#if canImport(SwiftUI)
import Observation
import SwiftUI

public enum SettingsPageMotion {
    public static let travelDistance: CGFloat = 64
    public static let animation: Animation = .timingCurve(0.22, 0, 0.2, 1, duration: 0.42)

    public static func transition(edge: HorizontalEdge) -> AnyTransition {
        .modifier(
            active: SettingsPageVisibility(isVisible: false, hiddenEdge: edge),
            identity: SettingsPageVisibility(isVisible: true, hiddenEdge: edge)
        )
    }

    public static func transition(isReturning: Bool) -> AnyTransition {
        .asymmetric(
            insertion: transition(edge: isReturning ? .leading : .trailing),
            removal: transition(edge: isReturning ? .trailing : .leading)
        )
    }
}

private struct SettingsPageVisibility: ViewModifier {
    let isVisible: Bool
    let hiddenEdge: HorizontalEdge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: isVisible || reduceMotion ? 0
                : (hiddenEdge == .leading ? -1 : 1) * SettingsPageMotion.travelDistance)
            .opacity(isVisible ? 1 : 0)
    }
}

public extension View {
    func settingsPageVisibility(_ isVisible: Bool, hiddenEdge: HorizontalEdge = .leading) -> some View {
        modifier(SettingsPageVisibility(isVisible: isVisible, hiddenEdge: hiddenEdge))
    }
}


/// Native navigation outside the TV Settings workspace.
public struct SettingsPageLink<Destination: View, Label: View>: View {
    let destination: () -> Destination
    let label: () -> Label
    @State private var isPresented = false

    public init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    public var body: some View {
        // A NavigationLink can claim all sibling controls in a composite List cell.
        Button { isPresented = true } label: { label() }
            .navigationDestination(isPresented: $isPresented, destination: destination)
    }
}

@propertyWrapper
public struct SettingsPageDismiss: DynamicProperty {
    @Environment(\.dismiss) private var nativeDismiss

    public init() {}

    public var wrappedValue: () -> Void {
        return { nativeDismiss() }
    }
}

public extension View {
    func settingsPageDestination<Destination: View>(
        isPresented: Binding<Bool>, @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        modifier(SettingsPageDestination(isPresented: isPresented, destination: destination))
    }
}

private struct SettingsPageDestination<Destination: View>: ViewModifier {
    @Binding var isPresented: Bool
    let destination: () -> Destination

    func body(content: Content) -> some View {
        content.navigationDestination(isPresented: $isPresented, destination: destination)
    }
}
#endif
