#if os(iOS)
import SwiftUI

/// The shared empty / failure surface for iOS pages.
///
/// It deliberately builds on `ContentUnavailableView`, so the system keeps its
/// layout, Dynamic Type and VoiceOver behavior. The wrapper only gives callers a
/// stable place to add the app's recovery actions without re-implementing the
/// same `ContentUnavailableView` block on every page.
public struct PlozzStateView<Actions: View>: View {
    private let icon: String
    private let title: Text
    private let message: Text?
    private let actions: Actions

    public init(
        icon: String,
        title: Text,
        message: Text? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public init(
        icon: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            icon: icon,
            title: Text(title),
            message: message.map(Text.init),
            actions: actions
        )
    }

    public var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: icon)
            }
        } description: {
            if let message {
                message
            }
        } actions: {
            actions
        }
    }
}

public extension PlozzStateView where Actions == EmptyView {
    init(icon: String, title: Text, message: Text? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }

    init(icon: String, title: LocalizedStringResource, message: LocalizedStringResource? = nil) {
        self.init(icon: icon, title: Text(title), message: message.map(Text.init)) { EmptyView() }
    }
}
#endif
