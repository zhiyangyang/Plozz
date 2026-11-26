import CoreModels
import Foundation
import XCTest
@testable import FeatureHomeCore

final class HeroLoadKeyTests: XCTestCase {
    private let scope = NSObject()
    private let connection = UUID()

    private var baseSettings: HeroSettings {
        HeroSettings.default
    }

    private func curation(
        _ settings: HeroSettings, revision: Int,
        content: HomeViewModel.Content = .init(),
        membershipRevision: Int = 0,
        scopeID: ObjectIdentifier? = nil,
        isPreparingHome: Bool = false,
        loadingRows: Set<HomeRowKind> = []
    ) -> HeroCurationLoadKey {
        HeroCurationLoadKey(
            content: content, settings: settings, visibility: .default,
            freshnessRevision: 0, identityIndexRevision: revision,
            watchlistMembershipRevision: membershipRevision,
            scopeID: scopeID ?? ObjectIdentifier(scope),
            isPreparingHome: isPreparingHome, loadingRows: loadingRows
        )
    }

    func testPendingEmptySourcesCannotCompleteHeroAndReadyEmptySourcesRestartCuration() {
        let dependencies: [(HeroSourceKind, HomeRowKind)] = [
            (.continueWatching, .continueWatching), (.recentlyAdded, .recentlyAdded),
            (.watchlist, .watchlist), (.randomFromLibrary, .libraries)
        ]
        for (source, row) in dependencies {
            var settings = HeroSettings.default
            settings.sources = [source]
            let preparing = curation(settings, revision: 0, isPreparingHome: true)
            let pending = curation(settings, revision: 0, loadingRows: [row])
            let ready = curation(settings, revision: 0)
            XCTAssertTrue(preparing.isAwaitingSources)
            XCTAssertTrue(pending.isAwaitingSources)
            XCTAssertFalse(ready.isAwaitingSources)
            XCTAssertNotEqual(pending, ready, "Even a successful empty source must restart the task.")
            XCTAssertEqual(
                ready,
                curation(settings, revision: 0, loadingRows: Set(HomeRowKind.allCases).subtracting([row])),
                "Unrelated Home rows must not delay or restart this hero."
            )
        }

    }

func testAsyncHeroSourcesWaitForPreparationButNotUnrelatedRows() {
        for source: HeroSourceKind in [.collection] {
            var settings = HeroSettings.default
            settings.sources = [source]
            let preparing = curation(settings, revision: 0, isPreparingHome: true)
            let pendingRows = curation(settings, revision: 0, loadingRows: Set(HomeRowKind.allCases))
            XCTAssertTrue(preparing.isAwaitingSources)
            XCTAssertFalse(pendingRows.isAwaitingSources)
            XCTAssertFalse(curation(settings, revision: 0).isAwaitingSources)
        }
        var settings = baseSettings
        settings.isEnabled = false
        XCTAssertFalse(curation(settings, revision: 0, loadingRows: Set(HomeRowKind.allCases)).isAwaitingSources)
    }

func testNewProfileScopeReloadsEvenWhenIndexRevisionAndSettingsMatch() {
        let otherScope = NSObject()
        XCTAssertNotEqual(
            curation(baseSettings, revision: 1),
            curation(baseSettings, revision: 1, scopeID: ObjectIdentifier(otherScope))
        )
    }

    func testWatchlistIntentRollbackReloadsWithoutRowIDChanges() {
        var settings = baseSettings
        settings.sources = [.watchlist]
        XCTAssertNotEqual(
            curation(settings, revision: 0, membershipRevision: 1),
            curation(settings, revision: 0, membershipRevision: 2)
        )
        var withoutWatchlist = baseSettings
        withoutWatchlist.sources = [.randomFromLibrary]
        XCTAssertEqual(
            curation(withoutWatchlist, revision: 0, membershipRevision: 1),
            curation(withoutWatchlist, revision: 0, membershipRevision: 2)
        )
    }

    func testCollectionSelectionAndHistoryRevisionRestartCuration() {
        var settings = baseSettings
        settings.sources = [.collection]
        settings.collections = [.init(accountID: "a", libraryID: "l", collectionID: "c", title: "Collection")]
        let initial = curation(settings, revision: 0)
        XCTAssertNotEqual(initial, curation(settings, revision: 1))
        settings.collections.append(.init(accountID: "a", libraryID: "l", collectionID: "other", title: "Collection"))
        XCTAssertNotEqual(initial, curation(settings, revision: 0))
        settings.hideWatched = false
        XCTAssertEqual(curation(settings, revision: 0), curation(settings, revision: 1))
    }

    private func item(_ id: String = "42") -> MediaItem {
        MediaItem(
            id: id, title: "Movie", kind: .movie, providerIDs: ["Tmdb": id],
            locallyValidatedPlayableSource: false
        )
    }

func testPinnedPlaybackResolutionRestartsWhenOwnershipChangesWithoutChangingDisplayID() {
        var external = item()
        external.kind = .series
        let cold = resolution(external)
        var owned = external
        owned.locallyValidatedPlayableSource = true
        owned.sources = [.init(accountID: "a", itemID: "physical-series", kind: .series)]
        let verified = resolution(owned)
        XCTAssertEqual(owned.id, external.id)
        XCTAssertNotEqual(cold, verified)

        let episode = MediaItem(id: "physical-episode", title: "Episode", kind: .episode)
        let cached = HeroResolutionCacheEntry(key: verified, item: episode)
        XCTAssertEqual(cached.value(for: verified)?.id, episode.id)
        XCTAssertNil(cached.value(for: cold), "Revoked ownership must not expose a cached playable episode.")
        owned.sources = [.init(accountID: "b", itemID: "different-series", kind: .series)]
        XCTAssertNil(cached.value(for: resolution(owned)), "Replacing routing must resolve a new episode.")
    }

    func testPlaybackResolutionKeyTracksVersionsIndexAndProfileNotStatusOrArtwork() {
        let original = item()
        let key = resolution(original)
        var presentation = original
        presentation.title = "Updated title"
        presentation.posterURL = URL(string: "https://images.example.test/new.jpg")
        XCTAssertEqual(key, resolution(presentation))
        presentation.selectedVersionID = "version-b"
        XCTAssertNotEqual(key, resolution(presentation))
        XCTAssertNotEqual(key, resolution(original, revision: 1))
        let otherScope = NSObject()
        XCTAssertNotEqual(key, HeroPlaybackResolutionKey(
            item: original, scopeID: ObjectIdentifier(otherScope), identityIndexRevision: 0
        ))
    }

    private func resolution(_ item: MediaItem, revision: Int = 0) -> HeroPlaybackResolutionKey {
        HeroPlaybackResolutionKey(
            item: item, scopeID: ObjectIdentifier(scope), identityIndexRevision: revision
        )
    }
}
