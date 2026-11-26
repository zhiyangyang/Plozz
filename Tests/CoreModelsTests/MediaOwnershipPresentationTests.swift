import XCTest
import CoreModels

/// Hero CTA and play-action behaviour for library titles.
final class MediaOwnershipPresentationTests: XCTestCase {
    func testFreshFirstEpisodesUseStartWatching() {
        for season in [1, 4] {
            let episode = MediaItem(
                id: "episode", title: "Episode", kind: .episode,
                seasonNumber: season, episodeNumber: 1
            )
            XCTAssertTrue(episode.startsWatching)
            var title = episode.playActionTitle
            title.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: title), "Start watching")
        }
    }

    func testResumeRewatchSpecialsAndUnknownEpisodesDoNotClaimAFreshStart() {
        let first = MediaItem(
            id: "episode", title: "Episode", kind: .episode,
            seasonNumber: 1, episodeNumber: 1
        )
        var variants: [MediaItem] = []
        var item = first
        item.resumePosition = 867
        variants.append(item)
        item = first
        item.playedPercentage = 0.2
        variants.append(item)
        item = first
        item.isPlayed = true
        variants.append(item)
        item = first
        item.hasBeenPlayed = true
        variants.append(item)
        item = first
        item.seasonNumber = 0
        variants.append(item)
        item = first
        item.seasonNumber = nil
        variants.append(item)
        item = first
        item.episodeNumber = 2
        variants.append(item)
        item = first
        item.locallyValidatedPlayableSource = false
        variants.append(item)
        item = first
        item.kind = .movie
        variants.append(item)
        for variant in variants {
            XCTAssertFalse(variant.startsWatching)
            var title = variant.playActionTitle
            title.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: title), "Play")
        }
    }

    func testPlexDiscoverWatchlistStubHasNoPlayableLibraryTarget() {
        let discover = MediaItem(
            id: "5d7768342ec6b5001f6bbacd",
            title: "13 Going on 30",
            kind: .movie,
            providerIDs: ["PlexGuid": "plex://movie/5d7768342ec6b5001f6bbacd"],
            locallyValidatedPlayableSource: false
        )

        XCTAssertFalse(discover.hasPlayableLibraryTarget())
    }

    func testPlexDiscoverWatchlistStubBecomesPlayableWithLibrarySource() {
        let discover = MediaItem(
            id: "5d7768342ec6b5001f6bbacd",
            title: "13 Going on 30",
            kind: .movie,
            providerIDs: ["PlexGuid": "plex://movie/5d7768342ec6b5001f6bbacd"],
            locallyValidatedPlayableSource: false
        )
        let librarySource = MediaSourceRef(
            accountID: "plex-account",
            itemID: "48291",
            providerKind: .plex
        )

        XCTAssertTrue(discover.hasPlayableLibraryTarget(additionalSources: [librarySource]))
    }

    func testOrdinaryAndOwnedPlexItemsHavePlayableLibraryTargets() {
        XCTAssertTrue(MediaItem(id: "x", title: "T", kind: .movie).hasPlayableLibraryTarget())

        let owned = MediaItem(
            id: "48291",
            title: "13 Going on 30",
            kind: .movie,
            providerIDs: ["PlexGuid": "plex://movie/5d7768342ec6b5001f6bbacd"]
        )
        XCTAssertTrue(owned.hasPlayableLibraryTarget())
    }

    func testAccountMetadataAndGlobalGuidDoNotProveOwnership() {
        let external = MediaItem(
            id: "global",
            title: "The Legend of Hei",
            kind: .movie,
            providerIDs: ["PlexGuid": "plex://movie/global"],
            locallyValidatedPlayableSource: false,
            sourceAccountID: "plex-account"
        )

        XCTAssertFalse(external.hasPlayableLibraryTarget())
        XCTAssertEqual(
            external.ownershipPresentation(),
            MediaOwnershipPresentation(hasValidatedPlayableSource: false)
        )
    }

    func testLegacyCachedDiscoverRecordMigratesToUnowned() throws {
        let legacyJSON = """
        {
          "id":"abc123",
          "title":"The Legend of Hei",
          "kind":"movie",
          "providerIDs":{"PlexGuid":"plex://movie/abc123"},
          "sourceAccountID":"plex-account"
        }
        """

        let decoded = try JSONDecoder().decode(
            MediaItem.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertFalse(decoded.locallyValidatedPlayableSource)
        XCTAssertFalse(decoded.hasPlayableLibraryTarget())
    }
}
