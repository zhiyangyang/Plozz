#if canImport(SwiftUI)
import SwiftUI

public enum NavigationEntryFocusPreference: Equatable, Sendable {
    case pending
    case content
    case fallback
}

public extension View {
    /// Declares a page's entry target without changing ordinary directional focus.
    @ViewBuilder
    func navigationEntryFocus(_ preference: NavigationEntryFocusPreference?) -> some View {
        self
    }
}

#endif
