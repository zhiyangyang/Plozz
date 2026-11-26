import Foundation
import Observation
import CoreModels

/// Drives the Search screen: holds the live query, debounces input, runs the
/// provider search, and guards against stale (out-of-order) responses.
///
/// The owning view binds `query` to a `.searchable` field and re-runs `search()`
/// via `.task(id: query)`, so SwiftUI cancels the previous in-flight task each
/// time the query changes. The debounce + cancellation checks here turn that
/// into a single trailing-edge request per pause in typing.
@MainActor
@Observable
public final class SearchViewModel {
    public var query: String = ""
    public private(set) var state: LoadState<[SearchSection]> = .idle

    private let accounts: [ResolvedAccount]
    private let limit: Int
    private let debounce: Duration
    private let diagnostics: PerformanceDiagnostics
    private let searchDiagnostics: SearchDiagnosticJournal
    /// Shared identity-index lookup folded into dedup so each result card carries
    /// its full cross-server source set even before the detail picker probes.
    private let identitySources: @Sendable (MediaItem) -> [MediaSourceRef]
    /// The profile's app-wide **disabled** library keys (`"accountID:libraryID"`),
    /// read fresh per search so a disabled library is kept out of results. Empty
    /// (the default) means every library is searchable — the zero-cost common path.
    /// Called only on the main actor (its `Set` result — `Sendable` — is what the
    /// per-account search tasks capture), so it needn't be `@Sendable` itself.
    private let disabledLibraryKeys: () -> Set<String>

    public init(
        accounts: [ResolvedAccount],
        limit: Int = 40,
        debounceMilliseconds: Int = 350,
        identitySources: @escaping @Sendable (MediaItem) -> [MediaSourceRef] = { _ in [] },
        disabledLibraryKeys: @escaping () -> Set<String> = { [] },
        diagnostics: PerformanceDiagnostics = .shared,
        searchDiagnostics: SearchDiagnosticJournal = .shared
    ) {
        self.accounts = accounts
        self.limit = limit
        self.debounce = .milliseconds(debounceMilliseconds)
        self.identitySources = identitySources
        self.disabledLibraryKeys = disabledLibraryKeys
        self.diagnostics = diagnostics
        self.searchDiagnostics = searchDiagnostics
    }

