#if canImport(SwiftUI)
import CoreUI
import SwiftUI

/// A settings choice is one focusable row; the system still owns its menu.
/// Inline picker options override grouped containers that otherwise add a submenu.
struct SettingsMenuRow<Options: View>: View {
    let title: LocalizedStringResource
    let value: Text
    var subtitle: LocalizedStringResource? = nil
    var icon: String? = nil
    var minimumContentHeight: CGFloat? = nil
    @ViewBuilder var options: () -> Options

    var body: some View {
        Menu {
            options().pickerStyle(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent {
                    HStack {
                        if let icon { Image(systemName: icon) }
                        SettingsMenuValue(value)
                    }
                } label: {
                    Text(title)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(SettingsRowMetrics.descriptionFont)
                        .plozzForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: minimumContentHeight)
        }
        .settingsActionRow()
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
    }
}
#endif
