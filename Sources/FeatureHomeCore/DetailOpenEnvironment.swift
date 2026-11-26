import Foundation
import CoreModels
import CoreNetworking

public struct DetailOpeningResolution {
    let provider: any MediaProvider
    let item: MediaItem
    let sources: [MediaSourceRef]
    let resumeEpisode: MediaItem?
}

/// The single place both platform shells (tvOS `AppShell`, iOS `AppShelliOS`)
/// turn a tapped `MediaItem` into a fully-configured ``ItemDetailViewModel``.
///
/// Historically each navigation destination hand-rolled `ItemDetailViewModel(...)`
/// — ~7 near-identical call sites across two shells. When one platform gained a
/// reconciliation step (e.g. enriching `initialSources` from the identity index so
/// a Plex *watchlist* / Discover title resolves to its real library copies) and
/// the other didn't, the two silently diverged — which is how "open from
/// watchlist" worked on iOS but not tvOS. Routing every shell through this one
/// factory makes that class of divergence impossible: the item→viewModel glue
/// lives in exactly one place.
///
/// Each shell builds a `DetailOpenEnvironment` **once** from its own app model
/// (the closures below resolve providers, the identity index, cross-server
/// discovery, and the snapshot cache), then every destination calls ``makeViewModel(for:libraryOrigin:)`` /
/// ``makeSeriesContextViewModel(seriesID:seed:sourceAccountID:originAccountID:)``.
@MainActor
public struct DetailOpenEnvironment {
    /// Resolves an active provider, using the primary only for an untagged item.
    /// Missing sources must throw rather than substituting another server.
    public let resolveProvider: (_ accountID: String?) throws -> any MediaProvider
    /// Resolves an account id to its provider, or nil when that account isn't
    /// active (used to fetch alternate-server copies).
    public let resolveOptionalProvider: @Sendable (_ accountID: String) -> (any MediaProvider)?
    /// Maps an item to the library `MediaSourceRef`s the identity index knows host
    /// it (keyed by the item's provider guids), so a Discover/watchlist item with
    /// empty `sources` still resolves to real library copies.
    public let identitySources: @Sendable (MediaItem) -> [MediaSourceRef]
    /// The current profile's already-loaded Home resume state, read at open time.
    public let continueWatchingSnapshot: @MainActor () -> [MediaItem]
    /// Discovers *other servers* hosting the same title off the critical path, to
    /// fill the cross-server picker. `nil` disables cross-server discovery.
    public let crossServerSourceResolver: (@Sendable (MediaItem) async -> CrossServerSourceResolution)?
    /// Loads a series season's complete canonical episode metadata roster.
    /// `nil` leaves roster-backed season coverage unavailable.
    public let loadSeasonEpisodeRoster:
        (@Sendable (MediaItem, Int) async -> SeasonEpisodeRosterResult)?
    /// Stale-while-revalidate detail snapshot cache (instant repaint on revisit).
    public let snapshotCache: DetailSnapshotCache

    public init(
        resolveProvider: @escaping (_ accountID: String?) throws -> any MediaProvider,
        resolveOptionalProvider: @escaping @Sendable (_ accountID: String) -> (any MediaProvider)?,
        identitySources: @escaping @Sendable (MediaItem) -> [MediaSourceRef],
        crossServerSourceResolver: (@Sendable (MediaItem) async -> CrossServerSourceResolution)?,
        continueWatchingSnapshot: @escaping @MainActor () -> [MediaItem] = { [] },
        loadSeasonEpisodeRoster:
            (@Sendable (MediaItem, Int) async -> SeasonEpisodeRosterResult)? = nil,
        snapshotCache: DetailSnapshotCache = .ephemeral
    ) {
        self.resolveProvider = resolveProvider
        self.resolveOptionalProvider = resolveOptionalProvider
        self.identitySources = identitySources
        self.continueWatchingSnapshot = continueWatchingSnapshot
        self.crossServerSourceResolver = crossServerSourceResolver
        self.loadSeasonEpisodeRoster = loadSeasonEpisodeRoster
        self.snapshotCache = snapshotCache
    }