    /// Runs a debounced search for the current `query`. Safe to call on every
    /// keystroke via `.task(id: query)`: an empty query resets to idle, and a
    /// query that changes mid-flight discards the obsolete result.
    public func search() async {
        let requested = SearchPolicy.normalized(query)

        guard SearchPolicy.shouldSearch(requested) else {
            state = .idle
            return
        }

        // Trailing-edge debounce: wait out the typing burst. If the query
        // changes, `.task(id:)` cancels this task and `Task.sleep` throws.
        do {
            try await Task.sleep(for: debounce)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let span = diagnostics.begin(.search, metrics: .init(accounts: accounts.count))
        var outcome = PerformanceDiagnostics.Outcome.cancelled
        var metrics = PerformanceDiagnostics.Metrics()
        defer { span?.finish(Task.isCancelled ? .cancelled : outcome, metrics: metrics) }
        state = .loading

        // The library search may throw only when EVERY account fails; capture that
        // rather than throwing so the view can distinguish failure from no results.
        var libraryItems: [MediaItem] = []
        var libraryError: AppError?
        do {
            libraryItems = try await aggregatedSearch(query: requested)
        } catch let error as AppError {
            libraryError = error
        } catch {
            libraryError = .unknown("")
        }

        guard SearchPolicy.isCurrent(requestedQuery: requested, liveQuery: query) else { return }

        let serverInfo = accounts.sourceServerInfo()
        let dedupedLibrary = SearchDeduplicator.deduplicate(
            libraryItems,
            identitySources: identitySources,
            serverInfo: { serverInfo[$0] }
        )
        let sections = SearchSection.sections(from: dedupedLibrary)
        outcome = libraryError == nil ? .succeeded : .failed
        metrics = .init(items: sections.reduce(0) { $0 + $1.items.count }, rows: sections.count)

        if !sections.isEmpty {
            state = .loaded(sections)
        } else if let libraryError {
            // Nothing to show and the library search failed outright — surface
            // the error instead of presenting the failure as an empty library.
            state = .failed(libraryError)
        } else {
            state = .empty
        }
    }

    /// Applies a watched-state mutation to the loaded result sections **in place**
    /// so affected cards just flip their watched badge, keeping the grid and the
    /// user's focus stable (no re-search).
    public func applyWatchedState(_ mutation: MediaItemMutation) {
        guard case let .loaded(sections) = state else { return }
        state = .loaded(sections.map { section in
            SearchSection(kind: section.kind, items: section.items.map { item in
                mutation.applied(to: item)
            })
        })
    }

    /// Searches every active account concurrently and round-robin interleaves the
    /// per-account hits, tagging each with its owning account so a tapped result
    /// routes to the right provider. Resilient: if some accounts fail their hits
    /// are simply omitted; only when **every** account fails is the error
    /// surfaced, so a single server being down still shows results from the rest.
    private func aggregatedSearch(query: String) async throws -> [MediaItem] {
        let perAccountLimit = limit
        // Snapshot the disabled-library keys once for this search so results from a
        // library the user turned off app-wide are excluded. Only accounts that
        // actually have a disabled library take the scoped path (see providers).
        let disabledKeys = disabledLibraryKeys()
        let diagnosticSearch = searchDiagnostics.beginSearch()
        let results = await withTaskGroup(of: (Int, Result<[MediaItem], AppError>).self) { group in
            for (index, resolved) in accounts.enumerated() {
                group.addTask {
                    let accountID = resolved.account.id
                    let disabledForAccount: [String] = disabledKeys.compactMap { key in
                        let prefix = "\(accountID):"
                        return key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
                    }
                    let diagnostic = diagnosticSearch?.source(
                        index: index, provider: resolved.provider.kind,
                        limit: perAccountLimit, disabledLibraries: disabledForAccount.count
                    )
                    do {
                        if let interactive = resolved.provider as? any InteractiveBrowseActivityReporting {
                            await interactive.noteInteractiveBrowseActivity()
                        }
                        let hits = try await SearchDiagnosticJournal.$currentSource.withValue(diagnostic) {
                            try await PerformanceDiagnostics.$provider.withValue(resolved.provider.kind) {
                                try await resolved.provider.search(query: query, limit: perAccountLimit,
                                                                   excludingLibraries: disabledForAccount)
                            }
                        }
                        diagnostic?.finish(resultCount: hits.count)
                        return (index, .success(hits.map { $0.taggingSource(accountID) }))
                    } catch let error as AppError {
                        diagnostic?.finish(error: error)
                        return (index, .failure(error))
                    } catch {
                        diagnostic?.finish(error: error is CancellationError ? .cancelled : .unknown(""))
                        return (index, .failure(.unknown("")))
                    }
                }
            }
            var byIndex: [Int: Result<[MediaItem], AppError>] = [:]
            for await (index, result) in group { byIndex[index] = result }
            return accounts.indices.map { byIndex[$0] ?? .success([]) }
        }

        var groups: [[MediaItem]] = []
        var firstError: AppError?
        var anySuccess = false
        for result in results {
            switch result {
            case let .success(hits):
                groups.append(hits)
                anySuccess = true
            case let .failure(error):
                if firstError == nil { firstError = error }
            }
        }
        if !anySuccess, let firstError { throw firstError }
        return Self.interleave(groups)
    }

    /// Round-robin interleave preserving each account's relevance order.
    static func interleave<T>(_ groups: [[T]]) -> [T] {
        let maxCount = groups.map(\.count).max() ?? 0
        var result: [T] = []
        for offset in 0..<maxCount {
            for group in groups where offset < group.count {
                result.append(group[offset])
            }
        }
        return result
    }
}
