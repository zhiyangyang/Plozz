#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// The things you can do to a profile: change how it looks, or delete it.
///
/// Shared by the picker's Edit sheet and individual profile settings so the two
/// surfaces cannot drift.
public struct ProfileActionsList: View {
    private let profile: Profile
    private let groupsActions: Bool
    private let automaticSignIn: AutomaticSignInSettings?
    private let onEditAppearance: () -> Void
    private let onDelete: (() -> Void)?

    public init(
        profile: Profile,
        groupsActions: Bool = false,
        automaticSignIn: AutomaticSignInSettings? = nil,
        onEditAppearance: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.groupsActions = groupsActions
        self.automaticSignIn = automaticSignIn
        self.onEditAppearance = onEditAppearance
        self.onDelete = onDelete
    }

    @State private var confirmDelete = false

    public var body: some View {
        VStack(spacing: groupsActions ? 16 : 14) {
            ProfileActionSection(grouped: groupsActions) {
                actionRow(
                    icon: "paintpalette",
                    title: "Appearance",
                    subtitle: "Name, avatar, and color",
                    action: onEditAppearance
                )
                .accessibilityIdentifier("profile.appearance")
            }

            if let automaticSignIn {
                ProfileActionSection(grouped: groupsActions) {
                    AutomaticSignInToggle(settings: automaticSignIn)
                        .toggleStyle(SettingsSwitchToggleStyle(flushLeading: false))
                }
                AutomaticSignInErrorMessage(settings: automaticSignIn)
                    .font(.footnote)
            }
            if onDelete != nil {
                ProfileActionSection(grouped: groupsActions) {
                    deleteButton
                        .labelStyle(.titleAndIcon)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("profile.delete")
                }
            }
        }
        .confirmationDialog("Delete this profile?", isPresented: $confirmDelete) {
            Button("Delete Profile", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting removes this profile's preferences (theme, playback, subtitles, spoilers) and which servers it includes. Signed-in server accounts stay shared.")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            if groupsActions {
                LabeledContent { EmptyView() } label: { deleteLabel }
            } else {
                deleteLabel
            }
        }
    }

    private var deleteLabel: some View {
        Label {
            Text("Delete Profile")
        } icon: {
            Image(systemName: "trash")
                .frame(width: groupsActions ? SettingsRowMetrics.iconColumnWidth : nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        action: @escaping () -> Void
    ) -> some View {
        #if os(iOS)
        if groupsActions {
            Button(action: action) {
                SettingsDisclosureLabel {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .fixedSize(horizontal: false, vertical: true)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.footnote)
                                    .settingsRowSecondary()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } icon: {
                        Image(systemName: icon)
                            .frame(width: SettingsRowMetrics.iconColumnWidth)
                            .settingsRowIcon()
                    }
                    .labelStyle(.titleAndIcon)
                } value: {
                    EmptyView()
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            focusedActionRow(icon: icon, title: title, subtitle: subtitle, action: action)
        }
        #else
        focusedActionRow(icon: icon, title: title, subtitle: subtitle, action: action)
        #endif
    }

    private func focusedActionRow(
        icon: String,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsRowLabel(icon: icon, title: title) {
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .settingsRowSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            } trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .settingsRowSecondary()
            }
        }
        .buttonStyle(SettingsFocusButtonStyle())
    }
}

private struct ProfileActionSection<Content: View>: View {
    let grouped: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if grouped {
            SettingsSectionGroup { content() } footer: { EmptyView() }
        } else {
            VStack(spacing: 14) { content() }
        }
    }
}
#endif
