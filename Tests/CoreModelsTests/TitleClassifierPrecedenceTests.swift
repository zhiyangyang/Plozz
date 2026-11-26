import XCTest
@testable import CoreModels

/// The shared ownership decisions, pinned so they cannot quietly regress.
final class TitleClassifierPrecedenceTests: XCTestCase {
    func testValidatedTitleIsOwned() {
        let item = MediaItem(
            id: "lib-1",
            title: "Owned",
            kind: .movie,
            locallyValidatedPlayableSource: true
        )

        XCTAssertFalse(TitleClassifier.isNotOwnedForBadge(item))
    }

    func testUnvalidatedTitleWithAnIndexPeerIsOwned() {
        let item = MediaItem(
            id: "x",
            title: "X",
            kind: .movie,
            locallyValidatedPlayableSource: false
        )
        let peer = MediaSourceRef(accountID: "a", itemID: "1", kind: .movie)

        let classification = TitleClassifier.classify(item, identitySources: [peer])
        XCTAssertTrue(classification.hasPlayableLibraryTarget)
        XCTAssertTrue(classification.ownershipPresentation.canPlay)
        XCTAssertTrue(
            item.hasPlayableLibraryTarget(additionalSources: [peer])
        )
    }

    func testUnvalidatedTitleWithNoIndexPeerIsNotOwned() {
        let item = MediaItem(
            id: "x",
            title: "Missing",
            kind: .movie,
            locallyValidatedPlayableSource: false
        )

        XCTAssertTrue(TitleClassifier.isNotOwnedForBadge(item))
        XCTAssertFalse(item.ownershipPresentation().canPlay)
    }

    func testDownloadedTitleStaysPlayableWithAnEmptyIndex() {
        let item = MediaItem(
            id: "dl-1",
            title: "Downloaded",
            kind: .movie,
            locallyValidatedPlayableSource: true
        )

        XCTAssertFalse(TitleClassifier.isNotOwnedForBadge(item))
        XCTAssertTrue(TitleClassifier.classify(item, identitySources: []).hasPlayableLibraryTarget)
    }

    func testWeakEvidenceRulesetIsConsistentlyConservative() {
        XCTAssertNotNil(MediaAliasWeakEvidence(kind: .series, title: "Foundation", year: 2021))
        XCTAssertNil(MediaAliasWeakEvidence(kind: .series, title: "Foundation", year: nil))
        XCTAssertNil(MediaAliasWeakEvidence(kind: .movie, title: "Dune", year: nil))
        XCTAssertNil(MediaAliasWeakEvidence(kind: .episode, title: "Pilot", year: 2021))

        let seriesTitleIdentities = MediaItemIdentity.identities(
            for: MediaItem(id: "s", title: "Foundation", kind: .series, productionYear: 2021)
        )
        XCTAssertFalse(seriesTitleIdentities.contains { identity in
            if case .title = identity { return true }
            return false
        })
        let movieTitleIdentities = MediaItemIdentity.identities(
            for: MediaItem(id: "m", title: "Dune", kind: .movie, productionYear: 2021)
        )
        XCTAssertTrue(movieTitleIdentities.contains { identity in
            if case .title = identity { return true }
            return false
        })
    }

    func testMergeTreatsAValidatedMemberAsOwned() {
        var discovery = MediaItem(
            id: "seer:1",
            title: "Dune",
            kind: .movie,
            productionYear: 2021,
            providerIDs: ["Tmdb": "438631"],
            locallyValidatedPlayableSource: false
        )
        discovery.sourceAccountID = "seer"
        var owned = MediaItem(
            id: "jf-1",
            title: "Dune",
            kind: .movie,
            productionYear: 2021,
            providerIDs: ["Tmdb": "438631"],
            locallyValidatedPlayableSource: true
        )
        owned.sourceAccountID = "jf"

        let merged = MediaItemMerger.merge([discovery, owned])

        XCTAssertEqual(merged.count, 1)
        guard let item = merged.first else { return XCTFail("merge dropped the title") }
        XCTAssertTrue(item.locallyValidatedPlayableSource)
        XCTAssertFalse(TitleClassifier.isNotOwnedForBadge(item))
    }
}
