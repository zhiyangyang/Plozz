import Foundation
import Observation

/// Persists `HomeLibraryVisibility` across launches.
public protocol HomeLibraryVisibilityStoring: Sendable {
    func load() -> HomeLibraryVisibility
    func save(_ visibility: HomeLibraryVisibility)
    func loadServerDefaults() -> CachedHomeRowDefaults?
    func saveServerDefaults(_ snapshot: CachedHomeRowDefaults)
}

public extension HomeLibraryVisibilityStoring {
    func loadServerDefaults() -> CachedHomeRowDefaults? { nil }
    func saveServerDefaults(_ snapshot: CachedHomeRowDefaults) {}
}

public final class HomeLibraryVisibilityStore: HomeLibraryVisibilityStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    /// - Parameter namespace: per-profile scope. `nil` (the default/primary
    ///   profile) uses the legacy un-suffixed key so upgrading installs keep
    ///   their Home customization; other profiles pass their `Profile.id` so each
    ///   profile gets its own independent set of hidden libraries.
    public init(defaults: UserDefaults = .standard, namespace: String? = nil) {
        self.defaults = defaults
        self.key = SettingsKey.scoped("com.plozz.homeLibraryVisibility", namespace: namespace)
    }

    public func load() -> HomeLibraryVisibility {
        guard let data = defaults.data(forKey: key),
              let visibility = try? JSONDecoder().decode(HomeLibraryVisibility.self, from: data) else {
            return .default
        }
        return visibility
    }

    public func save(_ visibility: HomeLibraryVisibility) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(visibility) {
            defaults.set(data, forKey: key)
        }
    }

    public func loadServerDefaults() -> CachedHomeRowDefaults? {
        guard let data = defaults.data(forKey: key + ".serverDefaults") else { return nil }
        return try? JSONDecoder().decode(CachedHomeRowDefaults.self, from: data)
    }

    public func saveServerDefaults(_ snapshot: CachedHomeRowDefaults) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key + ".serverDefaults")
        }
    }
}

/// Observable wrapper so the Settings checklist can two-way bind the per-library
/// toggles (enabled + show-on-home) and the merge switch, and have each choice
/// persisted immediately + broadcast to Home / Search / Music.
@MainActor
@Observable
public final class HomeLibraryVisibilityModel {
    public let sectionDiagnostics = HomeSectionDiagnosticsModel()
    public private(set) var visibility: HomeLibraryVisibility
    public private(set) var serverMatchFailures: [String: AppError] = [:]
    public private(set) var rowDefaultsRevision = UUID()

    private let store: HomeLibraryVisibilityStoring
    @ObservationIgnored private var cachedServerDefaults: CachedHomeRowDefaults?
    @ObservationIgnored private var lastServerCheck: Date?
    @ObservationIgnored private var lastServerCheckScope: [String] = []
    @ObservationIgnored private var serverRequestScope: [String] = []
    @ObservationIgnored private var serverRequestID = UUID()
    @ObservationIgnored private var serverRequest: Task<[String: Result<ServerHomeLayout?, AppError>], Never>?
    /// A cache-only refresh runs after Home has been given its cached layout. It
    /// must never publish into `visibility` while a Home load is in flight.
    @ObservationIgnored private var serverDefaultsRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var serverDefaultsRefreshID = UUID()
    @ObservationIgnored private var serverDefaultsRefreshScope: [String] = []

    public init(store: HomeLibraryVisibilityStoring = HomeLibraryVisibilityStore()) {
        self.store = store
        self.visibility = store.load()
        self.cachedServerDefaults = store.loadServerDefaults()
    }

    /// Applies the persisted server layout synchronously when it belongs to the
    /// current accounts. Home calls this before constructing its view model so the
    /// first frame can plan server rows without a layout round trip.
    public func applyCachedServerDefaults(accounts: [ResolvedAccount]) {
        guard visibility.rowCustomization?.defaults == .matchServer,
              let cached = cachedServerDefaults,
              cached.scope == Self.serverDefaultsScope(accounts: accounts)
        else { return }
        visibility.rowCustomization?.resolvedDefaults = cached.defaults
    }

