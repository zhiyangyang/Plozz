import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlaybackDiagnosticsHostedTests: XCTestCase {
    func testAvailableSpaceClearsCardsTabsAndMenusInTheSameCoordinateSpace() {
        let bounds = CGRect(x: 40, y: 30, width: 1920, height: 1080)
        for top: CGFloat in [650, 420, 60] {
            let controls = CGRect(x: 80, y: top, width: 1800, height: 400)
            let space = TelevisionDiagnosticsPlacement<EmptyView>.availableRect(in: bounds, avoiding: [controls])
            XCTAssertEqual(space.minX, 88)
            XCTAssertEqual(space.minY, 62)
            XCTAssertTrue(space.isEmpty || !space.intersects(controls))
            if space.height > 0 { XCTAssertLessThanOrEqual(space.maxY, top - 24) }
        }
        let unobstructed = TelevisionDiagnosticsPlacement<EmptyView>.availableRect(
            in: bounds, avoiding: [.null, CGRect(x: 3000, y: 0, width: 100, height: 100)]
        )
        XCTAssertEqual(unobstructed, CGRect(x: 88, y: 62, width: 1280, height: 1016))
        let rightMenu = CGRect(x: 1450, y: 100, width: 450, height: 800)
        XCTAssertEqual(
            TelevisionDiagnosticsPlacement<EmptyView>.availableRect(in: bounds, avoiding: [rightMenu]),
            unobstructed, "A menu outside the narrower panel must not hide diagnostics"
        )
        let smallBounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        XCTAssertEqual(
            TelevisionDiagnosticsPlacement<EmptyView>.availableRect(in: smallBounds, avoiding: []).width,
            1184
        )
    }

}

@MainActor
@Observable
private final class PanelMeasurement {
    var frame: CGRect?
}
