import Foundation

/// Content facts, not visibility preferences. An unresolved server says
/// nothing about whether its catalogue contains movies or shows.
public struct NavigationContentAvailability: Equatable, Sendable {
    public let hasHomeContent: Bool
    public let hasSearchContent: Bool
    public let hasWatchlistItems: Bool

    public init(
        accounts: [Account],
        libraries: [AggregatedLibrary],
        discoveredAccountIDs: Set<String>,
        disabledLibraryKeys: Set<String>,
        hasDiscoverySearch: Bool,
        hasWatchlistItems: Bool
    ) {
        let accountIDs = Set(accounts.map(\.id))
        let hasLibraries = libraries.contains {
            accountIDs.contains($0.accountID)
                && !disabledLibraryKeys.contains($0.key)
                && !$0.library.isMusic
        }
        // Keep established media navigation while an uncached server is loading
        // or unreachable.
        let hasUnresolvedMediaServer = accounts.contains {
            !discoveredAccountIDs.contains($0.id)
        }
        hasSearchContent = hasLibraries || hasUnresolvedMediaServer || hasDiscoverySearch
        hasHomeContent = hasSearchContent || accounts.contains { $0.server.provider == .plex }
        self.hasWatchlistItems = hasWatchlistItems
    }

    public var automaticallyHiddenKeys: Set<String> {
        var hidden: Set<String> = []
        if !hasHomeContent { hidden.insert(NavigationLibraryLayout.homeKey) }
        if !hasSearchContent { hidden.insert(NavigationLibraryLayout.searchKey) }
        if !hasWatchlistItems { hidden.insert(NavigationLibraryLayout.watchlistKey) }
        return hidden
    }


    /// Only a successful answer can remove an account's remembered libraries.
    public static func reconcileLibraries(
        discovered: [AggregatedLibrary],
        unreachableAccountIDs: Set<String>,
        remembered: [AggregatedLibrary]
    ) -> [AggregatedLibrary] {
        let carriedOver = remembered.filter { unreachableAccountIDs.contains($0.accountID) }
        var seen: Set<String> = []
        return (discovered + carriedOver).filter { seen.insert($0.key).inserted }
    }
}
