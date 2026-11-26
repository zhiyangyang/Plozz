#if os(iOS)
import CoreModels
import CoreUI
import FeatureProfiles
import SwiftUI

/// Settings → Everyone → Profiles → one profile on iPhone/iPad.
struct PlozziOSProfileSettingsView: View {
    let appModel: PlozziOSAppModel
    let profileID: String

    @State private var route: Route?
    @Environment(\.dismiss) private var dismiss

    private var profile: Profile? {
        appModel.profiles.profiles.first(where: { $0.id == profileID })
    }

    private var canDelete: Bool {
        profile != nil && appModel.profiles.profiles.count > 1
    }

    var body: some View {
        List {
            if let profile {
                ProfileActionsList(
                    profile: profile,
                    groupsActions: true,
                    automaticSignIn: AutomaticSignInSettings(
                        isEnabled: Binding(
                            get: { appModel.plexHomeUsers.automaticallySignIn },
                            set: { appModel.setAutomaticallySignIn($0) }
                        ),
                        error: appModel.plexHomeUsers.automaticSignInError
                    ),
                    onEditAppearance: { route = .appearance },
                    onDelete: canDelete ? { appModel.removeProfile(profileID) } : nil
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .settingsPageSurface()
        .navigationTitle(Text(verbatim: profile?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            destination(for: route)
        }
        .onChange(of: profile == nil) { _, profileIsGone in
            if profileIsGone { dismiss() }
        }
    }

    private enum Route: Hashable, Identifiable {
        case appearance
        var id: Self { self }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .appearance:
            PlozziOSProfileAppearancePage(appModel: appModel, profileID: profileID)
        }
    }
}
#endif
