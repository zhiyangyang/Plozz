import Foundation

/// A horizontal swipe through a live channel's rewind window, as VOD's scrub
/// surface does it: the playhead follows the finger (`preview`) and the seek is
/// made once, where it lifts (`commit`).
///
/// Kept free of UIKit so the axis lock and the seconds mapping are testable;
/// `LiveChannelTimelineScrubPan` feeds it the Siri Remote's pan samples.
struct LiveChannelTimelineScrub {
    /// Seconds behind live the scrub is showing; nil when not scrubbing.
    private(set) var behindLive: TimeInterval?
    private var startBehind: TimeInterval = 0
    private var lastTranslationX: Double = 0
    private var axis: Axis = .undecided

    enum Axis { case undecided, horizontal, vertical }

    /// Travel before the swipe commits to an axis, so a vertical swipe to the
    /// tabs never nudges the playhead on its way.
    static let axisLockDistance: Double = 24

    mutating func begin(behindLive current: TimeInterval) {
        startBehind = max(0, current)
        lastTranslationX = 0
        axis = .undecided
        behindLive = nil
    }

    /// One pan sample. Right moves toward live (less behind).
    mutating func change(
        translationX: Double, translationY: Double, speed: Double, windowSeconds: TimeInterval
    ) {
        if axis == .undecided {
            guard max(abs(translationX), abs(translationY)) >= Self.axisLockDistance else { return }
            axis = abs(translationX) > abs(translationY) * 1.2 ? .horizontal : .vertical
            if axis == .horizontal {
                behindLive = startBehind
                lastTranslationX = translationX
            }
        }
        guard axis == .horizontal, let current = behindLive else { return }
        let dx = translationX - lastTranslationX
        lastTranslationX = translationX
        let delta = ScrubGeometry.scrubDeltaSeconds(
            translationDeltaPoints: dx, speedPointsPerSecond: speed,
            tuning: Self.tuning(windowSeconds: windowSeconds)
        )
        behindLive = min(max(current - delta, 0), max(0, windowSeconds))
    }

    /// The scrub's landing, or nil if the swipe never became one.
    mutating func end() -> TimeInterval? {
        defer { behindLive = nil; axis = .undecided }
        return behindLive
    }

    mutating func cancel() {
        behindLive = nil
        axis = .undecided
    }

    /// VOD's transfer function, scaled to the window rather than a runtime, so a
    /// swipe covers the same share of the bar whatever the window's depth.
    static func tuning(windowSeconds: TimeInterval) -> ScrubGeometry.Tuning {
        let scale = min(max(windowSeconds / 7_200, 0.05), 1.6)
        return ScrubGeometry.Tuning(
            baseSecondsPerPoint: 0.18 * scale,
            accelOnsetSpeed: 500,
            accelSaturationSpeed: 3_500,
            maxAccelMultiplier: 5
        )
    }
}
