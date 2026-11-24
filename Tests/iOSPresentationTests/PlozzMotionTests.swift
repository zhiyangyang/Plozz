#if canImport(SwiftUI)
import SwiftUI
import XCTest
@testable import CoreUI

final class PlozzMotionTests: XCTestCase {
    func testReduceMotionDisablesOwnedStateAnimations() {
        for level in [PlozzMotion.Level.micro, .content, .loading, .emphasis] {
            XCTAssertNil(PlozzMotion.animation(level, reduceMotion: true))
        }
    }

    func testEachMotionLevelHasAnAnimationWhenMotionIsAllowed() {
        for level in [PlozzMotion.Level.micro, .content, .loading, .emphasis] {
            XCTAssertNotNil(PlozzMotion.animation(level, reduceMotion: false))
        }
    }

    func testContentLevelSharesThePageRevealRhythm() {
        XCTAssertEqual(PlozzMotion.content, PageMotion.contentReveal)
    }
}
#endif
