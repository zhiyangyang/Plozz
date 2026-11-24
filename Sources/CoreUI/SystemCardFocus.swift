import CoreModels
import Observation
import SwiftUI

private struct NativeFocusSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NativeArtworkSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NativeInformationFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var plozzNativeInformationFocus: Bool {
        get { self[NativeInformationFocusKey.self] }
        set { self[NativeInformationFocusKey.self] = newValue }
    }

    var plozzNativeFocusSurface: Bool {
        get { self[NativeFocusSurfaceKey.self] }
        set { self[NativeFocusSurfaceKey.self] = newValue }
    }

    var plozzNativeArtworkSurface: Bool {
        get { self[NativeArtworkSurfaceKey.self] }
        set { self[NativeArtworkSurfaceKey.self] = newValue }
    }
}

@propertyWrapper
public struct PlozzCardFocus: DynamicProperty {
    @FocusState private var focused: Bool
    @State private var observation = NativeFocusObservation()
    @State private var request = Request()
    @Environment(\.plozzCardFocusStyle) private var style

    public init() {}

    public var wrappedValue: Bool {
        get {
            focused
        }
        nonmutating set {
            if newValue {
                projectedValue.requestFocus()
            } else {
                request.wantsFocus = false
                focused = false
            }
        }
    }

    private var usesNativeFocus: Bool {
        false
    }

    struct Request: Equatable {
        var generation: UInt64 = 0
        var wantsFocus = false
        var animated = true
    }

    public var projectedValue: Binding {
        Binding(
            focusState: $focused,
            observation: observation,
            request: $request,
            requestSnapshot: request, usesNativeFocus: usesNativeFocus
        )
    }

    @Observable
    final class NativeFocusObservation {
        var isFocused = false
    }

    public struct Binding {
        public let focusState: FocusState<Bool>.Binding
        let observation: NativeFocusObservation
        let request: SwiftUI.Binding<Request>
        // The command value participates in SwiftUI invalidation even when the
        // native coordinator is the only consumer of the writable binding.
        let requestSnapshot: Request
        let usesNativeFocus: Bool

        var isFocused: Bool {
            usesNativeFocus ? observation.isFocused : focusState.wrappedValue
        }

        public func requestFocus(animated: Bool = true) {
            if usesNativeFocus {
                var next = request.wrappedValue
                next.generation &+= 1
                next.wantsFocus = true
                next.animated = animated
                request.wrappedValue = next
            } else {
                focusState.wrappedValue = true
            }
        }
    }
}

public extension View {
    func plozzCardFocusEffect() -> some View {
        modifier(CardFocusEffectAvailability())
    }

    /// Focus presentation belongs to the surrounding TVUIKit control.
    func plozzSystemCardProjection(cornerRadius: CGFloat) -> some View {
        self
    }

    func plozzRestingCardShadow(isFocused: Bool) -> some View {
        modifier(RestingCardShadow(isFocused: isFocused))
    }

    func plozzCardArtworkClip<S: Shape>(_ shape: S) -> some View {
        modifier(CardArtworkClip(shape: shape))
    }

    func plozzNativeMediaButtonStyle() -> some View {
        modifier(NativeMediaButtonStyle())
    }

    func plozzCardFocusButtonStyle<Style: ButtonStyle>(
        _ fallback: Style, cornerRadius: CGFloat, contentSuppliesProjection: Bool = false
    ) -> some View {
        modifier(CardFocusButtonStyle(fallback: fallback, cornerRadius: cornerRadius,
                                      contentSuppliesProjection: contentSuppliesProjection))
    }
}

private struct CardFocusButtonStyle<Style: ButtonStyle>: ViewModifier {
    let fallback: Style
    let cornerRadius: CGFloat
    let contentSuppliesProjection: Bool
    @Environment(\.plozzCardFocusStyle) private var style
    @Environment(\.plozzNativeInformationFocus) private var informationFocus

    func body(content: Content) -> some View {
        content.buttonStyle(fallback)
    }
}


private struct NativeMediaButtonStyle: ViewModifier {
    @Environment(\.plozzCardStyle) private var cardStyle

    func body(content: Content) -> some View {
        content
    }
}

private struct CardArtworkClip<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.plozzNativeArtworkSurface) private var nativeArtworkSurface

    func body(content: Content) -> some View {
        content.clipShape(shape)
    }
}

private struct CardFocusEffectAvailability: ViewModifier {
    @Environment(\.plozzCardFocusStyle) private var style

    func body(content: Content) -> some View {
        content.focusEffectDisabled(!style.usesSystemEffect)
    }
}

private struct RestingCardShadow: ViewModifier {
    let isFocused: Bool
    @Environment(\.plozzNativeFocusSurface) private var nativeSurface

    func body(content: Content) -> some View {
        if nativeSurface {
            content
        } else {
            content.shadow(
                color: .black.opacity(isFocused ? 0.36 : 0.15),
                radius: isFocused ? 20 : 8,
                y: isFocused ? 10 : 4
            )
        }
    }
}
