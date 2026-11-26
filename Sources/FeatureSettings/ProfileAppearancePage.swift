#if canImport(SwiftUI)
import CoreModels
import CoreUI
import FeatureProfiles
import SwiftUI

/// The profile's own name, avatar and colour, as a pushed settings page.
///
/// Exists so a profile can change how it looks without going through the
/// profile-management page; choosing an avatar and name is the bulk of what
/// editing a profile means.
struct ProfileAppearancePage: View {
    let context: SettingsContext
    let profileID: String

    @SettingsPageDismiss private var dismiss

    private var profile: Profile? {
        context.profiles.first(where: { $0.id == profileID })
    }

    var body: some View {
        content
            .onChange(of: profile == nil) { _, gone in
                if gone { dismiss() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let profile {
            ProfileEditorView(
                editingProfile: profile,
                // Deleting a profile lives on the profile page, not here.
                canDelete: false,
                photoSourceAccounts: context.accounts,
                plexHomeUsersFetcher: context.plexHomeUsersFetcher,
                onSave: { draft in
                    context.onSaveProfile(draft)
                    dismiss()
                },
                onLiveChange: { context.onUpdateProfileCosmetics($0) },
                ownsFullScreen: false,
                onCancel: { dismiss() }
            )
            // Identity is the PROFILE, not this view's position in the tree.
            //
            // `context.profiles` is recency-ordered and recomputed, so every
            // live cosmetic edit can hand this page a reordered array. Without a
            // stable id the editor could be treated as a new view, reset its
            // `@State` from the freshly-saved profile, and see that as another
            // edit — which writes again. That loop saturates the main thread and
            // presents as a frozen screen, not a crash.
            .id(profileID)
        }
        // This page can't delete (it is cosmetics only), but a sync applying a
        // remote deletion while it is open would leave it rendering nothing at
        // all — a page about something that no longer exists should leave.
        //
        // On a CHANGE, never on first appearance. `onAppear { dismiss() }` fires
        // during the push itself if the lookup is momentarily empty, and
        // dismissing a screen mid-push wedges the navigation stack.
        else {
            Color.clear
        }
    }
}
#endif