    /// Called only by a real Home refresh or the open arranger, never a timer.
    ///
    /// A matching persisted layout is applied immediately. Its refresh runs in the
    /// background and updates only the cache for the next load, so a cold launch
    /// never waits for an Emby/Jellyfin Home-layout round trip before requesting
    /// content. `forceRefresh` is for the row arranger, which needs current rows.
    public func prepareServerDefaults(
        accounts: [ResolvedAccount], now: Date = Date(), forceRefresh: Bool = false
    ) async {
        guard visibility.rowCustomization?.defaults == .matchServer else { return }
        let sources = accounts.sorted { $0.account.id < $1.account.id }
        let scope = Self.serverDefaultsScope(accounts: sources)
        // Effective revisions fence live work, but are not persisted: Plex Home
        // overrides get new revisions after a relaunch for the same viewer.
        let requestScope = Self.serverDefaultsRequestScope(accounts: sources, scope: scope)
        if !forceRefresh,
           let cached = cachedServerDefaults,
           cached.scope == scope {
            // A pending request for another viewer/credential revision must not
            // publish over the cached layout this caller is now using.
            if serverRequestScope != requestScope {
                serverRequest?.cancel()
                serverRequest = nil
                serverRequestID = UUID()
            }
            if serverDefaultsRefreshScope != requestScope {
                serverDefaultsRefreshTask?.cancel()
                serverDefaultsRefreshTask = nil
                serverDefaultsRefreshID = UUID()
                serverDefaultsRefreshScope = []
            }
            if serverRequest == nil { serverMatchFailures = [:] }
            visibility.rowCustomization?.resolvedDefaults = cached.defaults
            // Do not refresh here. The layout request is itself a pair of Emby
            // round trips; racing it with the first Home aggregation starved the
            // content rows on a real LAN server. Home asks for this refresh after
            // its live load settles.
            return
        }
        if !forceRefresh,
           scope == cachedServerDefaults?.scope,
           requestScope == lastServerCheckScope,
           let lastServerCheck, now.timeIntervalSince(lastServerCheck) < 120 {
            serverRequest?.cancel()
            serverRequest = nil
            serverRequestID = UUID()
            serverMatchFailures = [:]
            visibility.rowCustomization?.resolvedDefaults = cachedServerDefaults?.defaults
            return
        }
        serverDefaultsRefreshTask?.cancel()
        serverDefaultsRefreshTask = nil
        serverDefaultsRefreshID = UUID()
        serverDefaultsRefreshScope = []
        var seen = Set<[String]>()
        let representatives = sources.filter {
            seen.insert([
                $0.account.server.provider.rawValue, $0.account.server.identityKey,
                $0.provider.session.userID, $0.plexHomeUserID.map { "home:\($0)" } ?? "owner"
            ]).inserted
        }
        guard !representatives.isEmpty else {
            serverRequestID = UUID()
            acceptServerDefaults(
                .init(mode: .providerFallback), scope: scope, requestScope: requestScope, now: now
            )
            return
        }
        visibility.rowCustomization?.resolvedDefaults =
            cachedServerDefaults?.scope == scope ? cachedServerDefaults?.defaults : nil
        let request: Task<[String: Result<ServerHomeLayout?, AppError>], Never>
        if serverRequestScope == requestScope, let pending = serverRequest {
            request = pending
        } else {
            serverRequest?.cancel()
            serverRequestID = UUID()
            if serverRequestScope != requestScope { serverMatchFailures = [:] }
            serverRequestScope = requestScope
            request = Task { await Self.loadServerLayouts(representatives) }
            serverRequest = request
        }
        let requestID = serverRequestID
        let results = await request.value
        guard !Task.isCancelled, serverRequestID == requestID,
              visibility.rowCustomization?.defaults == .matchServer else { return }
        serverRequest = nil
        let previous = cachedServerDefaults?.scope == scope ? cachedServerDefaults?.defaults : nil
        guard let resolved = Self.resolvedServerDefaults(
            results, representatives: representatives, previous: previous
        ) else { return }
        if representatives.count == 1, !resolved.failures.isEmpty {
            serverMatchFailures = resolved.failures
            return
        }
        acceptServerDefaults(
            resolved.defaults, scope: scope, requestScope: requestScope, now: now
        )
        serverMatchFailures = resolved.failures
        if !resolved.failures.isEmpty { lastServerCheck = nil }
    }

