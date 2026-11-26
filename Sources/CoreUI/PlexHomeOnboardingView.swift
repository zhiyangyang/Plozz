#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// Picks which Plex Home user this single profile watches as.
public struct PlexHomeOnboardingView: View {
    private let users: [PlexHomeUser]
    private let onSelect: (PlexHomeUser) -> Void

    public init(
        users: [PlexHomeUser],
        onSelect: @escaping (PlexHomeUser) -> Void
    ) {
        self.users = users
        self.onSelect = onSelect
    }

    public var body: some View {
        PlexHomeOnboardingContent(users: users, onSelect: onSelect)
    }
}

struct PlexHomeOnboardingContent: View {
    let users: [PlexHomeUser]
    let onSelect: (PlexHomeUser) -> Void
    @FocusState private var focused: String?

    private var orderedUsers: [PlexHomeUser] {
        users.sorted {
            if $0.isAdmin != $1.isAdmin { return $0.isAdmin }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingHeader(Text("Choose your Plex user"))
                VStack(spacing: 14) {
                    ForEach(orderedUsers) { user in
                        Button {
                            onSelect(user)
                        } label: {
                            PlexHomeUserRow(user: user, showsOwnerBadge: user.isAdmin)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .focused($focused, equals: user.id)
                        .accessibilityIdentifier("plex-home-user-\(user.id)")
                    }
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .defaultScrollAnchor(.top)
        .task { focused = orderedUsers.first?.id }
    }
}
#endif
