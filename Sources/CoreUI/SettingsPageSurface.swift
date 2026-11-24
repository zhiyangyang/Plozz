#if os(iOS) && canImport(SwiftUI)
import SwiftUI

/// Canonical root for an iPhone/iPad settings screen. It pairs the standard
/// settings list behavior with Plozz's theme-aware page surface so new screens
/// cannot accidentally fall back to SwiftUI's system grouped colors.
public struct SettingsPageList<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        List {
            content
        }
        .settingsPageSurface()
    }
}

/// Composite panels can contain several NavigationLinks. Hosting a whole panel
/// in one List cell lets native row activation push all of its destinations.
public struct SettingsPageScroll<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileSettingsMetrics.sectionSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsPageSurface()
    }
}

public struct SettingsPageSurface: ViewModifier {
    @Environment(\.themePalette) private var palette
    private let titleDisplayMode: NavigationBarItem.TitleDisplayMode
    private let horizontalInset: CGFloat
    private let contentMaxWidth: CGFloat

    public init(
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        horizontalInset: CGFloat = MobileSettingsMetrics.pageInset,
        contentMaxWidth: CGFloat = PlozziOSPageMetrics.formMaxWidth
    ) {
        self.titleDisplayMode = titleDisplayMode
        self.horizontalInset = horizontalInset
        self.contentMaxWidth = contentMaxWidth
    }

    public func body(content: Content) -> some View {
        content
            .tint(palette.primaryText)
            .toggleStyle(SettingsSwitchToggleStyle())
            .listStyle(.plain)
            .listRowSpacing(MobileSettingsMetrics.sectionSpacing)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 24, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.horizontal, horizontalInset)
            // Pushed navigation hosts need their own copy of the sheet background.
            .settingsPageBackground(paintsDialogBackground: true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}

public extension View {
    func settingsPageSurface(
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        horizontalInset: CGFloat = MobileSettingsMetrics.pageInset,
        contentMaxWidth: CGFloat = PlozziOSPageMetrics.formMaxWidth
    ) -> some View {
        modifier(SettingsPageSurface(
            titleDisplayMode: titleDisplayMode,
            horizontalInset: horizontalInset,
            contentMaxWidth: contentMaxWidth
        ))
    }
}
#endif
