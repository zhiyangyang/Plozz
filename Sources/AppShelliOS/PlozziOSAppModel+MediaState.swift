#if os(iOS)
import Foundation
import AppRuntime
import CoreModels
import CoreNetworking

// MARK: - Local durable media state
//
// The alias ledger and universal watchlist are device-local stores. They used to
// used to live in the cross-device sync extension; keep their local preparation
// here now that sync is gone.
extension PlozziOSAppModel {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func writableStateDirectory() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func mediaAliasStorageDirectory() -> URL? {
        writableStateDirectory()?
            .appendingPathComponent("PlozzMediaState", isDirectory: true)
            .appendingPathComponent("AliasLedger", isDirectory: true)
    }

    func prepareMediaAliasLedger() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.mediaAliasLedger.loadProfiles(
                    self.profiles.profiles.map(\.id)
                )
                try await self.mediaAliasLedger.activate(
                    profileID: self.profiles.activeProfileID
                )
                await self.prepareUniversalWatchlist()
            } catch {
                PlozzLog.app.error(
                    "Media aliases: local ledger preparation failed: \(error.localizedDescription)"
                )
            }
            self.armMediaAliasObservation()
        }
    }

    /// Profile roster/selection changes require activation and one native import.
    func armMediaAliasObservation() {
        withObservationTracking {
            _ = profiles.profiles
            _ = profiles.activeProfileID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.mediaAliasLedger.loadProfiles(
                        self.profiles.profiles.map(\.id)
                    )
                    try await self.mediaAliasLedger.activate(
                        profileID: self.profiles.activeProfileID
                    )
                    await self.prepareUniversalWatchlist()
                } catch {
                    PlozzLog.app.error(
                        "Media aliases: profile activation failed: \(error.localizedDescription)"
                    )
                }
                self.armMediaAliasObservation()
            }
        }
    }

    func removeMediaAliases(forProfileID profileID: String) {
        removeUniversalWatchlist(forProfileID: profileID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.mediaAliasLedger.removeProfile(profileID)
            } catch {
                PlozzLog.app.error(
                    "Media aliases: profile removal failed: \(error.localizedDescription)"
                )
            }
        }
    }
}
#endif
