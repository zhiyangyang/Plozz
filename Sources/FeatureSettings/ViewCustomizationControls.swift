#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

struct ViewPreferenceChoiceGroup<Content: View>: View {
    var rowSize: SettingsRowSize = .standard
    @ViewBuilder var content: () -> Content

    var body: some View {
        SettingsSectionGroup(content: content)
    }
}

struct ViewPreferenceChoiceRow: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource? = nil
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                    if isSelected, let detail {
                        Text(detail).font(SettingsRowMetrics.descriptionFont).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .settingsControlTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ViewCustomizationLink<Destination: View>: View {
    let isCustomized: Bool
    var title: LocalizedStringResource = "Customize by view"
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        SettingsDetailLink(destination: destination) {
            ViewCustomizationLinkLabel(isCustomized: isCustomized, title: title)
                .settingsControlTarget()
        }
    }
}

private struct ViewCustomizationLinkLabel: View {
    let isCustomized: Bool
    let title: LocalizedStringResource
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            layout {
                Text(title)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if isCustomized {
                    Text("Custom")
                        .font(.caption.weight(.medium))
                        .settingsRowSecondary()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            Image(systemName: "chevron.right").accessibilityHidden(true)
        }
    }
}

struct ViewCustomizationList<Content: View>: View {
    let title: LocalizedStringResource
    let initialRowID: String
    var focusedHelp: (String) -> ViewCustomizationHelp? = { _ in nil }
    var pinsFocusedHelp = true
    var inlineHelpAfterSection: Int?
    var sectionSpacing: CGFloat = SettingsRowMetrics.formRowSpacing
    var hasGroupedContent = false
    @ViewBuilder var content: () -> Content
    @SettingsPageDismiss private var dismiss
    @Environment(SettingsDetailNavigation.self) private var detailNavigation: SettingsDetailNavigation?
    @Environment(SettingsSearchRequest.self) private var searchRequest: SettingsSearchRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedRow: String?
    @State private var hasEnteredList = false
    @State private var topFadeStrength: CGFloat = 0
    @Namespace private var focusScope

    var body: some View {
        SettingsPageList {
            content()
        }
        .navigationTitle(Text(title))
    }
}

#if os(iOS)
struct ViewCustomizationMenu<Selection: Hashable, Options: View>: View {
    let id: String
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    var detail: LocalizedStringResource? = nil
    @Binding var selection: Selection
    @ViewBuilder var options: () -> Options

    var body: some View {
        HStack {
            SettingsControlMenu {
                Picker(selection: $selection) {
                    options()
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                ViewCustomizationMenuLabel(id: id, title: title) {
                    SettingsMenuValue(Text(value))
                }
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(value))
            .accessibilityHint(Text(detail ?? "Select to change."))
            .accessibilityIdentifier(id)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ViewCustomizationMenuLabel<Control: View>: View {
    let id: String
    let title: LocalizedStringResource
    @ViewBuilder var control: () -> Control
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLabel
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Text(title)
                            .accessibilityIdentifier("\(id)-title")
                            .fixedSize()
                        Spacer(minLength: 8)
                        control().fixedSize()
                    }
                    stackedLabel
                }
            }
        }
        .font(.body)
        .foregroundStyle(palette.primaryText)
        .multilineTextAlignment(.leading)
    }

    private var stackedLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .accessibilityIdentifier("\(id)-title")
            control()
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

struct ViewCustomizationRow: View {
    let id: String
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    var detail: LocalizedStringResource? = nil
    let cycle: () -> Void

    var body: some View {
        Button(action: cycle) {
            ViewCustomizationRowLabel(title: title, value: value)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(detail ?? "Select to change."))
        .accessibilityIdentifier(id)
        .modifier(ViewCustomizationRowFocus(id: id))
    }
}

private struct ViewCustomizationFocusKey: EnvironmentKey {
    static let defaultValue: FocusState<String?>.Binding? = nil
}

private extension EnvironmentValues {
    var viewCustomizationFocus: FocusState<String?>.Binding? {
        get { self[ViewCustomizationFocusKey.self] }
        set { self[ViewCustomizationFocusKey.self] = newValue }
    }
}

struct ViewCustomizationRowFocus: ViewModifier {
    let id: String
    @Environment(\.viewCustomizationFocus) private var focus

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus, equals: id)
        } else {
            content
        }
    }
}

private struct ViewCustomizationRowLabel: View {
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLabel
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        titleText.fixedSize()
                        Spacer(minLength: 12)
                        valueText.fixedSize()
                    }
                    stackedLabel
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var stackedLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleText
            valueText
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(title)
            .font(.body.weight(.medium))
            .multilineTextAlignment(.leading)
    }

    private var valueText: some View {
        Text(value)
            .multilineTextAlignment(.leading)
            .settingsRowSecondary()
    }
}

#endif
