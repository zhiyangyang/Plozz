#if os(iOS)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class HeroGlassButtonPresentationTests: XCTestCase {
    func testCircularGlassRetainsItsTouchTargetAtEveryTextSize() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            let button = Button {} label: { Image(systemName: "bookmark") }
                .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .secondary, circular: true))
                .environment(\.dynamicTypeSize, size)
            XCTAssertEqual(measure(button, width: 48), CGSize(width: 48, height: 48))
        }
    }

    func testProminentGlassRetainsMinimumWidthAndAccessibleWrapping() {
        let regular = measure(play(wraps: false, minimumWidth: 180), width: 2_000)
        XCTAssertGreaterThanOrEqual(regular.width, 180)
        XCTAssertGreaterThanOrEqual(regular.height, 48)
        let wrapped = measure(play(wraps: true), width: 145)
        XCTAssertLessThanOrEqual(wrapped.width, 145)
        XCTAssertGreaterThan(wrapped.height, regular.height)
    }

    func testResolvingPlayPlaceholderRetainsItsLayoutAtEveryTextSize() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            for width in [CGFloat(145), 276, 720] {
                for resumes in [false, true] {
                    func button(placeholder: Bool) -> some View {
                        Button {} label: {
                            PlayResumeButtonLabel(
                                title: resumes ? "Resume" : "Play",
                                progress: resumes ? 0.4 : nil,
                                remainingText: resumes ? "43m" : nil,
                                seasonEpisodeText: resumes ? "S20, E100" : nil,
                                onLight: true, spacing: 10, capsuleWidth: 60,
                                isPlaceholder: placeholder, crossfadesPlaceholder: true,
                                wrapsText: width == 145
                            )
                        }
                        .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .primary))
                        .environment(\.dynamicTypeSize, size)
                    }
                    let placeholder = measure(button(placeholder: true), width: width)
                    let ready = measure(button(placeholder: false), width: width)
                    XCTAssertEqual(ready.width, placeholder.width, accuracy: 0.5)
                    XCTAssertEqual(ready.height, placeholder.height, accuracy: 0.5)
                    if !resumes && size == .large { XCTAssertLessThan(ready.width, 130) }
                    if width == 145 { XCTAssertLessThanOrEqual(ready.width, width + 0.5) }
                }
            }
        }
    }

    func testGlassRowKeepsOverflowWithinPhoneAndTabletWidths() {
        for width in [CGFloat(276), 331, 386, 720] {
            for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let row = ViewThatFits(in: .horizontal) {
                    ForEach((0...4).reversed(), id: \.self) { extras in
                        HeroActionRow {
                            self.play(wraps: false, minimumWidth: 180)
                            ForEach(0..<extras, id: \.self) { _ in
                                Button {} label: { Image(systemName: "bookmark") }
                                    .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .secondary, circular: true))
                            }
                        }
                    }
                    HeroActionRow(stacksVertically: true) { self.play(wraps: true) }
                }
                .environment(\.dynamicTypeSize, typeSize)
                XCTAssertLessThanOrEqual(measure(row, width: width).width, width + 0.5)
            }
        }
    }

    func testReducedGlassAndTransparencyKeepTheExistingFallback() {
        for reduceGlass in [false, true] {
            for kind in [TouchHeroActionButtonStyle.Kind.primary, .secondary] {
                let label = Button("Play", action: {})
                let existing = measure(label.buttonStyle(TouchHeroActionButtonStyle(kind: kind)), width: 300)
                let actual = measure(label
                    .buttonStyle(PlozziOSHeroActionButtonStyle(kind: kind))
                    .environment(\.plozzReducePanelGlass, reduceGlass)
                    .environment(\.plozzReduceTransparency, !reduceGlass), width: 300)
                XCTAssertEqual(actual, existing)
            }
        }
    }

    private func play(wraps: Bool, minimumWidth: CGFloat? = nil) -> some View {
        Button {} label: {
            PlayResumeButtonLabel(
                title: "Resume", progress: 0.4, remainingText: "43m",
                seasonEpisodeText: "S20, E100", onLight: true,
                spacing: 10, capsuleWidth: 60, wrapsText: wraps
            )
        }
        .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .primary, minimumWidth: minimumWidth))
    }

    private func measure(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 2_000))
    }
}
#endif