    /// Refresh the persisted layout without changing live visibility. Home calls
    /// this only after its first live load has settled, so the layout's Emby round
    /// trips cannot compete with the content rows the viewer is waiting for.
    public func refreshServerDefaultsCacheOnly(accounts: [ResolvedAccount]) async {
        guard visibility.rowCustomization?.defaults == .matchServer,
              let cached = cachedServerDefaults
        else { return }
        let sources = accounts.sorted { $0.account.id < $1.account.id }
        let scope = Self.serverDefaultsScope(accounts: sources)
        guard cached.scope == scope else { return }
        let requestScope = Self.serverDefaultsRequestScope(accounts: sources, scope: scope)
        if let existing = serverDefaultsRefreshTask {
            if serverDefaultsRefreshScope == requestScope {
                await existing.value
                return
            }
            existing.cancel()
            serverDefaultsRefreshTask = nil
            serverDefaultsRefreshID = UUID()
            serverDefaultsRefreshScope = []
        }
        guard let task = scheduleServerDefaultsRefreshIfNeeded(
            accounts: sources, scope: scope, requestScope: requestScope,
            previous: cached.defaults, now: Date(), ignoringRecentCheck: true
        ) else { return }
        await task.value
    }

    @discardableResult
    private func scheduleServerDefaultsRefreshIfNeeded(
        accounts: [ResolvedAccount], scope: [String], requestScope: [String],
        previous: HomeResolvedRowDefaults, now: Date, ignoringRecentCheck: Bool = false
    ) -> Task<Void, Never>? {
        guard accounts.isEmpty == false,
              serverRequest == nil,
              serverDefaultsRefreshTask == nil
        else { return serverDefaultsRefreshTask }
        if !ignoringRecentCheck,
           requestScope == lastServerCheckScope,
           let lastServerCheck, now.timeIntervalSince(lastServerCheck) < 120 {
            return nil
        }
        var seen = Set<[String]>()
        let representatives = accounts.filter {
            seen.insert([
                $0.account.server.provider.rawValue, $0.account.server.identityKey,
                $0.provider.session.userID, $0.plexHomeUserID.map { "home:\($0)" } ?? "owner"
            ]).inserted
        }
        guard !representatives.isEmpty else { return nil }
        let refreshID = UUID()
        serverDefaultsRefreshID = refreshID
        serverDefaultsRefreshScope = requestScope
        let task = Task { [weak self] in
            let results = await Self.loadServerLayouts(representatives)
            guard let self, !Task.isCancelled,
                  self.serverDefaultsRefreshID == refreshID
            else { return }
            self.serverDefaultsRefreshTask = nil
            self.serverDefaultsRefreshScope = []
            guard self.visibility.rowCustomization?.defaults == .matchServer,
                  let resolved = Self.resolvedServerDefaults(
                    results, representatives: representatives, previous: previous
                  ),
                  resolved.failures.isEmpty
            else { return }
            let snapshot = CachedHomeRowDefaults(scope: scope, defaults: resolved.defaults)
            if self.cachedServerDefaults != snapshot {
                self.store.saveServerDefaults(snapshot)
            }
            self.cachedServerDefaults = snapshot
            self.lastServerCheck = Date()
            self.lastServerCheckScope = requestScope
        }
        serverDefaultsRefreshTask = task
        return task
    }

    private nonisolated static func serverDefaultsScope(
        accounts: [ResolvedAccount]
    ) -> [String] {
        ["server-home-v2"] + accounts.sorted { $0.account.id < $1.account.id }.flatMap {
            [$0.account.id, $0.account.server.provider.rawValue,
             $0.account.server.identityKey, $0.provider.session.userID,
             $0.plexHomeUserID.map { "home:\($0)" } ?? "owner"]
        }
    }

    private nonisolated static func serverDefaultsRequestScope(
        accounts: [ResolvedAccount], scope: [String]
    ) -> [String] {
        scope + accounts.sorted { $0.account.id < $1.account.id }
            .map { $0.credentialRevision.rawValue.uuidString }
    }

