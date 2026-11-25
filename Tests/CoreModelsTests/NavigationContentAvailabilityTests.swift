import Foundation
import XCTest
@testable import CoreModels

final class NavigationContentAvailabilityTests: XCTestCase {
    private let automaticKeys: Set<String> = [
        NavigationLibraryLayout.homeKey,
        NavigationLibraryLayout.searchKey,
        NavigationLibraryLayout.watchlistKey,
    ]

    func testUnresolvedMediaServerKeepsNavigationDuringLoadingAndOfflineStartup() {
        for provider in [ProviderKind.jellyfin, .plex, .emby] {
            let facts = availability(accounts: [account("server", provider: provider)])
            XCTAssertTrue(facts.hasHomeContent)
            XCTAssertTrue(facts.hasSearchContent)
        }
    }

    func testResolvedLibraryEnablesHomeAndSearch() {
        for kind in [MediaItemKind.movie, .series] {
            let facts = availability(
                accounts: [account("server", provider: .jellyfin)],
                libraries: [library("server", kind: kind)]
            )
            XCTAssertEqual(facts.automaticallyHiddenKeys, [NavigationLibraryLayout.watchlistKey])
            XCTAssertTrue(facts.hasHomeContent)
            XCTAssertTrue(facts.hasSearchContent)
        }
    }

    func testKnownEmptyDisabledAndOtherProfileLibrariesDoNotEnableSearch() {
        let server = account("server", provider: .jellyfin)
        for (libraries, disabled) in [
            ([], Set<String>()),
            ([library("other-profile")], Set<String>()),
            ([library("server")], ["server:movies"]),
            ([library("server", isMusic: true)], Set<String>()),
        ] {
            let facts = availability(
                accounts: [server], libraries: libraries, known: ["server"], disabled: disabled
            )
            XCTAssertFalse(facts.hasHomeContent)
            XCTAssertFalse(facts.hasSearchContent)
        }
    }

    func testDiscoveryAndWatchlistAreIndependentOfMediaLibraries() {
        let discovery = availability(discovery: true)
        XCTAssertTrue(discovery.hasHomeContent)
        XCTAssertTrue(discovery.hasSearchContent)
        XCTAssertFalse(discovery.hasWatchlistItems)
        let watchlist = availability(watchlist: true)
        XCTAssertFalse(watchlist.hasHomeContent)
        XCTAssertFalse(watchlist.hasSearchContent)
        XCTAssertTrue(watchlist.hasWatchlistItems)
        let plex = availability(accounts: [account("plex", provider: .plex)], known: ["plex"])
        XCTAssertTrue(plex.hasHomeContent)
        XCTAssertFalse(plex.hasSearchContent)
    }

    func testAnEmptyOpenWatchlistStaysUntilLeavingButManualHideWins() {
        var layout = NavigationLibraryLayout.default
        let open = layout.resolvingAutomaticVisibility(hidden: automaticKeys, retainingWatchlist: true)
        XCTAssertTrue(open.isVisible(NavigationLibraryLayout.watchlistKey))
        XCTAssertFalse(layout.resolvingAutomaticVisibility(hidden: automaticKeys)
            .isVisible(NavigationLibraryLayout.watchlistKey))
        XCTAssertEqual(layout, .default)
        layout.setVisible(false, for: NavigationLibraryLayout.watchlistKey)
        XCTAssertFalse(layout.resolvingAutomaticVisibility(hidden: automaticKeys, retainingWatchlist: true)
            .isVisible(NavigationLibraryLayout.watchlistKey))
    }

    func testManualShowSurvivesEmptyContentAndRelaunch() throws {
        var layout = NavigationLibraryLayout.default
        for key in automaticKeys { layout.setVisible(true, for: key) }
        let restored = try JSONDecoder().decode(
            NavigationLibraryLayout.self, from: JSONEncoder().encode(layout)
        )
        XCTAssertEqual(restored.shownKeys, automaticKeys)
        for key in automaticKeys {
            XCTAssertTrue(restored.resolvingAutomaticVisibility(hidden: automaticKeys).isVisible(key))
        }
    }

    func testReorderingDoesNotPersistAutomaticHidingOrShowing() throws {
        let available = NavigationDestinationDefaults.compact()
        let automaticKeys = self.automaticKeys
        var layout = NavigationLibraryLayout.default
        layout.apply(
            .init(
                enabled: [NavigationLibraryLayout.settingsKey],
                disabled: available.filter { automaticKeys.contains($0) }
            ),
            available: available,
            automaticallyHiddenKeys: automaticKeys
        )
        XCTAssertTrue(layout.hiddenKeys.isEmpty)
        XCTAssertTrue(layout.shownKeys.isEmpty)
        let restored = try JSONDecoder().decode(
            NavigationLibraryLayout.self, from: JSONEncoder().encode(layout)
        )
        XCTAssertEqual(restored, layout)
        XCTAssertEqual(Set(restored.visibleKeys(available: available)), Set(available))
        XCTAssertFalse(restored.resolvingAutomaticVisibility(hidden: automaticKeys)
            .isVisible(NavigationLibraryLayout.watchlistKey))
    }

