import CoreUI
import CoreModels
import FeatureSettings
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class ICloudOnboardingHostedTests: XCTestCase {
    func testChoicesRenderInBothThemesAndPrimaryReceivesTVFocus() async throws {
        let sizes: [(CGFloat, CGFloat, DynamicTypeSize)] = [
            (393, 852, .large), (393, 852, .accessibility1), (1024, 1366, .large)
        ]
        for scheme in [ColorScheme.dark, .light] {
            for (width, height, typeSize) in sizes {
                try await render(width: width, height: height, typeSize: typeSize, scheme: scheme)
            }
        }
    }

    private func render(
        width: CGFloat, height: CGFloat, typeSize: DynamicTypeSize, scheme: ColorScheme,
        restorationPhase: InitialSetupRestorationPhase? = nil,
        restorationActivity: InitialSetupRestorationActivity = .liveTVSources
    ) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        var choices: [Bool] = []
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = UIHostingController(rootView:
            Group {
                if let restorationPhase {
                    ICloudRestorationView(
                        phase: restorationPhase,
                        activity: restorationActivity,
                        onRetry: { choices.append(true) },
                        onSetUpManually: { choices.append(false) }
                    )
                } else {
                    ICloudOnboardingView { choices.append($0) }
                }
            }
                .environment(\.themePalette, scheme == .dark ? .dark : .light)
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, typeSize)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let expectedFocus: String? = switch restorationPhase {
        case nil: "Enable iCloud Sync"
        case .unavailable: "Retry"
        case .slow: "Set up manually"
        default: nil
        }
        func spinners(in view: UIView) -> [UIActivityIndicatorView] {
            (view as? UIActivityIndicatorView).map { [$0] } ?? view.subviews.flatMap(spinners)
        }
        if let restorationPhase, [.restoring, .slow, .stopping].contains(restorationPhase),
           !UIAccessibility.isReduceMotionEnabled {
            try await waitUntil { !spinners(in: window).isEmpty }
        }
        // Only the native indeterminate spinner is allowed to keep animating during capture.
        try await waitForHostedLayout(window, ignoringAnimationIn: spinners(in: window).map(\.layer))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "iCloud-onboarding-\(Int(width))-\(typeSize)-\(scheme)-\(String(describing: restorationPhase))-\(restorationActivity)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let observations = request.results ?? []
        let strings = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = strings.joined(separator: " ")
        let labels: [String]
        if let restorationPhase {
            labels = switch restorationPhase {
            case .unavailable: ["Couldn't restore your setup", "Retry", "Set up manually", "iCloud Sync stays on"]
            case .slow: ["Restoring setup from iCloud", "Taking longer than expected", "Set up manually", "iCloud Sync stays on"]
            case .restoring: ["Restoring setup from iCloud"]
            case .stopping: ["Preparing manual setup"]
            case .hidden, .checking: []
            }
            XCTAssertFalse(text.contains("Continue"))
            if restorationPhase != .slow && restorationPhase != .unavailable {
                XCTAssertFalse(text.contains("Set up manually"))
                XCTAssertFalse(text.contains("Retry"))
            }
            if restorationPhase == .checking {
                XCTAssertFalse(text.contains("Restoring setup"))
            }
            if restorationPhase == .restoring || restorationPhase == .slow {
                let expectedActivity = switch restorationActivity {
                case .checkingICloud: "Checking iCloud"
                case .profilesAndSettings: "Restoring profiles and settings"
                case .servers: "Restoring servers"
                case .liveTVSources: "Restoring Live TV sources"
                case .signingInToServers: "Signing in to servers"
                }
                XCTAssertTrue(text.contains(expectedActivity), "Missing active work: \(text)")
            } else {
                XCTAssertFalse(text.contains("Restoring Live TV sources"), "Inactive screens must not announce work")
            }
        } else {
            labels = ["iCloud Sync", "Enable iCloud Sync", "Not now", "Settings"]
        }
        for label in labels {
            XCTAssertTrue(text.contains(label), "Missing \(label): \(text)")
        }
        XCTAssertTrue(choices.isEmpty, "Rendering/default focus must never accept iCloud for the user.")
    }

    func testRestorationShowsManualSetupOnlyWhenSlowOrUnavailable() async throws {
        let sizes: [(CGFloat, CGFloat, DynamicTypeSize)] = [
            (393, 852, .large), (393, 852, .accessibility1), (1024, 1366, .large)
        ]
        for phase in [InitialSetupRestorationPhase.checking, .restoring, .slow, .unavailable, .stopping] {
            for scheme in [ColorScheme.dark, .light] {
                for (width, height, typeSize) in sizes {
                    try await render(width: width, height: height, typeSize: typeSize,
                                     scheme: scheme, restorationPhase: phase)
                }
            }
        }
    }

    func testAllActualRestorationActivitiesRender() async throws {
        let size: (CGFloat, CGFloat) = (393, 852)
        for activity in [InitialSetupRestorationActivity.checkingICloud, .profilesAndSettings, .servers,
                         .liveTVSources, .signingInToServers] {
            try await render(width: size.0, height: size.1, typeSize: .large, scheme: .dark,
                             restorationPhase: .restoring, restorationActivity: activity)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}