    private nonisolated static func resolvedServerDefaults(
        _ results: [String: Result<ServerHomeLayout?, AppError>],
        representatives: [ResolvedAccount],
        previous: HomeResolvedRowDefaults?
    ) -> (defaults: HomeResolvedRowDefaults, failures: [String: AppError])? {
        var resolved = HomeResolvedRowDefaults(mode: representatives.count > 1 ? .combined : .server)
        var failures: [String: AppError] = [:]
        for source in representatives {
            switch results[source.account.id] ?? .failure(.cancelled) {
            case let .success(layout?):
                resolved.serverRows += layout.sections.map {
                    HomeServerRowDefinition(
                        accountID: source.account.id, serverName: source.account.server.name,
                        providerKind: source.account.server.provider, section: $0
                    )
                }
                resolved.omitsMusic = resolved.omitsMusic || layout.omitsMusic
                resolved.omitsReading = resolved.omitsReading || layout.omitsReading
                if representatives.count == 1 { resolved.source = layout.source }
            case .success(nil):
                resolved.fallbackAccountIDs.insert(source.account.id)
            case let .failure(error):
                guard error != .cancelled else { return nil }
                failures[source.account.id] = error
                let retained = previous?.serverRows.filter { $0.accountID == source.account.id } ?? []
                resolved.serverRows += retained
                if previous == nil || previous?.fallbackAccountIDs.contains(source.account.id) == true {
                    resolved.fallbackAccountIDs.insert(source.account.id)
                }
                resolved.omitsMusic = resolved.omitsMusic || previous?.omitsMusic == true
                resolved.omitsReading = resolved.omitsReading || previous?.omitsReading == true
            }
        }
        if resolved.mode == .combined {
            let shared = HomeRowChoice.shared.map(\.id)
            let native = resolved.serverRows.map(\.id).filter { !shared.contains($0) }
            resolved.order = shared.filter { $0 != .libraries }
                + native + [.libraries]
        } else if !resolved.fallbackAccountIDs.isEmpty {
            resolved.mode = .providerFallback
        } else {
            resolved.order = resolved.serverRows.map(\.id)
        }
        var ordered = Set<HomeRowID>()
        resolved.order = resolved.order.filter { ordered.insert($0).inserted }
        return (resolved, failures)
    }

