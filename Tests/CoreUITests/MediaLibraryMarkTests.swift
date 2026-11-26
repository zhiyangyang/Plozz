import CoreModels
import XCTest
@testable import CoreUI

#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Covers which mark a card wears. A title the viewer does not own is flagged
/// without depending on any external request service.
final class MediaLibraryMarkTests: XCTestCase {
    private func item(owned: Bool) -> MediaItem {
        MediaItem(
            id: "1", title: "A Title", kind: .movie,
            locallyValidatedPlayableSource: owned
        )
    }

    func testOrdinaryLibraryItemIsNeverMarked() {
        XCTAssertNil(MediaLibraryMark.mark(for: item(owned: true)))
    }

    func testUnownedTitlesAreMarked() {
        XCTAssertEqual(MediaLibraryMark.mark(for: item(owned: false)), .notInLibrary)
    }

    func testNotInLibraryAccessibilityDescribesTheMissingTitle() {
        var label = MediaLibraryMark.notInLibrary.accessibilityLabel
        label.locale = Locale(identifier: "en")
        XCTAssertEqual(String(localized: label), "Not in your library")
    }

    #if canImport(UIKit)
    @MainActor
    func testDiscoverySymbolFitsItsBadgeSlot() throws {
        for size in [CGFloat(20), 21, 25, 36, 42, 50] {
            let renderer = ImageRenderer(content: MediaLibraryMarkView(mark: .notInLibrary, size: size))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, Int(size * 2), "The mark must not exceed its badge width")
            XCTAssertEqual(image.height, Int(size * 2), "The mark must share the same badge height")
        }
    }
    #endif

    func testMarkAgreesWithTheItemPredicateItIsDerivedFrom() {
        for owned in [true, false] {
            let subject = item(owned: owned)
            XCTAssertEqual(
                MediaLibraryMark.mark(for: subject) != nil,
                !subject.hasPlayableLibraryTarget()
            )
        }
    }

    func testIndicatorStateCarriesTheSameDecisionAsTheItem() {
        for owned in [true, false] {
            let subject = item(owned: owned)
            let state = MediaPlaybackIndicatorState(subject)
            XCTAssertEqual(
                state.libraryMark(),
                MediaLibraryMark.mark(for: subject)
            )
        }
    }

    func testMarkSizeScalesWithTheCardRatherThanBeingFixed() {
        let personPage = MediaLibraryMarkView.size(forCardWidth: 280)
        let playerCast = MediaLibraryMarkView.size(forCardWidth: 167)
        XCTAssertEqual(personPage, 42, "a standard poster keeps the watched badge's 42pt")
        XCTAssertLessThan(playerCast, personPage)
        XCTAssertEqual(playerCast / 167, personPage / 280, accuracy: 0.01)
    }
}
#endif