    func testShowingAutomaticallyHiddenWatchlistCreatesOnlyThatOverride() {
        let available = NavigationDestinationDefaults.compact()
        let automaticKeys = self.automaticKeys
        var layout = NavigationLibraryLayout.default
        layout.apply(
            .init(
                enabled: [
                    NavigationLibraryLayout.watchlistKey, NavigationLibraryLayout.settingsKey,
                ],
                disabled: [
                    NavigationLibraryLayout.homeKey, NavigationLibraryLayout.searchKey
                ]
            ),
            available: available,
            automaticallyHiddenKeys: automaticKeys
        )
        XCTAssertEqual(layout.shownKeys, [NavigationLibraryLayout.watchlistKey])
        XCTAssertTrue(layout.hiddenKeys.isEmpty)
        XCTAssertTrue(layout.resolvingAutomaticVisibility(hidden: automaticKeys)
            .isVisible(NavigationLibraryLayout.watchlistKey))
    }

    func testLegacyDefaultsAreAutomaticButExplicitArrangementsArePreserved() throws {
        func decode(order: [String], hidden: [String] = []) throws -> NavigationLibraryLayout {
            try JSONDecoder().decode(
                NavigationLibraryLayout.self,
                from: JSONSerialization.data(withJSONObject: ["order": order, "hiddenKeys": hidden])
            )
        }
        for order in [[], ["server:movies", NavigationLibraryLayout.allLibrariesKey]] {
            let untouched = try decode(order: order)
            XCTAssertTrue(untouched.shownKeys.isEmpty)
            XCTAssertFalse(untouched.resolvingAutomaticVisibility(hidden: automaticKeys)
                .isVisible(NavigationLibraryLayout.watchlistKey))
        }
        let arranged = try decode(
            order: [NavigationLibraryLayout.watchlistKey, NavigationLibraryLayout.searchKey],
            hidden: [NavigationLibraryLayout.searchKey]
        )
        XCTAssertEqual(arranged.shownKeys, [NavigationLibraryLayout.watchlistKey])
        XCTAssertEqual(arranged.hiddenKeys, [NavigationLibraryLayout.searchKey])
    }

    @MainActor
    func testLibrarySnapshotsSurviveFailureButNotSuccessfulRemovalOrAccountRemoval() {
        let suite = "NavigationContentAvailabilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = NavigationLibrariesSnapshotStore(defaults: defaults, namespace: "viewer")
        snapshot.save([library("server")])
        let model = NavigationStyleSettingsModel(
            store: NavigationStyleSettingsStore(defaults: defaults, namespace: "viewer"),
            layoutStore: NavigationLibraryLayoutStore(defaults: defaults, namespace: "viewer"),
            librariesSnapshotStore: snapshot
        )
        XCTAssertEqual(model.contentLibraries, [library("server")])
        model.updateContentLibraries([], accountIDs: ["server"], unreachableAccountIDs: ["server"])
        XCTAssertEqual(model.contentLibraries, [library("server")])
        XCTAssertEqual(snapshot.load(), model.contentLibraries)
        model.updateContentLibraries([], accountIDs: ["server"], unreachableAccountIDs: [])
        XCTAssertTrue(model.contentLibraries.isEmpty)
        XCTAssertEqual(model.discoveredAccountIDs, ["server"])
        model.updateContentLibraries([library("server")], accountIDs: ["server"], unreachableAccountIDs: [])
        model.updateContentLibraries([], accountIDs: [], unreachableAccountIDs: [])
        XCTAssertTrue(model.contentLibraries.isEmpty)
        XCTAssertTrue(model.discoveredAccountIDs.isEmpty)
    }

    @MainActor
    func testManualWatchlistShowIsProfileScopedAndResetRestoresAutomaticDefault() {
        let suite = "NavigationContentAvailabilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func model(_ namespace: String?) -> NavigationStyleSettingsModel {
            let result = NavigationStyleSettingsModel(
                store: NavigationStyleSettingsStore(defaults: defaults, namespace: namespace),
                layoutStore: NavigationLibraryLayoutStore(defaults: defaults, namespace: namespace)
            )
            result.automaticallyHiddenKeys = automaticKeys
            return result
        }
        let primary = model(nil)
        XCTAssertFalse(primary.showsWatchlist)
        primary.showsWatchlist = true
        XCTAssertTrue(model(nil).showsWatchlist)
        XCTAssertFalse(model("child").showsWatchlist)
        primary.resetLibraryLayout()
        XCTAssertFalse(primary.showsWatchlist)
        XCTAssertFalse(model(nil).showsWatchlist)
    }

    private func availability(
        accounts: [Account] = [], libraries: [AggregatedLibrary] = [],
        known: Set<String> = [], disabled: Set<String> = [],
        discovery: Bool = false, watchlist: Bool = false
    ) -> NavigationContentAvailability {
        NavigationContentAvailability(
            accounts: accounts, libraries: libraries, discoveredAccountIDs: known,
            disabledLibraryKeys: disabled, hasDiscoverySearch: discovery, hasWatchlistItems: watchlist
        )
    }

    private func account(_ id: String, provider: ProviderKind) -> Account {
        Account(
            id: id,
            server: MediaServer(id: id, name: id, baseURL: URL(string: "https://example.invalid")!, provider: provider),
            userID: "user", userName: "User", deviceID: "device"
        )
    }

    private func library(
        _ accountID: String, kind: MediaItemKind = .movie, isMusic: Bool = false
    ) -> AggregatedLibrary {
        AggregatedLibrary(
            accountID: accountID, accountName: accountID, serverName: "Server", providerKind: .jellyfin,
            library: MediaLibrary(id: "movies", title: "Movies", kind: kind, isMusic: isMusic)
        )
    }
}
