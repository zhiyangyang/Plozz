#if canImport(SwiftUI)
import SwiftUI

/// Place this heading inside ordinary pages' scrollable content. Full-screen
/// editors may keep it outside their independently scrolling tool pane.
/// Add a subtitle only when the title cannot communicate the scope of the page.
public struct SettingsPageHeader<Trailing: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let trailing: Trailing

    public init(_ title: Text, subtitle: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: SettingsFormMetrics.controlSpacing) {
            heading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(PlozzTypography.font(.pageTitle))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                subtitle
                    .font(.subheadline)
                    .plozzForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SettingsPageHeader where Trailing == EmptyView {
    public init(_ title: Text, subtitle: Text? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }

    public init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.init(Text(title), subtitle: subtitle.map(Text.init))
    }

    public init(verbatim title: String, subtitle: LocalizedStringResource? = nil) { // l10n:content
        self.init(Text(verbatim: title), subtitle: subtitle.map(Text.init))
    }
}

public struct SettingsBackButton: View {
    private let action: () -> Void
    private let usesGlass: Bool

    public init(usesGlass: Bool = false, action: @escaping () -> Void) {
        self.action = action
        self.usesGlass = usesGlass
    }

    public var body: some View {
        control
    }

    private var control: some View {
        styledButton
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .fixedSize()
    }

    @ViewBuilder
    private var styledButton: some View {
        if usesGlass {
            button.plozzGlassPillButton()
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.backward")
                .labelStyle(.iconOnly)
        }
    }
}

#endif
