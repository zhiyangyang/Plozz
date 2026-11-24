import SwiftUI

/// Shared picture-layout and renderer-entry motion, separate from native focus timing.
public enum MultiviewMotion {
    public static var duration: TimeInterval {
        0.32
    }

    public static var animation: Animation { .easeInOut(duration: duration) }
}

/// Focus belongs to the video surface, not the player or its transport controls.
public struct VideoCardFocus {
    public let identifier: String
    public let title: String // l10n:content - Provider-supplied channel label.
    public let audible: Bool
    public let presentsEffect: Bool
    public let cornerRadius: CGFloat
    public var horizontalInset: CGFloat
    public let request: Int
    public let prefersFocus: Bool
    public let focused: (Bool) -> Void
    public let activate: () -> Void
    public let promote: () -> Void
    public let replace: () -> Void
    public let remove: (() -> Void)?
    public let back: () -> Void
    public let caption: AnyView

    public init(
        identifier: String, title: String, audible: Bool, presentsEffect: Bool, // l10n:content - Provider-supplied channel label.
        cornerRadius: CGFloat, horizontalInset: CGFloat, request: Int, prefersFocus: Bool,
        focused: @escaping (Bool) -> Void, activate: @escaping () -> Void,
        promote: @escaping () -> Void, replace: @escaping () -> Void,
        remove: (() -> Void)? = nil,
        back: @escaping () -> Void = {}, caption: AnyView = AnyView(EmptyView())
    ) {
        self.identifier = identifier
        self.title = title
        self.audible = audible
        self.presentsEffect = presentsEffect
        self.cornerRadius = cornerRadius
        self.horizontalInset = horizontalInset
        self.request = request
        self.prefersFocus = prefersFocus
        self.focused = focused
        self.activate = activate
        self.promote = promote
        self.replace = replace
        self.remove = remove
        self.back = back
        self.caption = caption
    }
}

private struct VideoCardFocusKey: EnvironmentKey {
    static let defaultValue: VideoCardFocus? = nil
}

public extension EnvironmentValues {
    var videoCardFocus: VideoCardFocus? {
        get { self[VideoCardFocusKey.self] }
        set { self[VideoCardFocusKey.self] = newValue }
    }
}

public extension View {
    func videoCardFocusSurface() -> some View {
        modifier(VideoCardFocusModifier(background: { _ in AnyView(EmptyView()) }))
    }

    func videoCardFocusSurface<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        let view = AnyView(background())
        return modifier(VideoCardFocusModifier(background: { _ in view }))
    }

    func videoCardFocusSurface<Background: View>(
        @ViewBuilder background: @escaping (_ isFocused: Bool) -> Background
    ) -> some View {
        modifier(VideoCardFocusModifier(background: { AnyView(background($0)) }))
    }
}

private struct VideoCardFocusModifier: ViewModifier {
    @Environment(\.videoCardFocus) private var configuration
    let background: (Bool) -> AnyView

    func body(content: Content) -> some View {
        content
    }
}
