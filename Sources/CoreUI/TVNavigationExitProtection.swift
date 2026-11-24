import SwiftUI


public extension View {
    /// A tab's content overrides the surrounding navigation focus scope, including
    /// any detail pages pushed inside it.
    func tvNavigationExitProtectionContent() -> some View {
        self
    }

    /// Keeps short Back presses in navigation chrome from exiting the app.
    /// Custom navigation passes its focus state. Native TabView content must use
    /// `tvNavigationExitProtectionContent()` to distinguish it from the chrome.
    func tvNavigationExitProtection(
        isEnabled: Bool,
        navigationHasFocus: Bool? = nil
    ) -> some View {
        self
    }
}