    /// The `initialSources` to seed a detail view model from a tapped item: the
    /// item's own sources merged (deduped) with the identity index's resolved
    /// library copies.
    ///
    /// Static so shells that build `ItemDetailViewModel` directly (iOS) share the
    /// exact merge rule rather than hand-rolling it, which would silently drift
    /// if the dedupe or ordering ever changed.
    public static func initialSources(
        for item: MediaItem,
        identitySources: (MediaItem) -> [MediaSourceRef]
    ) -> [MediaSourceRef] {
        let indexed = identitySources(item)
        var own: [MediaSourceRef] = []
        if let opening = openingSource(for: item) ?? contextSource(for: item) {
            var source = (item.sources + indexed).first {
                $0.accountID == opening.accountID && $0.itemID == opening.itemID
            } ?? MediaSourceRef(
                accountID: opening.accountID,
                itemID: opening.itemID,
                kind: item.kind
            )
            source.kind = item.kind
            source.libraryID = item.libraryID ?? source.libraryID
            source.edition = item.edition ?? source.edition
            if !item.versions.isEmpty {
                source.versions = item.versions
            } else if source.versions.isEmpty {
                source.versions = [MediaVersion.synthesized(from: item)]
            }
            source.resumePosition = item.resumePosition
            source.playedPercentage = item.playedPercentage
            source.unwatchedEpisodeCount = item.unwatchedEpisodeCount
            source.isPlayed = item.isPlayed
            source.hasBeenPlayed = item.hasBeenPlayed
            source.isFavorite = item.isFavorite
            source.lastPlayedAt = item.lastPlayedAt
            own = [source]
        }
        var seen = Set<String>()
        return (own + item.sources + indexed).filter { source in
            (!item.rejectedSourceIDs.contains(source.id) || own.contains { $0.id == source.id })
                && seen.insert(source.id).inserted
        }
    }

    /// Library grids preserve physical provider items; Home/Search aggregation
    /// stamps `isMergedTitle`. Only an independently listed, explicitly named
    /// edition expresses an item choice, never an arbitrary merged representative.
    public static func openingSource(for item: MediaItem) -> MediaItemSourceIdentity? {
        if let opening = item.editionOpeningSource { return opening }
        guard !item.isMergedTitle, item.locallyValidatedPlayableSource,
              item.kind == .movie,
              let edition = item.edition,
              !edition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let account = item.sourceAccountID else { return nil }
        return MediaItemSourceIdentity(accountID: account, itemID: item.id)
    }

    /// Direct episode pages and explicit season navigation keep provider-local
    /// child IDs on their owner. Ordinary episode taps reach us as a series seed.
    private static func contextSource(for item: MediaItem) -> MediaItemSourceIdentity? {
        guard item.kind == .episode || item.kind == .season
                || (item.kind == .series && item.seasonID != nil),
              let account = item.sourceAccountID else { return nil }
        return MediaItemSourceIdentity(accountID: account, itemID: item.id)
    }

    public func initialSources(for item: MediaItem) -> [MediaSourceRef] {
        Self.initialSources(for: item, identitySources: identitySources)
    }

    /// Membership-only index refs contain no progress. Selecting the same physical
    /// item must not erase the resume state that arrived on the tapped card.
    public static func initialItem(
        for item: MediaItem,
        selectedSource: MediaSourceRef?
    ) -> MediaItem {
        var item = item
        item.editionOpeningSource = openingSource(for: item)
        guard let selectedSource else { return item }
        if item.locallyValidatedPlayableSource,
           item.id == selectedSource.itemID,
           item.sourceAccountID == selectedSource.accountID {
            return item
        }
        return item.selectingSource(selectedSource)
    }

