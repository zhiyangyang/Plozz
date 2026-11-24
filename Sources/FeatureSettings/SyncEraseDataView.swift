import CoreUI
import SwiftUI

/// Review is the first confirmation; only the subsequent native alert can erase.
public struct SyncEraseDataView: View {
    @Environment(\.dismiss) private var dismiss
    private let profileID: String
    private let isAllowed: Bool
    private let status: SyncStatusProvider
    private let erase: () -> Void
    @State private var confirmsErase = false

    public init(
        profileID: String, isAllowed: Bool,
        status: SyncStatusProvider, erase: @escaping () -> Void
    ) {
        self.profileID = profileID
        self.isAllowed = isAllowed
        self.status = status
        self.erase = erase
    }

    public var body: some View {
        let presentation = status.make()
        Group {
            ScrollView {
                reviewContent(isRecovering: presentation.isRecovering)
            }
            .accessibilityIdentifier("cloud-sync-erase-review")
        }
        .alert("Erase sync data?", isPresented: $confirmsErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Data", role: .destructive) {
                guard isAllowed, !status.make().isRecovering else { return }
                erase()
            }
            .accessibilityIdentifier("cloud-sync-erase-final")
        } message: {
            Text("This cannot be undone. iCloud Sync will stay off on this device.")
        }
        .onChange(of: profileID) { _, _ in confirmsErase = false; dismiss() }
        .onChange(of: presentation.accountTag) { _, _ in confirmsErase = false; dismiss() }
        .onChange(of: isAllowed) { _, allowed in
            if !allowed { confirmsErase = false; dismiss() }
        }
        .onChange(of: presentation.isRecovering) { _, recovering in
            if recovering { confirmsErase = false }
        }
    }

    private func reviewContent(isRecovering: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Erase Sync Data")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            SettingsPanel {
                scopeRow("From iCloud", detail: "Profiles, settings, servers, watchlist, Live TV sources, and tracker sign-ins.")
                Divider()
                scopeRow("From this device", detail: "Profiles, servers, watchlist, and Live TV sources. iCloud Sync is turned off.")
                Divider()
                scopeRow("Not affected", detail: "Your media servers and their files.")
            }
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Turn off sync on other devices first so they don't upload their data again.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
                Text("Also removes Plozz's server logins from iCloud Keychain.")
                    .font(.footnote)
                    .plozzForeground(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                Button("Erase Sync Data…", role: .destructive) { confirmsErase = true }
                    .accessibilityIdentifier("cloud-sync-erase-continue")
                    .disabled(!isAllowed || isRecovering)
                Button("Cancel", role: .cancel) { dismiss() }
                    .accessibilityIdentifier("cloud-sync-erase-cancel")
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(32)
    }

    private func scopeRow(_ title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .plozzForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