    private nonisolated static func loadServerLayouts(
        _ sources: [ResolvedAccount]
    ) async -> [String: Result<ServerHomeLayout?, AppError>] {
        await withTaskGroup(of: (String, Result<ServerHomeLayout?, AppError>).self) { group in
            var next = 0
            func enqueue() {
                guard next < sources.count, !Task.isCancelled else { return }
                let source = sources[next]
                next += 1
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        return (source.account.id, .success(try await source.provider.serverHomeLayout()))
                    } catch is CancellationError {
                        return (source.account.id, .failure(.cancelled))
                    } catch {
                        return (source.account.id, .failure((error as? AppError) ?? .invalidResponse))
                    }
                }
            }
            for _ in 0..<min(3, sources.count) { enqueue() }
            var results: [String: Result<ServerHomeLayout?, AppError>] = [:]
            while let (id, result) = await group.next() {
                results[id] = result
                enqueue()
            }
            return results
        }
    }

    private func acceptServerDefaults(
        _ defaults: HomeResolvedRowDefaults, scope: [String], requestScope: [String], now: Date
    ) {
        serverRequest?.cancel()
        serverRequest = nil
        serverDefaultsRefreshTask?.cancel()
        serverDefaultsRefreshTask = nil
        serverDefaultsRefreshID = UUID()
        serverDefaultsRefreshScope = []
        serverMatchFailures = [:]
        lastServerCheck = now
        lastServerCheckScope = requestScope
        let snapshot = CachedHomeRowDefaults(scope: scope, defaults: defaults)
        if cachedServerDefaults != snapshot { store.saveServerDefaults(snapshot) }
        cachedServerDefaults = snapshot
        visibility.rowCustomization?.resolvedDefaults = defaults
    }

    public func applyRows(
        _ sections: OrderedVisibilityList.Sections<HomeRowID>, choices: [HomeRowChoice]
    ) {
        visibility.applyRows(sections, choices: choices)
        store.save(visibility)
    }

    public func setHomeRowName(_ name: String, for id: HomeRowID) {
        var updated = visibility
        updated.setHomeRowName(name, for: id)
        guard updated != visibility else { return }
        visibility = updated
        store.save(visibility)
    }

    public func setEmptyHomeRowDismissed(_ dismissed: Bool, id: HomeRowID) {
        guard visibility.dismissedEmptyHomeRows.contains(id) != dismissed else { return }
        if dismissed {
            visibility.dismissedEmptyHomeRows.insert(id)
        } else {
            visibility.dismissedEmptyHomeRows.remove(id)
        }
        store.save(visibility)
    }

    public func setHomeSectionVisible(
        _ visible: Bool, id: HomeRowID, catalog: HomeSectionCatalog
    ) throws {
        let updated = try catalog.settingVisible(visible, id: id, in: visibility)
        guard updated != visibility else { return }
        visibility = updated
        store.save(visibility)
    }

    public func reorderHomeSections(_ order: [HomeRowID], catalog: HomeSectionCatalog) throws {
        let updated = try catalog.reordering(order, in: visibility)
        guard updated != visibility else { return }
        visibility = updated
        store.save(visibility)
    }

    public func saveCollectionSection(_ section: CollectionSection, catalog: HomeSectionCatalog) throws {
        guard !section.id.isEmpty, !section.sources.isEmpty, section.sources.allSatisfy(\.isValid),
              !section.title.isEmpty else { throw AppError.invalidResponse }
        var updated = visibility
        if let index = updated.collectionSections.firstIndex(where: { $0.id == section.id }) {
            updated.collectionSections[index] = section
        } else {
            updated.collectionSections.append(section)
        }
        let choices = catalog.availableChoices(in: updated)
        guard choices.contains(where: { $0.id == section.rowID }) else { throw AppError.notFound }
        var sections = catalog.sections(in: updated)
        sections.disabled.removeAll { $0 == section.rowID }
        if !sections.enabled.contains(section.rowID) {
            let index = sections.enabled.firstIndex(of: .libraries) ?? sections.enabled.endIndex
            sections.enabled.insert(section.rowID, at: index)
        }
        updated.applyRows(sections, choices: choices)
        visibility = updated
        store.save(visibility)
    }

    public func useRowDefaults(_ defaults: HomeRowCustomization.Defaults) {
        serverRequest?.cancel()
        serverRequest = nil
        serverDefaultsRefreshTask?.cancel()
        serverDefaultsRefreshTask = nil
        serverDefaultsRefreshID = UUID()
        serverDefaultsRefreshScope = []
        serverRequestID = UUID()
        visibility.rowCustomization = HomeRowCustomization(defaults: defaults)
        rowDefaultsRevision = UUID()
        serverMatchFailures = [:]
        store.save(visibility)
    }

    // MARK: - Merge

    /// Whether Home merges every library into unified cross-server rows.
    public var mergeLibrariesOnHome: Bool {
        visibility.mergeLibrariesOnHome
    }

    /// Sets the all-or-nothing "merge libraries on Home" switch and persists.
    public func setMergeLibrariesOnHome(_ merge: Bool) {
        guard visibility.mergeLibrariesOnHome != merge else { return }
        visibility.mergeLibrariesOnHome = merge
        store.save(visibility)
    }

    // MARK: - Global Home rows

    /// Whether a global Home row (Continue Watching / Watchlist / Recently Added)
    /// is shown (default on).
    public func isGlobalRowEnabled(_ row: HomeGlobalRow) -> Bool {
        visibility.isGlobalRowEnabled(row)
    }

    /// Shows/hides a global Home row and persists.
    public func setGlobalRowEnabled(_ enabled: Bool, for row: HomeGlobalRow) {
        visibility.setGlobalRowEnabled(enabled, for: row)
        store.save(visibility)
    }

    /// Whether Continue Watching identifies cards by show artwork + logo (default
    /// on) rather than by the episode thumbnail.
    public var continueWatchingShowsSeriesArtwork: Bool {
        visibility.continueWatchingShowsSeriesArtwork
    }

    public var continueWatchingUsesSeriesArtwork: Bool {
        visibility.continueWatchingUsesSeriesArtwork
    }

    public var continueWatchingLayout: ContinueWatchingCardLayout {
        visibility.continueWatchingLayout
    }

    public var continueWatchingPlaybackDetails: ContinueWatchingPlaybackDetails {
        visibility.continueWatchingPlaybackDetails
    }

    public var continueWatchingAction: ContinueWatchingAction {
        visibility.continueWatchingAction
    }

    public func setContinueWatchingAction(_ action: ContinueWatchingAction) {
        guard visibility.continueWatchingAction != action else { return }
        visibility.continueWatchingAction = action
        store.save(visibility)
    }

    public func setContinueWatchingPlaybackDetails(_ details: ContinueWatchingPlaybackDetails) {
        guard visibility.continueWatchingPlaybackDetails != details else { return }
        visibility.continueWatchingPlaybackDetails = details
        store.save(visibility)
    }

    public func setContinueWatchingLayout(_ layout: ContinueWatchingCardLayout) {
        guard visibility.continueWatchingLayout != layout else { return }
        visibility.continueWatchingLayout = layout
        store.save(visibility)
    }

    /// Sets the Continue Watching artwork treatment and persists.
    public func setContinueWatchingShowsSeriesArtwork(_ showsSeriesArtwork: Bool) {
        guard visibility.continueWatchingShowsSeriesArtwork != showsSeriesArtwork else { return }
        visibility.continueWatchingShowsSeriesArtwork = showsSeriesArtwork
        store.save(visibility)
    }

    public func setMergeNextUpIntoContinueWatching(_ merge: Bool) {
        guard visibility.mergeNextUpIntoContinueWatching != merge else { return }
        visibility.mergeNextUpIntoContinueWatching = merge
        store.save(visibility)
    }

    public func setHideWatchedRecentlyAdded(_ hide: Bool) {
        guard visibility.hideWatchedRecentlyAdded != hide else { return }
        visibility.hideWatchedRecentlyAdded = hide
        store.save(visibility)
    }

    // MARK: - Per-library Home rows (unmerged, opt-in)

    /// Whether a per-library row is opted in to Home (default off).
    public func isLibraryRowEnabled(_ libraryKey: String, kind: LibraryHomeRowKind) -> Bool {
        visibility.isLibraryRowEnabled(libraryKey, kind: kind)
    }

    /// Opts a per-library row in/out of Home and persists.
    public func setLibraryRowEnabled(_ enabled: Bool, libraryKey: String, kind: LibraryHomeRowKind) {
        visibility.setLibraryRowEnabled(enabled, libraryKey: libraryKey, kind: kind)
        store.save(visibility)
    }

    /// Seeds all provided per-library rows **on** the first time the user
    /// unmerges, then persists. Called when the merge switch is turned **off** so
    /// the unmerged Home starts populated rather than empty (see
    /// ``HomeLibraryVisibility/seedLibraryRowsIfNeeded(_:)``). A no-op once the
    /// one-time seeding has run, so it never re-seeds over the user's row choices.
    public func seedLibraryRowsIfNeeded(_ rows: [(libraryKey: String, kind: LibraryHomeRowKind)]) {
        if visibility.seedLibraryRowsIfNeeded(rows) {
            store.save(visibility)
        }
    }

    // MARK: - Per-library predicates

    /// Whether the library is on (not disabled).
    public func isEnabled(_ key: String) -> Bool {
        visibility.isEnabled(key)
    }

    /// Whether the library appears on Home (now just ``isEnabled(_:)`` — the
    /// separate Home-only opt-out was retired).
    public func isVisibleOnHome(_ key: String) -> Bool {
        visibility.isVisibleOnHome(key)
    }

    public func isVisibleOnHome(_ key: String, library: MediaLibrary) -> Bool {
        visibility.isVisibleOnHome(key, library: library)
    }

    public func isVisibleOnHome(_ library: AggregatedLibrary) -> Bool {
        visibility.isVisibleOnHome(library)
    }

    /// Compatibility alias for ``isVisibleOnHome(_:)``.
    public func isVisible(_ key: String) -> Bool {
        visibility.isVisible(key)
    }

    // MARK: - Per-library mutation

    /// Turns a library on/off and persists immediately.
    public func setEnabled(_ enabled: Bool, for key: String) {
        visibility.setEnabled(enabled, for: key)
        store.save(visibility)
    }
}
