import AppShelliOS
import AppRuntime
import CoreModels
import CoreNetworking
import CoreUI
import FeatureSettings
import Foundation
import SwiftUI
import UIKit

private final class PlozziOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlozziOSWindowOrientation.supportedOrientations(for: window)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PlozziOSDownloadNotificationBridge.activate()
        PlozziOSBackgroundSessionBridge.activate()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        PlozziOSBackgroundSessionBridge.handleEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}

@main
struct PlozziOSApp: App {
    @UIApplicationDelegateAdaptor(PlozziOSAppDelegate.self) private var appDelegate

    init() {
        let bootStart = DispatchTime.now().uptimeNanoseconds
        PlozzLog.boot("App.init START")
        _ = AppInstallation.current
        ProcessSignalPolicy.ignoreBrokenPipe()
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: nil
        )
        // Mirrors the tvOS entry point. `PLZSTALL=1` arms the opt-in main-actor
        // wake-up probe, which is how a device run can attribute the post-back
        // navigation lock to a real stall instead of a screenshot guess.
        MainActor.assumeIsolated { MainThreadStallProbe.startIfRequested() }
        PlozzLog.boot(
            "App.init END ms=\(Double(DispatchTime.now().uptimeNanoseconds - bootStart) / 1_000_000)"
        )
    }

    var body: some Scene {
        WindowGroup {
            PlozziOSRootView()
                .diagnosticRecordingStatus()
        }
    }
}
