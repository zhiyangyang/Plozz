import XCTest
@testable import FeatureHomeCore

/// The gauge follows the slide's dwell timer.
final class HeroGaugeStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func resolve(
        autoAdvance: Bool = true,
        at offset: TimeInterval,
        dwell: TimeInterval = 10,
        isTransitioning: Bool = false
    ) -> HeroGaugeState {
        HeroGaugeState.resolve(
            autoAdvance: autoAdvance,
            dwellStart: start,
            dwellDuration: dwell,
            now: start.addingTimeInterval(offset),
            isTransitioning: isTransitioning
        )
    }

    func testDwellRampsFromEmptyToFull() {
        XCTAssertEqual(resolve(at: 0).fraction, 0, accuracy: 0.001)
        XCTAssertEqual(resolve(at: 5).fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(resolve(at: 5).remaining ?? 0, 5, accuracy: 0.001)
    }

    func testAnIncomingSlideStartsEmptyRatherThanFull() {
        let state = resolve(at: 30)
        XCTAssertEqual(state.fraction, 0)
        XCTAssertEqual(state.remaining ?? 0, 10, accuracy: 0.001)

        let transitioning = resolve(at: 4, isTransitioning: true)
        XCTAssertEqual(transitioning.fraction, 0)
    }

    func testAutoAdvanceOffHoldsAFullPillWithNoRamp() {
        let state = resolve(autoAdvance: false, at: 3)
        XCTAssertEqual(state.fraction, 1)
        XCTAssertNil(state.remaining)
    }

    func testFractionNeverLeavesItsRange() {
        XCTAssertEqual(resolve(at: -5).fraction, 0)
        XCTAssertEqual(resolve(at: 9).fraction, 0.9, accuracy: 0.001)
    }
}
