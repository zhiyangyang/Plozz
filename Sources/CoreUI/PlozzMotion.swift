#if canImport(SwiftUI)
import SwiftUI

/// The shared motion vocabulary for ordinary app UI.
///
/// Navigation and modal transitions belong to the system. These levels are for
/// state changes a view owns: a button press, local content arriving, a loading
/// swap. Player and music surfaces may use richer movement, but must still
/// resolve through ``animation(_:reduceMotion:)`` or their own Reduce Motion
/// branch.
public enum PlozzMotion {
    public enum Level: Sendable {
        /// Button feedback, toggles, selections.
        case micro
        /// Local content replacement and image arrival.
        case content
        /// Skeleton-to-content swaps.
        case loading
        /// Deliberate movement. Never applied to a whole page by default.
        case emphasis
    }

    public static let micro: Animation = .easeOut(duration: 0.14)
    public static let content: Animation = .easeOut(duration: PageMotion.contentRevealDuration)
    public static let loading: Animation = .easeOut(duration: 0.22)
    public static let emphasis: Animation = .easeInOut(duration: 0.30)

    /// Returns `nil` under Reduce Motion so callers can keep state changes
    /// instant without branching at every call site.
    public static func animation(_ level: Level, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch level {
        case .micro: return micro
        case .content: return content
        case .loading: return loading
        case .emphasis: return emphasis
        }
    }
}
#endif
