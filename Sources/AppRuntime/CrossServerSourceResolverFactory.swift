import CoreModels
import CoreNetworking
import Foundation

private func searchWithDeadline(
    _ provider: any MediaProvider,
    query: String,
    limit: Int,
    seconds: Double,
    excludingLibraries: [String] = []
) async -> [MediaItem] {
    let searchTask = Task {
        let items = (try? await provider.search(
            query: query, limit: limit, excludingLibraries: excludingLibraries
        )) ?? []
        guard provider.catalogIdentityRequiresEnrichment else { return items }
        let prepared = await IdentityEnrichment.prepare(items, enrichIdentifiedItems: true) { item in
            try await provider.item(id: item.id)
        }
        guard !Task.isCancelled else { return [] }
        if prepared.inconclusive {
            FanoutDiagnostics.emit("source.search incomplete identities provider=\(provider.kind.rawValue)")
        }
        let fullByID = Dictionary(
            prepared.indexable.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return items.compactMap { item in
            guard item.kind == .movie || item.kind == .series else { return item }
            guard var full = fullByID[item.id] else { return nil }
            full.libraryID = item.libraryID ?? full.libraryID
            full.sourceAccountID = item.sourceAccountID ?? full.sourceAccountID
            return full
        }
    }
    // Dispatch keeps the deadline responsive even when cooperative tasks are saturated.
    let timeout = DispatchWorkItem { searchTask.cancel() }
    DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + seconds,
        execute: timeout
    )
    let result = await withTaskCancellationHandler {
        await searchTask.value
    } onCancel: {
        searchTask.cancel()
    }
    timeout.cancel()
    return result
}

/// Builds the shared on-demand cross-server source probe used by both app shells.
public func crossServerSourceResolver(
    in accounts: [ResolvedAccount],
    identitySources: @escaping @Sendable (MediaItem) -> [MediaSourceRef]
) -> (@Sendable (MediaItem) async -> CrossServerSourceResolution)? {
    guard !accounts.isEmpty else { return nil }
    let serverInfo = accounts.sourceServerInfo()
    let orderedAccountIDs = accounts.map(\.account.id)
    let providersByAccountID: [String: any MediaProvider] = Dictionary(
        accounts.map { ($0.account.id, $0.provider) },
        uniquingKeysWith: { first, _ in first }
    )
    return { primary in
        await CrossServerSourceResolver.resolveWithEvidence(
            primary: primary,
            otherAccountIDs: orderedAccountIDs,
            search: { accountID, query in
                guard let provider = providersByAccountID[accountID] else { return [] }
                return await searchWithDeadline(
                    provider,
                    query: query,
                    limit: 25,
                    seconds: 4
                )
            },
            serverInfo: { serverInfo[$0] },
            identitySources: identitySources
        )
    }
}

/// Recovers only curated hero titles missing from the index, never the full
/// Discovery candidate feed. Search suggestions still require live verification.
public func heroLibraryTargetResolver(
    in accounts: [ResolvedAccount],
    identitySources: @escaping @Sendable (MediaItem) -> [MediaSourceRef],
    visibility: @escaping @Sendable () async -> HomeLibraryVisibility = { .default }
) -> (@Sendable (MediaItem) async -> MediaItem?)? {
    guard !accounts.isEmpty else { return nil }
    let serverInfo = accounts.sourceServerInfo()
    return { item in
        guard !Task.isCancelled, !item.locallyValidatedPlayableSource,
              item.kind == .movie || item.kind == .series,
              MediaItemIdentity.hasStrongRetargetIdentity(item),
              identitySources(item).isEmpty else { return nil }
        let initialVisibility = await visibility()
        let recovered = await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    let prefix = "\(account.account.id):"
                    let disabled = initialVisibility.disabledKeys.compactMap {
                        $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil
                    }.sorted()
                    let lookup = Task<MediaItem?, Never> {
                        let resolution = await CrossServerSourceResolver.resolveWithEvidence(
                            primary: item, otherAccountIDs: [account.account.id],
                            search: { _, query in
                                await searchWithDeadline(
                                    account.provider, query: query, limit: 25, seconds: 4,
                                    excludingLibraries: disabled
                                )
                            },
                            serverInfo: { serverInfo[$0] }
                        )
                        guard !Task.isCancelled, !resolution.sources.isEmpty else { return nil }
                        let verification = HeroDiscoveryRuntime(
                            accounts: [account], identitySources: { _ in resolution.sources }
                        )
                        let verified = await verification.resolveLibrarySources(
                            in: [item], visibility: initialVisibility
                        )
                        return verified.first(where: \.locallyValidatedPlayableSource)
                    }
                    // Each account shares one budget across title variants and
                    // verification. A slow account cannot erase a verified peer.
                    let deadline = DispatchWorkItem { lookup.cancel() }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4, execute: deadline)
                    let result = await withTaskCancellationHandler {
                        await lookup.value
                    } onCancel: {
                        lookup.cancel()
                    }
                    deadline.cancel()
                    guard !Task.isCancelled else { return (index, nil) }
                    guard !lookup.isCancelled else {
                        PlozzLog.app.error("Hero library recovery timed out for an account; its copy remains unverified.")
                        return (index, nil)
                    }
                    return (index, result)
                }
            }
            var byIndex: [Int: MediaItem] = [:]
            for await (index, result) in group { byIndex[index] = result }
            return accounts.indices.compactMap { byIndex[$0] }
        }
        guard await visibility() == initialVisibility, !Task.isCancelled else { return nil }
        var verified: [MediaItem] = []
        for copy in recovered {
            guard !verified.contains(where: {
                MediaIdentityVerification.hasConflictingStrongIdentity($0, copy)
            }) else {
                PlozzLog.app.error("Hero library recovery ignored conflicting cross-account identity.")
                continue
            }
            verified.append(copy)
        }
        guard !verified.isEmpty else { return nil }
        return MediaItemMerger.mergeGroup(verified)
    }
}

/// A cross-account library search for the Related row: one query fanned out to
/// every signed-in server, results pooled.
///
/// Pooled rather than per-account because a related title only has to exist
/// *somewhere* the viewer can reach. Which server holds it is the detail page's
/// problem once they open it, not this row's.
///
/// The same short deadline as the cross-server probe applies: a cold or unreachable
/// server must not hold up a row that is, by design, supplementary.
