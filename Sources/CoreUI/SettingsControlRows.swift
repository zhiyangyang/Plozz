#if canImport(SwiftUI)
import SwiftUI

/// A control and its supporting copy form one row, including for group separators.
public struct SettingsDescribedControl<Control: View, Description: View>: View {
    private let control: Control
    private let description: Description

    public init(@ViewBuilder control: () -> Control, @ViewBuilder description: () -> Description) {
        self.control = control()
        self.description = description()
    }

    public var body: some View {
        #if os(iOS)
        let descriptionSpacing: CGFloat = 0
        #else
        let descriptionSpacing = SettingsFormMetrics.relatedControlSpacing
        #endif
        VStack(alignment: .leading, spacing: descriptionSpacing) {
            control
                #if os(iOS)
                .frame(minHeight: MobileSettingsMetrics.rowMinHeight - 2 * MobileSettingsMetrics.controlVerticalInset)
                #endif
            description
                .settingsHelperText()
                .fixedSize(horizontal: false, vertical: true)
                #if os(iOS)
                .padding(.bottom, MobileSettingsMetrics.descriptionBottomInset - MobileSettingsMetrics.controlVerticalInset)
                #endif
        }
    }
}

/// Rows sharing a Settings container. Keep each control and its helper in one
/// child view so the separator follows both. Conditional rows retain their IDs.
public struct SettingsControlRows<Content: View>: View {
    private let nonTVSpacing: CGFloat
    private let dividerLeadingInset: CGFloat?
    private let content: Content
    @Environment(\.settingsFormTextInset) private var textInset

    public init(
        nonTVSpacing: CGFloat = SettingsFormMetrics.controlSpacing,
        dividerLeadingInset: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.nonTVSpacing = nonTVSpacing
        self.dividerLeadingInset = dividerLeadingInset
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: nonTVSpacing) {
            content
        }
    }
}
#endif