    /// Resolves the complete source set and chooses the page's server before a
    /// detail model exists. Shared by tvOS and iOS so neither platform can fall
    /// back to post-arrival retargeting.
    public static func initialSourceSelection(
        for item: MediaItem,
        libraryOrigin: String?,
        identitySources: (MediaItem) -> [MediaSourceRef],
        sourceLocality: (String) -> SourceLocality?,
        sourceIsAvailable: (String) -> Bool = { _ in true }
    ) -> (sources: [MediaSourceRef], selected: MediaSourceRef?) {
        let sources = initialSources(
            for: item,
            identitySources: identitySources
        ).filter { sourceIsAvailable($0.accountID) }.map { source in
            guard let locality = sourceLocality(source.accountID) else { return source }
            var liveSource = source
            liveSource.locality = locality
            return liveSource
        }.sorted { $0.id < $1.id }
        let opening = openingSource(for: item) ?? contextSource(for: item)
        let selected = sources.first(where: {
            $0.accountID == opening?.accountID && $0.itemID == opening?.itemID
        }) ?? CrossSourceSelector.bestSelection(
            from: sources,
            capabilities: .detected()
        )?.source
        return (sources, selected)
    }

    /// Build the detail view model for a tapped movie or series — including a Plex
    /// **watchlist** / Discover title (empty `sources`, Discover id), which the
    /// identity-index enrichment above resolves to its real library copies so the
    /// server picker and episodes work.
    ///
    /// - Parameter libraryOrigin: owning account for an untagged native seed,
    ///   not a preference that changes ordinary detail source selection.
    public func makeViewModel(for item: MediaItem, libraryOrigin: String?) throws -> ItemDetailViewModel {
        var item = item
        if item.sourceAccountID == nil { item.sourceAccountID = libraryOrigin }
        if let opening = Self.openingSource(for: item) ?? Self.contextSource(for: item) {
            _ = try resolveProvider(opening.accountID)
        }
        let identitySources = self.identitySources
        let resolveOptionalProvider = self.resolveOptionalProvider
        let liveIdentitySources: @Sendable (MediaItem) -> [MediaSourceRef] = { item in
            identitySources(item).filter { resolveOptionalProvider($0.accountID) != nil }
        }
        let indexedSources = liveIdentitySources(item)
        var routingItem = item
        routingItem.sources.removeAll { resolveOptionalProvider($0.accountID) == nil }
        let selection = Self.initialSourceSelection(
            for: routingItem,
            libraryOrigin: libraryOrigin,
            identitySources: { _ in indexedSources },
            sourceLocality: {
                resolveOptionalProvider($0)?.connectionLocality
            },
            sourceIsAvailable: {
                resolveOptionalProvider($0) != nil
            }
        )
        let sources = selection.sources
        let selectedSource = selection.selected
        var selectedItem = Self.initialItem(for: routingItem, selectedSource: selectedSource)
        selectedItem.sources = sources
        let resume = DetailPlaybackSelection.resumeItem(for: selectedItem, in: continueWatchingSnapshot())
        let seed = selectedItem
        let retargeted = seed.id != routingItem.id || seed.sourceAccountID != routingItem.sourceAccountID
        let expectedIdentity = retargeted ? routingItem : nil
        let openingResolver: @MainActor () async throws -> DetailOpeningResolution = {
            try await self.resolveOpening(for: seed, expectedIdentity: expectedIdentity)
        }
        return ItemDetailViewModel(
            provider: try resolveProvider(
                selectedSource?.accountID ?? item.sourceAccountID ?? libraryOrigin
            ),
            itemID: selectedSource?.itemID ?? item.id,
            initialItem: DetailPlaybackSelection.applyingResumeItem(resume, to: selectedItem),
            initialResumeEpisode: selectedItem.kind == .series ? resume : nil,
            loadSeasonEpisodeRoster: loadSeasonEpisodeRoster,
            sourceAccountID: selectedSource?.accountID ?? item.sourceAccountID ?? libraryOrigin,
            originSourceAccountID: Self.contextSource(for: selectedItem)?.accountID,
            initialSources: sources,
            alternateProviderResolver: resolveOptionalProvider,
            crossServerSourceResolver: crossServerSourceResolver,
            identitySources: liveIdentitySources,
            snapshotCache: snapshotCache,
            openingResolver: openingResolver,
            // Match upstream: the season rail loads when it is actually shown.
            // Eagerly fetching the opening season's episodes here starts a third
            // server round-trip during the push, competing with the page's first
            // paint (the entering freeze) and duplicating the rail's own load.
            prefetchesOpeningSeason: false
        )
    }

