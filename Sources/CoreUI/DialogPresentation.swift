#if canImport(SwiftUI)
import SwiftUI


private struct DialogBackgroundOwnedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var plozzDialogBackgroundOwned: Bool {
        get { self[DialogBackgroundOwnedKey.self] }
        set { self[DialogBackgroundOwnedKey.self] = newValue }
    }
}

struct PlozzDialogBackgroundStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let palette = environment.themePalette
        if environment.gradientBackgroundsEnabled {
            return AnyShapeStyle(AmbientGradientBackground.mesh(
                colors: AmbientGradientBackground.meshColors(tint: nil, palette: palette)
            ))
        }
        return AnyShapeStyle(palette.overlay.fill)
    }
}

/// One opaque surface for the entire dialog, including native presentation insets.
struct PlozzDialogBackground: View {
    var body: some View {
        Rectangle()
            .fill(PlozzDialogBackgroundStyle())
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct PlozzDialogContent<Content: View>: View {
    let content: Content
    let style: PlozzSheetStyle
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var cardSurface = NativeGradientCardSurface()
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif

    var body: some View {
        content
            #if os(iOS)
            .plozzOpaqueNavigationChrome()
            .environment(\.settingsGradientCardSurface, style == .standard ? cardSurface : nil)
            #endif
            .scrollContentBackground(.hidden)
            .environment(\.plozzDialogBackgroundOwned, style == .standard)
            .presentationBackground {
                if style == .standard {
                    PlozzDialogBackground()
                        #if os(iOS)
                        .background {
                            NativeGradientViewport(
                                surface: cardSurface,
                                style: .init(
                                    colors: AmbientGradientBackground.meshColors(tint: nil, palette: palette),
                                    palette: palette, informationSurfaceOpacity: 0
                                ),
                                reduceMotion: reduceMotion
                            )
                            .ignoresSafeArea()
                        }
                        #endif
                } else {
                    Color.clear
                }
            }
    }
}

public enum PlozzSheetStyle {
    case standard
    /// Content supplies its own dimming and a shared `.overlay` card surface.
    case floatingCard
}

/// The small set of presentation geometries app-owned sheets may use.
///
/// Use a native sheet or cover first; this only keeps the size choice consistent
/// when a flow needs one. Full-screen covers ignore sizing.
public enum PlozzSheetSize: Sendable {
    case form
    case page
    case full
    case detents(Set<PresentationDetent>)
}

public extension View {
    @ViewBuilder
    func plozzSheetSize(_ size: PlozzSheetSize) -> some View {
        #if os(iOS)
        switch size {
        case .form:
            presentationSizing(.form)
        case .page:
            presentationSizing(.page)
        case .full:
            self
        case let .detents(detents):
            presentationDetents(detents)
                .presentationDragIndicator(.visible)
        }
        #else
        self
        #endif
    }
}

public extension View {
    /// The existing sheet surface when several flows share one native presenter.
    func plozzDialogSurface(style: PlozzSheetStyle = .standard) -> some View {
        PlozzDialogContent(content: self, style: style)
    }

    func plozzSheet<SheetContent: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        style: PlozzSheetStyle = .standard,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            PlozzDialogContent(content: content(), style: style)
        }
    }

    func plozzSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        style: PlozzSheetStyle = .standard,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            PlozzDialogContent(content: content(item), style: style)
        }
    }

    /// A themed sheet on iOS and the caller's ordinary native sheet on tvOS.
    ///
    /// Used by feature screens that exist on both platforms but should not
    /// inherit the tvOS full-screen dialog treatment.
    @ViewBuilder
    func plozzThemedSheet<SheetContent: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        #if os(iOS)
        plozzSheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder
    func plozzThemedSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        #if os(iOS)
        plozzSheet(item: item, onDismiss: onDismiss, content: content)
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    #if os(iOS)
    /// Full-screen flows own their own page background, even when opened from a sheet.
    func plozzFullScreenCover<CoverContent: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> CoverContent
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            content().environment(\.plozzDialogBackgroundOwned, false)
                #if os(iOS)
                .plozzOpaqueNavigationChrome()
                #endif
        }
    }

    func plozzFullScreenCover<Item: Identifiable, CoverContent: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> CoverContent
    ) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { item in
            content(item).environment(\.plozzDialogBackgroundOwned, false)
                #if os(iOS)
                .plozzOpaqueNavigationChrome()
                #endif
        }
    }
    #endif
}
#endif
