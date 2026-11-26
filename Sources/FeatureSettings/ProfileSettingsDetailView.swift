#if canImport(SwiftUI)
import CoreModels
import CoreNetworking
import CoreUI
import FeatureProfiles
import SwiftUI

/// Settings → Everyone → Profiles → one profile.
struct ProfileSettingsDetailView: View {
    let context: SettingsContext
    let profileID: String

    @SettingsPageDismiss private var dismiss

    private var profile: Profile? {
        context.profiles.first(where: { $0.id == profileID })
    }

    private var canDelete: Bool {
        context.profiles.count > 1
    }

    var body: some View {
        let _ = PlozzBodyRate.tick("ProfileSettingsDetailView")
        return pageBody
            .onChange(of: profile == nil) { _, profileIsGone in
                if profileIsGone { dismiss() }
            }
    }

    private var pageBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let profile {
                    SettingsPageHeader(
                        verbatim: profile.name,
                        subtitle: "How this profile looks."
                    )
                    ProfileActionsList(
                        profile: profile,
                        groupsActions: true,
                        automaticSignIn: context.automaticSignIn,
                        onEditAppearance: {
                            context.pushRoute(.profileAppearance(profileID: profileID))
                        },
                        onDelete: canDelete ? { context.onDeleteProfile(profileID) } : nil
                    )
                    .settingsWorkspaceEntry()
                }
            }
            .frame(maxWidth: PlozzTheme.Metrics.settingsContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, PlozzTheme.Metrics.screenPadding)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }
}
#endif
