#if os(iOS)
import SwiftUI

/// The shared search field for iOS page content.
///
/// The Search tab and the compact Settings shell both need a persistent field
/// below a navigation title. Keeping the field in content (rather than in the
/// navigation-bar search drawer) is what lets those pages keep the native large
/// title on iOS 26 and later.
public struct PlozzSearchField: View {
    @Binding private var text: String
    private let prompt: LocalizedStringResource
    private let label: LocalizedStringResource?
    private let focus: FocusState<Bool>.Binding
    @Environment(\.themePalette) private var palette

    public init(
        text: Binding<String>,
        prompt: LocalizedStringResource = "Search",
        focus: FocusState<Bool>.Binding,
        accessibilityLabel: LocalizedStringResource? = nil
    ) {
        _text = text
        self.prompt = prompt
        self.label = accessibilityLabel
        self.focus = focus
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .plozzForeground(.secondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(prompt)) {
                Text(prompt)
            }
            .focused(focus)
            .textFieldStyle(.plain)
            .foregroundStyle(palette.primaryText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .accessibilityLabel(Text(label ?? prompt))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .plozzForeground(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background {
            Capsule(style: .continuous)
                .fill(palette.fill)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(palette.separator, lineWidth: 1)
        }
        .contentShape(Capsule())
        .onTapGesture { focus.wrappedValue = true }
    }
}
#endif