    /// Hydrate before resolving membership: episode-derived parent seeds do not
    /// carry the series' catalog IDs. Every route then uses the same source policy.
    private func resolveOpening(
        for seed: MediaItem, expectedIdentity: MediaItem?
    ) async throws -> DetailOpeningResolution {
        var provider = try resolveProvider(seed.sourceAccountID)
        var item = try await provider.item(id: seed.id)
        try Task.checkCancellation()
        guard item.id == seed.id, item.kind == seed.kind,
              seed.sourceAccountID == nil || item.sourceAccountID == nil
                || item.sourceAccountID == seed.sourceAccountID,
              !MediaItemIdentity.externalIdentitiesConflict(
                  expectedIdentity.map(MediaItemIdentity.identities(for:)) ?? [],
                  MediaItemIdentity.identities(for: item)
              ) else {
            throw AppError.invalidResponse
        }
        item.sourceAccountID = seed.sourceAccountID ?? item.sourceAccountID
        item.editionOpeningSource = seed.editionOpeningSource
        if item.kind == .series { item.seasonID = seed.seasonID }
        item.rejectedSourceIDs.formUnion(seed.rejectedSourceIDs)
        item.sources = (seed.sources + item.sources + identitySources(item)).map { source in
            var source = source
            source.providerKind = resolveOptionalProvider(source.accountID)?.kind ?? source.providerKind
            return source
        }
        if let account = item.sourceAccountID {
            var own = item.sources.first { $0.accountID == account && $0.itemID == item.id }
                ?? MediaSourceRef(accountID: account, itemID: item.id)
            own.kind = item.kind
            own.providerKind = provider.kind
            if !item.versions.isEmpty {
                own.versions = item.versions
            } else if [.movie, .episode, .video].contains(item.kind), item.mediaInfo != nil {
                own.versions = [MediaVersion.synthesized(from: item)]
            }
            own.edition = item.edition ?? own.edition
            item.sources = [own] + item.sources.filter { $0.id != own.id }
        }
        let selection = Self.initialSourceSelection(
            for: item, libraryOrigin: nil,
            identitySources: identitySources,
            sourceLocality: { resolveOptionalProvider($0)?.connectionLocality },
            sourceIsAvailable: { resolveOptionalProvider($0) != nil }
        )
        if let selected = selection.selected,
           selected.itemID != item.id || selected.accountID != item.sourceAccountID {
            provider = try resolveProvider(selected.accountID)
            let fetched = try await provider.item(id: selected.itemID)
            try Task.checkCancellation()
            guard fetched.id == selected.itemID, fetched.kind == item.kind,
                  fetched.sourceAccountID == nil || fetched.sourceAccountID == selected.accountID,
                  !MediaItemIdentity.externalIdentitiesConflict(
                      MediaItemIdentity.identities(for: item),
                      MediaItemIdentity.identities(for: fetched)
                  ) else {
                throw AppError.invalidResponse
            }
            item = fetched.taggingSource(selected.accountID)
        }
        item.sources = selection.sources
        return DetailOpeningResolution(
            provider: provider, item: item, sources: selection.sources,
            resumeEpisode: DetailPlaybackSelection.resumeItem(for: item, in: continueWatchingSnapshot())
        )
    }

/// Build the detail view model for a series opened via an episode/season
    /// context: the page and its first paint describe the series; the tapped
    /// child identifies the parent, not a stale override of its current resume target.
    public func makeSeriesContextViewModel(
        seriesID: String,
        seed: MediaItem,
        sourceAccountID: String?,
        originAccountID: String?
    ) throws -> ItemDetailViewModel {
        let series = SeriesEpisodeEntry.seriesSeed(
            from: seed, seriesID: seriesID, sourceAccountID: sourceAccountID ?? originAccountID
        )
        return try makeViewModel(for: series, libraryOrigin: originAccountID)
    }
}
