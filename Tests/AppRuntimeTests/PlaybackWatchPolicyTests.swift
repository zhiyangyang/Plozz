import XCTest
import CoreModels
@testable import AppRuntime

final class PlaybackWatchPolicyTests: XCTestCase {
    private func movie(resume: TimeInterval? = nil) -> MediaItem {
        MediaItem(
            id: "movie", title: "Movie", kind: .movie, runtime: 7_200,
            resumePosition: resume, providerIDs: ["Tmdb": "123"], sourceAccountID: "origin"
        )
    }

    func testShortProgressIsDurableEvenBeforeContinueWatchingAdmission() {
        let item = movie()
        for position in [0.0, 1] {
            XCTAssertNil(WatchMutationFactory.playbackStop(
                item: item, position: position, watchedPercent: position / 72,
                primaryAccountID: "origin"
            ))
        }
        for position in [2.0, 10, 30, 59.999, 60, 120] {
            let mutation = WatchMutationFactory.playbackStop(
                item: item, position: position, watchedPercent: position / 72,
                primaryAccountID: "origin"
            )
            XCTAssertEqual(mutation?.resumePosition, position)
        }
    }

    func testExistingResumeAndCompletedShortContentAreNotDiscarded() {
        XCTAssertEqual(WatchMutationFactory.playbackStop(
            item: movie(resume: 15), position: 20, watchedPercent: 1,
            primaryAccountID: "origin"
        )?.resumePosition, 20)
        XCTAssertEqual(WatchMutationFactory.playbackStop(
            item: movie(), position: 45, watchedPercent: 100,
            primaryAccountID: "origin"
        )?.played, true)
    }

func testSpecialFeatureNeverPropagatesParentIdentity() throws {
        var item = movie()
        item.id = "featurette"
        let feature = MediaExtra(item: item, kind: .featurette).playbackItem
        for percent in [10.0, 100] {
            let mutation = try XCTUnwrap(WatchMutationFactory.playbackStop(
                item: feature, position: 15, watchedPercent: percent, primaryAccountID: "origin",
                additionalSources: [.init(accountID: "other", itemID: "movie-copy", providerKind: .plex)]
            ))
            XCTAssertEqual(mutation.targets.map(\.id), ["origin:featurette"])
            XCTAssertFalse(mutation.expansionPending)
            XCTAssertTrue(mutation.identities.isEmpty)
        }
    }

}
