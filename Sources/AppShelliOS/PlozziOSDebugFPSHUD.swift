#if DEBUG && os(iOS)
import Observation
import QuartzCore
import SwiftUI

/// Debug-only frame cadence overlay for physical-device scrolling checks.
///
/// Enabled with `PLOZZ_FPS_HUD=1` in the launch environment (or `--fps-hud`).
/// It counts `CADisplayLink` callbacks, so a blocked main thread or a skipped
/// display refresh lowers the reported number. It is a quick cadence signal,
/// not a replacement for Instruments' Animation Hitches trace.
struct PlozziOSDebugFPSHUD: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PLOZZ_FPS_HUD"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--fps-hud")
    }

    @State private var model = PlozziOSDebugFPSModel()

    var body: some View {
        Text(String(format: "%.1f FPS", model.fps))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.68), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { model.start() }
            .onDisappear { model.stop() }
    }
}

@MainActor
@Observable
private final class PlozziOSDebugFPSModel {
    private(set) var fps: Double = 0

    private var link: CADisplayLink?
    private var frames = 0
    private var windowStart = CACurrentMediaTime()

    func start() {
        guard link == nil else { return }
        frames = 0
        windowStart = CACurrentMediaTime()
        fps = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        frames += 1
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 0.5 else { return }
        fps = Double(frames) / elapsed
        frames = 0
        windowStart = now
    }
}
#endif
