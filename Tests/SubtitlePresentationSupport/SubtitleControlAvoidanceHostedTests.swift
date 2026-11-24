import CoreModels
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import CoreUI
@testable import FeaturePlayback

@MainActor
final class SubtitleControlAvoidanceHostedTests: XCTestCase {
    #if os(iOS)
    func testMobileAvoidanceSwitchEditsTextAndBitmapStyles() async throws {
        let scene = try await activeScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let controls = PlayerControlsModel()
        var saved = SubtitleStyle.profileDefault
        controls.subtitleStyle = saved
        let context = SubtitleStyleEditingContext(
            controls: controls, style: Binding(get: { saved }, set: { saved = $0 }),
            secondaryPreview: .constant(false)
        )
        let host = UIHostingController(rootView: NavigationStack {
            MobileSubtitleStyleEditor(viewModel: context)
        }.environment(\.locale, Locale(identifier: "en_US")))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func listedSwitches(_ view: UIView) -> [UISwitch] {
            if let list = view as? UICollectionView {
                return list.visibleCells.flatMap { descendants($0).compactMap { $0 as? UISwitch } }
            }
            return view.subviews.flatMap(listedSwitches)
        }
        func toggle() -> UISwitch? {
            listedSwitches(host.view).max {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            }
        }
        for format: String? in [nil, "PGS"] {
            controls.secondarySubtitleImagePrimaryFormat = format
            context.applySubtitleStyle(.profileDefault)
            try await waitUntil {
                window.layoutIfNeeded()
                return listedSwitches(host.view).count == (format == nil ? 2 : 1) && toggle()?.isOn == true
            }
            let control = try XCTUnwrap(toggle())
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Subtitle avoidance switch \(format ?? "text")"
            attachment.lifetime = .keepAlways
            add(attachment)
            control.setOn(false, animated: false)
            control.sendActions(for: .valueChanged)
            try await waitUntil { !saved.avoidsPlayerControls }
            XCTAssertFalse(controls.subtitleStyle.avoidsPlayerControls)
            XCTAssertTrue(saved.followsSystemStyle)
        }
    }
    #endif

    func testControlAvoidanceEditorDoesNotDisableDeviceCaptionMatching() {
        let controls = PlayerControlsModel()
        var saved = SubtitleStyle.profileDefault
        controls.subtitleStyle = saved
        let context = SubtitleStyleEditingContext(
            controls: controls, style: Binding(get: { saved }, set: { saved = $0 }),
            secondaryPreview: .constant(false)
        )
        var expected = saved
        expected.avoidsPlayerControls = false
        context.editSubtitleStyle { $0.avoidsPlayerControls = false }
        XCTAssertEqual(saved, expected)
        XCTAssertEqual(controls.subtitleStyle, expected)
        XCTAssertTrue(context.effectiveStyle.followsSystemStyle)
        XCTAssertFalse(context.effectiveStyle.avoidsPlayerControls)
        context.editSubtitleStyle { $0.avoidsPlayerControls = true }
        XCTAssertEqual(saved, .profileDefault)
    }

