import CoreModels
import Foundation

/// Playback/root hydration follows routing changes even when a pinned catalog
/// presentation keeps its display id. Status, artwork and copy are not inputs.
public struct HeroPlaybackResolutionKey: Equatable, Sendable {
    private let id: String
    private let kind: MediaItemKind
    private let providerIDs: [String: String]
    private let sourceAccountID: String?
    private let selectedSourceAccountID: String?
    private let explicitSourceSelection: Bool
    private let selectedVersionID: String?
    private let versions: [MediaVersion]
    private let sources: [MediaSourceRef]
    private let seriesID: String?
    private let resumePosition: TimeInterval?
    private let isPlayed: Bool
    private let hasBeenPlayed: Bool
    private let lastPlayedAt: Date?
    private let hasValidatedSource: Bool
    private let scopeID: ObjectIdentifier?
    private let identityIndexRevision: Int

    public init(item: MediaItem, scopeID: ObjectIdentifier?, identityIndexRevision: Int) {
        id = item.id
        kind = item.kind
        providerIDs = item.providerIDs
        sourceAccountID = item.sourceAccountID
        selectedSourceAccountID = item.selectedSourceAccountID
        explicitSourceSelection = item.explicitSourceSelection
        selectedVersionID = item.selectedVersionID
        versions = item.versions
        sources = item.sources
        seriesID = item.seriesID
        resumePosition = item.resumePosition
        isPlayed = item.isPlayed
        hasBeenPlayed = item.hasBeenPlayed
        lastPlayedAt = item.lastPlayedAt
        hasValidatedSource = item.locallyValidatedPlayableSource
        self.scopeID = scopeID
        self.identityIndexRevision = identityIndexRevision
    }
}

public struct HeroResolutionCacheEntry: Sendable {
    private let key: HeroPlaybackResolutionKey
    private let item: MediaItem

    public init(key: HeroPlaybackResolutionKey, item: MediaItem) {
        self.key = key
        self.item = item
    }

    public func value(for key: HeroPlaybackResolutionKey) -> MediaItem? {
        self.key == key ? item : nil
    }
}

/// Content-loading identity, independent of carousel presentation preferences.
/// Keyed on title MEMBERSHIP, not full item values: re-aggregation folds
/// (`ContentRefresh` reloads Home ~every 15 s while foreground) re-fetch the
/// same titles with volatile status fields (resume position, availability,
/// artwork/copy). Those must NOT restart hero curation — otherwise the
/// `.task(id: heroLoadKey)` chain tears the settled hero, re-resolves it over
/// the network, and re-warms artwork on every fold (the visible "hero leaves,
/// art re-renders" flicker and the slow hero paint). Status-only changes have
/// their own lane, like `HeroStatusRefreshKey` documents below.
public struct HeroCurationLoadKey: Equatable, Sendable {
    public let isAwaitingSources: Bool
    private let continueWatchingIDs: [String]
    private let watchlistIDs: [String]
    private let recentlyAddedIDs: [String]
    private let libraries: [AggregatedLibrary]
    private let configuration: HeroConfigurationKey
    private let visibility: HomeLibraryVisibility
    private let freshnessRevision: Int
    private let identityIndexRevision: Int
    private let watchlistMembershipRevision: Int
    private let scopeID: ObjectIdentifier

    public init(
        content: HomeViewModel.Content,
        settings: HeroSettings,
        visibility: HomeLibraryVisibility,
        freshnessRevision: Int,
        identityIndexRevision: Int,
        watchlistMembershipRevision: Int = 0,
        scopeID: ObjectIdentifier,
        isPreparingHome: Bool = false,
        loadingRows: Set<HomeRowKind> = []
    ) {
        continueWatchingIDs = settings.isEnabled(.continueWatching) ? content.continueWatching.map(\.id) : []
        watchlistIDs = settings.isEnabled(.watchlist) ? content.watchlist.map(\.id) : []
        recentlyAddedIDs = settings.isEnabled(.recentlyAdded) ? content.latest.map(\.id) : []
        libraries = settings.isEnabled(.randomFromLibrary) || settings.isEnabled(.collection)
            ? content.libraries : []
        configuration = HeroConfigurationKey(settings: settings)
        self.visibility = visibility
        self.freshnessRevision = freshnessRevision
        isAwaitingSources = isPreparingHome || HomeHeroLaunchPolicy.isAwaitingSources(
            settings: settings, loadingRows: loadingRows
        )
        let enrichesCollectionHistory = settings.isEnabled(.collection) && settings.hideWatched
        self.identityIndexRevision = settings.isActive && enrichesCollectionHistory
            ? identityIndexRevision : 0
        self.watchlistMembershipRevision = settings.isActive && settings.isEnabled(.watchlist)
            ? watchlistMembershipRevision : 0
        self.scopeID = scopeID
    }
}
