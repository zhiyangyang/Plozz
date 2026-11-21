#if os(iOS)
import SwiftUI

private struct PlozziOSDetailTagNavigatorKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String) -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens the catalog for one of the tag chips in a detail hero.
    var plozziOSDetailTagNavigator: (@MainActor (String) -> Void)? {
        get { self[PlozziOSDetailTagNavigatorKey.self] }
        set { self[PlozziOSDetailTagNavigatorKey.self] = newValue }
    }
}
#endif
