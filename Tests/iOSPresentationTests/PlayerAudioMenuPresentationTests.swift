#if os(iOS)
import AVFoundation
import CoreModels
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerAudioMenuPresentationTests: XCTestCase {
    func testNativeTracksSubmenuKeepsRichTitlesIDsAndCurrentSelection() throws {
        let options = TrackMenuBuilder.audioOptions(
            tracks: [
                .init(id: 17, kind: .audio, displayTitle: "English", language: "en", codec: "opus", channels: 6),
                .init(id: 42, kind: .audio, displayTitle: "French", language: "fr", codec: "aac", channels: 2)
            ], selectedID: 42, preferred: [], locale: .init(identifier: "en")
        )
        var picked: Int?
        let menu = PlayerAudioMenu.make(options: options, locale: .init(identifier: "en"), onSelect: { picked = $0 })
        XCTAssertEqual(menu.title, "Audio")
        XCTAssertEqual(menu.children.count, 1, "Unavailable enhancement must not produce a nonfunctional submenu.")
        let tracks = try XCTUnwrap(menu.children.first as? UIMenu)
        XCTAssertTrue(tracks.title.isEmpty, "The Audio menu already labels these tracks.")
        XCTAssertTrue(tracks.options.contains(.displayInline), "Audio tracks should not need another submenu tap.")
        XCTAssertTrue(tracks.options.contains(.singleSelection))
        let choices = tracks.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(choices.map(\.title), ["English (Opus 5.1)", "French (AAC Stereo)"])
        XCTAssertEqual(choices.map(\.state), [.off, .on], "The container's default is not the active selection.")
        perform(choices[0])
        XCTAssertEqual(picked, 17)
        perform(choices[1])
        XCTAssertEqual(picked, 42)
    }

    func testSoleTrackIsVisibleDisabledMetadata() throws {
        let menu = PlayerAudioMenu.make(options: [
            .init(id: 7, title: Text(verbatim: "English (Opus Stereo)"), isSelected: true, nativeTitle: "English (Opus Stereo)")
        ], onSelect: { _ in XCTFail("A sole track must not initiate a switch.") })
        let tracks = try XCTUnwrap(menu.children.first as? UIMenu)
        XCTAssertTrue(tracks.title.isEmpty)
        let track = try XCTUnwrap(tracks.children.first as? UIAction)
        XCTAssertEqual(track.title, "English (Opus Stereo)")
        XCTAssertEqual(track.state, .on)
        XCTAssertTrue(track.attributes.contains(.disabled))
    }

    func testSupportedEngineEnhancementUsesRealBinaryChoicesInItsOwnSubmenu() throws {
        var enabled: Bool?
        let menu = PlayerAudioMenu.make(
            options: [], dialogueEnhancement: true, locale: .init(identifier: "en"),
            onSelect: { _ in XCTFail("There are no tracks.") },
            onSetDialogueEnhancement: { enabled = $0 }
        )
        let enhancement = try XCTUnwrap(menu.children.first as? UIMenu)
        XCTAssertEqual(enhancement.title, "Enhance Dialogue")
        let choices = enhancement.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(choices.map(\.title), ["Off", "On"])
        XCTAssertEqual(choices.map(\.state), [.off, .on])
        perform(choices[0])
        XCTAssertEqual(enabled, false)
        perform(choices[1])
        XCTAssertEqual(enabled, true)
        XCTAssertEqual(menu.children.count, 1)
    }

    func testNoTracksAndNoWorkingEnhancementProducesNoOptions() {
        XCTAssertTrue(PlayerAudioMenu.make(options: [], onSelect: { _ in }).children.isEmpty)
    }

    func testAudioButtonUsesNativeMenuAndKeepsSnapshotAcrossClockUpdates() async throws {
        let state = MenuState()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: MenuFixture(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { self.button(in: host.view) != nil }
        let button = try XCTUnwrap(button(in: host.view))
        XCTAssertEqual(button.accessibilityIdentifier, "player-audio")
        XCTAssertEqual(button.accessibilityLabel, "Audio")
        XCTAssertEqual(PlayerOptionsMenuButton.Kind.audio.symbol, "waveform")
        let audioImage = try XCTUnwrap(button.image(for: .normal))
        let waveformImage = try XCTUnwrap(UIImage(
            systemName: "waveform", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3)
        ))
        XCTAssertTrue(audioImage.isEqual(waveformImage))
        XCTAssertTrue(button.showsMenuAsPrimaryAction)
        let interaction = try XCTUnwrap(button.contextMenuInteraction)
        defer { interaction.dismissMenu() }
        button.performPrimaryAction()
        try await waitUntil { button.presentedMenu != nil }
        let original = try XCTUnwrap(button.presentedMenu)
        XCTAssertEqual(original.title, "Audio")
        let tracks = try XCTUnwrap(original.children.first as? UIMenu)
        XCTAssertTrue(tracks.title.isEmpty, "The native popup must not repeat Audio as a section heading.")
        XCTAssertEqual(tracks.children.compactMap { ($0 as? UIAction)?.state }, [.on, .off])
        for tick in 1...10 {
            state.seconds = tick
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertTrue(button.presentedMenu === original)
        }
        XCTAssertEqual(state.presentations, [true])
        interaction.dismissMenu()
        try await waitUntil { button.presentedMenu == nil }
        state.selectedID = 42
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        button.performPrimaryAction()
        try await waitUntil { button.presentedMenu != nil }
        let reopened = try XCTUnwrap(button.presentedMenu?.children.first as? UIMenu)
        XCTAssertEqual(reopened.children.compactMap { ($0 as? UIAction)?.state }, [.off, .on])
        interaction.dismissMenu()
        try await waitUntil { button.presentedMenu == nil }
        XCTAssertEqual(state.presentations, [true, false, true, false])
    }

    private func perform(_ action: UIAction) {
        let button = UIButton(type: .system)
        button.addAction(action, for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)
    }

    private func button(in view: UIView) -> PlayerOptionsMenuControl? {
        if let button = view as? PlayerOptionsMenuControl { return button }
        return view.subviews.lazy.compactMap { self.button(in: $0) }.first
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    @MainActor @Observable
    final class MenuState {
        var seconds = 0
        var selectedID = 17
        var presentations: [Bool] = []

        var options: [PlayerTrackOption] {
            [
                .init(id: 17, title: Text(verbatim: "English (Opus 5.1)"),
                      isSelected: selectedID == 17, nativeTitle: "English (Opus 5.1)"),
                .init(id: 42, title: Text(verbatim: "French (AAC Stereo)"),
                      isSelected: selectedID == 42, nativeTitle: "French (AAC Stereo)")
            ]
        }
    }

    private struct MenuFixture: View {
        let state: MenuState

        var body: some View {
            VStack {
                Text(verbatim: "\(state.seconds)")
                PlayerAudioMenuButton(
                    options: state.options, onSelect: { state.selectedID = $0 },
                    onPresentationChange: { state.presentations.append($0) }
                )
            }
            .environment(\.locale, .init(identifier: "en"))
        }
    }

}
#endif
