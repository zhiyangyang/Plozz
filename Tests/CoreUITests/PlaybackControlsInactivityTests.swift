import XCTest
@testable import CoreUI

final class PlaybackControlsInactivityTests: XCTestCase {
    func testNoInputRetainsTheExistingFourSecondGrace() {
        let inactivity = PlaybackControlsInactivity()
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 10), 4)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 13), 1)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 14), 0)
    }

    func testNativeMovementExtendsAlreadyRunningFullscreenCountdown() {
        var inactivity = PlaybackControlsInactivity()
        inactivity.recordInteraction(at: 5.23)
        inactivity.recordInteraction(at: 5.65)
        XCTAssertEqual(
            inactivity.remainingDelay(startedAt: 1.8, now: 5.89),
            3.76,
            accuracy: 0.001
        )
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 1.8, now: 9.65), 0, accuracy: 0.001)
    }

    func testMovementAtRowBoundaryAlsoRenewsGraceWithoutFocusChanging() {
        var inactivity = PlaybackControlsInactivity()
        inactivity.recordInteraction(at: 13)
        inactivity.recordInteraction(at: 16)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 17), 3)
    }

    func testLateOlderActivityCannotShortenCurrentDeadline() {
        var inactivity = PlaybackControlsInactivity()
        inactivity.recordInteraction(at: 20)
        inactivity.recordInteraction(at: 19)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 21), 3)
    }

    func testCallerCanUseALongerReadingGraceWithoutChangingTheSharedDefault() {
        let inactivity = PlaybackControlsInactivity()
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 14), 0)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 14, grace: 9), 5)
    }
}