    func testRenderedTopArtworkStaysFixedWhileOnlyBottomArtworkAvoidsControls() async throws {
        let scene = try await activeScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        func bitmap(_ color: UIColor) throws -> CGImage {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 12)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 30, height: 12))
            }
            return try XCTUnwrap(image.cgImage)
        }
        let model = LiveSubtitleModel()
        model.style.followsSystemStyle = false
        model.style.opacity = 1
        model.beginLiveFeed()
        model.updateLiveCues([
            .init(id: 1, start: 0, end: 60, body: .image(.init(
                cgImage: try bitmap(.red), normalizedRect: CGRect(x: 0.2, y: 0.06, width: 0.6, height: 0.08),
                controlAvoidance: .fixed
            ))),
            .init(id: 2, start: 0, end: 60, body: .image(.init(
                cgImage: try bitmap(.green), normalizedRect: CGRect(x: 0.2, y: 0.86, width: 0.6, height: 0.08),
                controlAvoidance: .lowerRegion(
                    envelope: CGRect(x: 0.2, y: 0.84, width: 0.6, height: 0.12), minimumY: 0.18
                )
            )))
        ])
        model.tick(1)
        let controls = PlayerControlsModel()
        let fixture = ControlsFixture()
        fixture.height = root.view.bounds.height * 0.25
        let captions = UIHostingController(rootView: LiveSubtitleOverlay(model: model, controls: controls))
        let chrome = UIHostingController(rootView: FixtureControls(model: fixture, layout: controls.subtitleLayout))
        captions.safeAreaRegions = []
        chrome.safeAreaRegions = []
        for host in [captions as UIViewController, chrome as UIViewController] {
            root.addChild(host)
            host.view.backgroundColor = .clear
            host.view.frame = root.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.view.addSubview(host.view)
            host.didMove(toParent: root)
        }
        var resting = (top: CGRect.null, bottom: CGRect.null)
        try await waitUntil {
            window.layoutIfNeeded()
            resting = self.coloredRegions(in: window)
            return !resting.top.isNull && !resting.bottom.isNull
        }
        fixture.visible = true
        var raised = resting
        try await waitUntil {
            window.layoutIfNeeded()
            raised = self.coloredRegions(in: window)
            return !raised.bottom.isNull && raised.bottom.minY < resting.bottom.minY - 10
        }
        XCTAssertEqual(raised.top, resting.top)
        XCTAssertEqual(raised.bottom.height, resting.bottom.height, accuracy: window.bounds.width / 480,
                       "Allow one row of quantization in the downsampled pixel capture")
        XCTAssertLessThanOrEqual(raised.bottom.maxY, try XCTUnwrap(controls.subtitleLayout.frame).minY)
        model.style.avoidsPlayerControls = false
        try await waitUntil {
            window.layoutIfNeeded()
            let disabled = self.coloredRegions(in: captions.view)
            return disabled.top == resting.top && disabled.bottom == resting.bottom
        }
        XCTAssertNotNil(controls.subtitleLayout.frame)
        model.style.avoidsPlayerControls = true
        try await waitUntil {
            window.layoutIfNeeded()
            return self.coloredRegions(in: window).bottom == raised.bottom
        }
        fixture.visible = false
        try await waitUntil {
            window.layoutIfNeeded()
            let restored = self.coloredRegions(in: window)
            return restored.top == resting.top && restored.bottom == resting.bottom
        }
    }

    func testDisplayClockReleasesItsDisplayLinkAndDoesNotOwnThePlayer() async throws {
        let scene = try await activeScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        var engine: NativeVideoEngine? = NativeVideoEngine()
        var model: LiveSubtitleModel? = LiveSubtitleModel()
        var clock: SubtitleDisplayClockView? = SubtitleDisplayClockView()
        weak var weakEngine = engine
        weak var weakModel = model
        weak var weakClock = clock
        clock?.engine = engine
        clock?.subtitles = model
        window.rootViewController?.view.addSubview(try XCTUnwrap(clock))
        engine = nil
        model = nil
        XCTAssertNil(weakEngine)
        XCTAssertNil(weakModel)
        clock?.removeFromSuperview()
        clock = nil
        try await waitUntil { weakClock == nil }
    }

    func testSeparateControlsHostLiftsAndRestoresRenderedSubtitlesWithoutChangingSavedStyle() async throws {
        let scene = try await activeScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let model = LiveSubtitleModel()
        model.style.fontFamily = .system
        model.style.verticalPosition = 0.06
        model.style.followsSystemStyle = false
        let originalStyle = model.style
        model.loadPrimary(SubtitleCueParser.parse("WEBVTT\n\n00:00:00.000 --> 00:01:00.000\nA visible subtitle gyp.\n", id: 1))
        model.tick(1)
        let controls = PlayerControlsModel()
        let fixture = ControlsFixture()
        let root = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let captions = UIHostingController(rootView: LiveSubtitleOverlay(model: model, controls: controls))
        let chrome = UIHostingController(rootView: FixtureControls(model: fixture, layout: controls.subtitleLayout))
        for host in [captions as UIViewController, chrome as UIViewController] {
            root.addChild(host)
            host.view.backgroundColor = .clear
            host.view.frame = root.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.view.addSubview(host.view)
            host.didMove(toParent: root)
        }
        captions.safeAreaRegions = []
        chrome.safeAreaRegions = []
        try await waitUntil {
            window.layoutIfNeeded()
            return !self.frames(in: captions.view, relativeTo: window).isEmpty
        }
        let resting = try XCTUnwrap(frames(in: captions.view, relativeTo: window).first)
        #if DEBUG
        let line = try XCTUnwrap(subtitleLines(in: captions.view).first)
        let builds = line.layoutBuildCountForTesting
        #endif
        fixture.visible = true
        try await waitUntil {
            window.layoutIfNeeded()
            guard let obstruction = controls.subtitleLayout.frame,
                  let frame = self.frames(in: captions.view, relativeTo: window).first else { return false }
            return abs(frame.maxY - (obstruction.minY - SubtitleOverlayGeometry.controlsClearance)) <= 1
        }
        let raised = try XCTUnwrap(frames(in: captions.view, relativeTo: window).first)
        XCTAssertLessThan(raised.maxY, resting.maxY)
        XCTAssertEqual(raised.size, resting.size)
        XCTAssertEqual(model.style, originalStyle)

        fixture.height = 220
        try await waitUntil {
            window.layoutIfNeeded()
            guard let obstruction = controls.subtitleLayout.frame,
                  let frame = self.frames(in: captions.view, relativeTo: window).first else { return false }
            return abs(frame.maxY - (obstruction.minY - SubtitleOverlayGeometry.controlsClearance)) <= 1
                && frame.maxY < raised.maxY
        }
        fixture.visible = false
        try await waitUntil {
            window.layoutIfNeeded()
            guard let frame = self.frames(in: captions.view, relativeTo: window).first else { return false }
            return controls.subtitleLayout.frame == nil && abs(frame.maxY - resting.maxY) <= 1
        }
        XCTAssertEqual(model.style, originalStyle)
        #if DEBUG
        XCTAssertEqual(line.layoutBuildCountForTesting, builds, "Moving around controls must reuse shaped text")
        #endif
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = "Restored subtitle position after controls hide"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func subtitleLines(in view: UIView) -> [SubtitleLineView] {
        if let line = view as? SubtitleLineView { return [line] }
        return view.subviews.flatMap { subtitleLines(in: $0) }
    }


    private func frames(in view: UIView, relativeTo window: UIWindow) -> [CGRect] {
        if let line = view as? SubtitleLineView { return [line.convert(line.bounds, to: window)] }
        return view.subviews.flatMap { frames(in: $0, relativeTo: window) }
    }

    private func coloredRegions(in view: UIView) -> (top: CGRect, bottom: CGRect) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let image = image.cgImage else { return (.null, .null) }
        let width = 480
        let height = max(1, Int(CGFloat(width) * view.bounds.height / view.bounds.width))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var red = CGRect.null, green = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let point = CGRect(x: x, y: y, width: 1, height: 1)
                if bytes[offset] > 220 && bytes[offset + 1] < 40 { red = red.union(point) }
                if bytes[offset + 1] > 220 && bytes[offset] < 40 { green = green.union(point) }
            }
        }
        let transform = CGAffineTransform(scaleX: view.bounds.width / CGFloat(width),
                                          y: view.bounds.height / CGFloat(height))
        return (red.applying(transform), green.applying(transform))
    }

    private func activeScene() async throws -> UIWindowScene {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        return try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
    }

    private func waitUntil(
        failureMessage: @autoclosure () -> String = "Subtitle/control layout did not settle",
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), failureMessage())
    }
}

@MainActor @Observable
private final class ControlsFixture {
    var visible = false
    var height: CGFloat = 160
}

private struct FixtureControls: View {
    let model: ControlsFixture
    let layout: SubtitleControlsLayout
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Rectangle().fill(.black.opacity(0.8))
                .frame(height: model.height)
                .reportSubtitleControlsFrame(isVisible: model.visible) { layout.frame = $0 }
                .opacity(model.visible ? 1 : 0)
        }
        .ignoresSafeArea()
    }
}
