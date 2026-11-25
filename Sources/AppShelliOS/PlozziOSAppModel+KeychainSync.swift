#if os(iOS)
import Foundation
import CoreModels
import CoreNetworking
import FeatureAuthCore
import FeatureSyncSetup
import CoreSecureStore

// MARK: - Legacy mobile publication and pairing
//
// New server restoration uses ProviderCredentialSync on both platforms. Keep
// Keychain publication for older mobile clients.
// Generated SSH private keys remain device-local.
extension PlozziOSAppModel {

    nonisolated private static let portableCredService = "com.plozz.portablecred.v1"

    /// A synchronizable (iCloud-Keychain-backed) store for portable credentials.
    private var portableCredStore: KeychainStore {
        KeychainStore(service: Self.portableCredService, userIndependent: false, synchronizable: true)
    }

    static func makePortableCredentialPublisher() -> SerializedCredentialPublisher {
        let store = KeychainStore(service: portableCredService, userIndependent: false, synchronizable: true)
        return SerializedCredentialPublisher(
            store: store, clearStore: { try store.removeAll() },
            isEnabled: { SyncSetupFeatureFlag().allowsAutomaticSync },
            onFailure: { operation, error in
                if case KeychainError.unexpectedStatus(let status) = error {
                    PlozzLog.auth.error("KeychainSync: \(operation.rawValue) failed, status=\(status)")
                } else {
                    PlozzLog.auth.error("KeychainSync: \(operation.rawValue) failed")
                }
            }
        )
    }

    /// This device's transferable credentials (bearer tokens + share envelopes). Also
    /// used by the pairing `secretsProvider`, so both paths agree on what's shareable.
    func currentSecretsBundle() -> SyncSecretsBundle {
        Self.buildSecretsBundle(accounts: accountsProviders.accounts, accountStore: accountStore)
    }

    /// Pure builder shared by the instance method above AND the pairing service's
    /// `secretsProvider` (which runs during init, before `self` is usable, so it can
    /// only capture already-initialized properties — not call an instance method).
    nonisolated static func buildSecretsBundle(accounts: [Account], accountStore: AccountPersisting) -> SyncSecretsBundle {
        var accts: [AccountSecret] = []
        var shares: [ShareSecret] = []
        for account in accounts {
            guard account.server.provider.permitsCredentialTransfer else { continue }
            if account.server.provider == .mediaShare {
                if let envelope = try? accountStore.mediaShareCredential(for: account.id) {
                    if case .generatedKey = envelope.authentication {
                        // The SSH key lives in THIS device's Keychain and never
                        // travels; the paired device re-adds this share (own key).
                        PlozzLog.auth.info("KeychainSync: skipping generated-key share \(account.id)")
                    } else if let encoded = try? MediaShareCredentialCodec.encode(envelope) {
                        shares.append(ShareSecret(accountID: account.id, credentialEnvelope: encoded))
                    }
                }
                continue
            }
            guard let token = accountStore.token(for: account.id) else { continue }
            accts.append(AccountSecret(
                accountID: account.id, provider: account.server.provider, token: token,
                deviceID: account.deviceID,
                trustedOrigin: LocalAuthorization.origin(of: account.server.baseURL)))
        }
        return SyncSecretsBundle(accounts: accts, shares: shares)
    }

    /// WRITE: publish this device's transferable credentials to the iCloud-Keychain-
    /// synced store so the user's OTHER iPhone/iPad auto-connect with zero taps —
    /// bearer tokens (Plex/Jellyfin/Emby) AND media-share credential envelopes
    /// (NFS/SMB/WebDAV). Gated on sync being enabled (the household consent decision).
    ///
    /// SFTP shares with a device-local generated SSH key are intentionally NOT
    /// published (the private key must never leave the device) — `buildSecretsBundle`
    /// already omits those, so they still require a manual re-add on each device.
    func publishPortableCredentials() {
        guard !isOfflineMode, applicationIsActive else { return }
        guard SyncSetupFeatureFlag().allowsAutomaticSync else { return }
        let captured = Self.buildSecretsBundle(accounts: accountsProviders.accounts, accountStore: accountStore)
        let bundle = SyncSecretsBundle(
            accounts: captured.accounts.filter {
                providerCredentialSync.mayPublish(accountID: $0.accountID, credential: $0.token)
            },
            shares: captured.shares.filter {
                providerCredentialSync.mayPublish(accountID: $0.accountID, credential: $0.credentialEnvelope)
            })
        portableCredentialPublisher.publish {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var records: [String: String] = [:]
            for secret in bundle.accounts {
                records[secret.accountID] = String(decoding: try encoder.encode(secret), as: UTF8.self)
            }
            for share in bundle.shares {
                records[share.accountID] = String(decoding: try encoder.encode(share), as: UTF8.self)
            }
            return records
        }
    }

    /// Remove a portable credential (an account was signed out on this device), so it
    /// stops auto-connecting the user's other devices.
    func removePortableCredential(_ accountID: String) {
        portableCredentialPublisher.removeValue(for: accountID)
    }

    /// Debug: purge EVERY synced iCloud-Keychain login for the whole household —
    /// including credentials synced in from other devices whose account IDs this
    /// device never held locally. Because the store is synchronizable, the deletion
    /// propagates through iCloud Keychain to the household's other devices, so no
    /// device silently auto-reconnects afterward. Used by "Erase Everything From
    /// iCloud" to reach a true clean slate for cold-start testing.
    func removeAllPortableCredentials() async throws {
        try await withCheckedThrowingContinuation { continuation in
            portableCredentialPublisher.removeAll { continuation.resume(with: $0) }
        }
    }

    /// Only the shared, authority-checked path can suppress manual server setup.
    func hasPortableCredential(_ accountID: String) -> Bool {
        providerCredentialSync.hasCredential(for: accountID)
    }

    /// Both shells restore servers through the same identity and consent gates.
    func autoConnectFromSyncedCredentials() {
        guard !isOfflineMode else { return }
        guard SyncSetupFeatureFlag().allowsAutomaticSync else { return }
        providerCredentialSync.reconcile()
    }
}
#endif
