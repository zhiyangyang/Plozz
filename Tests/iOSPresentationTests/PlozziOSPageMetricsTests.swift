#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import XCTest
@testable import CoreUI

final class PlozziOSPageMetricsTests: XCTestCase {
    func testPageInsetResolvesByWidthClass() {
        XCTAssertEqual(
            PlozziOSPageMetrics.pageInset(for: .compact),
            PlozziOSPageMetrics.compactPageInset
        )
        XCTAssertEqual(
            PlozziOSPageMetrics.pageInset(for: .regular),
            PlozziOSPageMetrics.regularPageInset
        )
        XCTAssertEqual(
            PlozziOSPageMetrics.pageInset(for: .regular, usesDesktopSizing: true),
            PlozziOSPageMetrics.desktopPageInset
        )
    }

    func testPageInsetUsesTheSameEdgeForiPadMultitaskingWidths() {
        XCTAssertLessThan(
            PlozziOSPageMetrics.pageInset(for: .compact),
            PlozziOSPageMetrics.pageInset(for: .regular)
        )
        XCTAssertGreaterThan(PlozziOSPageMetrics.rowMinHeight, 44)
        XCTAssertGreaterThan(PlozziOSPageMetrics.formMaxWidth, PlozziOSPageMetrics.readingMaxWidth)
        XCTAssertGreaterThan(PlozziOSPageMetrics.readingMaxWidth, 0)
    }
}
#endif
