import CoreModels
import Foundation
import Observation

@MainActor
@Observable
public final class MediaAliasLedgerModel {
    private struct DeletedProfilesState: Codable {
        static let currentVersion = 1

        let version: Int
        let profileIDs: [String]
    }

    public private(set) var snapshotsByProfile: [String: MediaAliasSnapshot] = [:]
    public private(set) var activeProfileID: String?
    public private(set) var deletionStateRecoveryOccurred = false

    private let legacyDurableStore: DurableLocalStateStore?
    private let storageDirectory: URL?
    private var ledgersByProfile: [String: MediaAliasLedger] = [:]
    private var loadingLedgersByProfile: [
        String: Task<MediaAliasLedger, Error>
    ] = [:]
    private var removedProfileIDs: Set<String> = []
    private var pendingPurgeProfileIDs: Set<String> = []
    @ObservationIgnored private var mutationGeneration: UInt64 = 0

    public init(
        durableStore: DurableLocalStateStore? = nil,
        storageDirectory: URL? = nil
    ) {
        legacyDurableStore = durableStore
        let resolvedStorageDirectory: URL?
        if let storageDirectory {
            resolvedStorageDirectory = storageDirectory
        } else if durableStore != nil {
            resolvedStorageDirectory = Self.defaultStorageDirectory()
        } else {
            resolvedStorageDirectory = nil
        }
        self.storageDirectory = resolvedStorageDirectory

        guard let resolvedStorageDirectory else { return }
        let deletionURL = Self.deletionStateURL(in: resolvedStorageDirectory)
        guard FileManager.default.fileExists(atPath: deletionURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: deletionURL)
            removedProfileIDs = try Self.deletedProfileIDs(from: data)
            pendingPurgeProfileIDs = removedProfileIDs
        } catch {
            deletionStateRecoveryOccurred = true
            Self.quarantineCorruptDeletionState(at: deletionURL)
        }
    }

    public var activeSnapshot: MediaAliasSnapshot {
        guard let activeProfileID else { return .empty }
        return snapshotsByProfile[activeProfileID] ?? .empty
    }

    public func activate(profileID: String) async throws {
        try reviveProfiles([profileID])
        let ledger = try await ledger(for: profileID)
        publish(await ledger.snapshot(), profileID: profileID)
        if activeProfileID != profileID {
            activeProfileID = profileID
        }
    }

    public func loadProfiles(_ profileIDs: [String]) async throws {
        let profileIDs = Set(profileIDs)
        try reviveProfiles(profileIDs)
        for profileID in profileIDs.sorted() {
            let ledger = try await ledger(for: profileID)
            publish(await ledger.snapshot(), profileID: profileID)
        }
    }

    public func lookup(
        profileID: String,
        evidence: MediaAliasEvidence,
        preferredAliasID: MediaAliasID? = nil
    ) async throws -> MediaAliasID? {
        try ensureDeletionStateAvailable()
        guard !removedProfileIDs.contains(profileID) else { return nil }
        let ledger = try await ledger(for: profileID)
        return await ledger.lookup(
            evidence: evidence,
            preferredAliasID: preferredAliasID
        )
    }

    @discardableResult
    public func resolveOrCreate(
        profileID: String,
        evidence: MediaAliasEvidence,
        preferredAliasID: MediaAliasID? = nil
    ) async throws -> MediaAliasID {
        try reviveProfiles([profileID])
        let ledger = try await ledger(for: profileID)
        let id = try await ledger.resolveOrCreate(
            evidence: evidence,
            preferredAliasID: preferredAliasID
        )
        publish(await ledger.snapshot(), profileID: profileID)
        return id
    }

    public func resolveOrCreateBatch(
        profileID: String,
        requests: [MediaAliasResolutionRequest]
    ) async throws -> [MediaAliasID] {
        guard !requests.isEmpty else { return [] }
        try reviveProfiles([profileID])
        let ledger = try await ledger(for: profileID)
        let ids = try await ledger.resolveOrCreate(requests)
        publish(await ledger.snapshot(), profileID: profileID)
        return ids
    }

    @discardableResult
    public func restoreMissingLegacyAliases(
        profileID: String,
        intents: [WatchlistIntent]
    ) async throws -> Int {
        try ensureDeletionStateAvailable()
        guard !removedProfileIDs.contains(profileID) else {
            throw MediaAliasLedgerError.profileDeleted(profileID)
        }
        let ledger = try await ledger(for: profileID)
        let count = try await ledger.restoreMissingLegacyAliases(from: intents)
        if count > 0 { publish(await ledger.snapshot(), profileID: profileID) }
        return count
    }

    public func enrich(
        profileID: String,
        aliasID: MediaAliasID,
        evidence: MediaAliasEvidence
    ) async throws {
        try ensureDeletionStateAvailable()
        guard !removedProfileIDs.contains(profileID) else {
            throw MediaAliasLedgerError.profileDeleted(profileID)
        }
        let ledger = try await ledger(for: profileID)
        try await ledger.enrich(aliasID: aliasID, with: evidence)
        publish(await ledger.snapshot(), profileID: profileID)
    }

    @discardableResult
    public func clearPresentationArtwork(
        profileID: String,
        aliasIDs: Set<MediaAliasID>
    ) async throws -> Int {
        try ensureDeletionStateAvailable()
        guard !removedProfileIDs.contains(profileID) else {
            throw MediaAliasLedgerError.profileDeleted(profileID)
        }
        let ledger = try await ledger(for: profileID)
        let changed = try await ledger.clearPresentationArtwork(
            aliasIDs: aliasIDs
        )
        publish(await ledger.snapshot(), profileID: profileID)
        return changed
    }

    /// Applies one identity-index publication with one durable write and one
    /// observable snapshot publication, regardless of intent count.
    @discardableResult
    public func enrichBatch(
        profileID: String,
        enrichments: [MediaAliasEnrichment]
    ) async throws -> Int {
        try ensureDeletionStateAvailable()
        guard !removedProfileIDs.contains(profileID) else {
            throw MediaAliasLedgerError.profileDeleted(profileID)
        }
        let ledger = try await ledger(for: profileID)
        let changedCount = try await ledger.enrich(enrichments)
        publish(await ledger.snapshot(), profileID: profileID)
        return changedCount
    }

    private func publish(
        _ snapshot: MediaAliasSnapshot,
        profileID: String
    ) {
        guard snapshotsByProfile[profileID] != snapshot else { return }
        snapshotsByProfile[profileID] = snapshot
        mutationGeneration &+= 1
    }

    @discardableResult
    public func removeProfile(_ profileID: String) async throws {
        try ensureDeletionStateAvailable()
        if removedProfileIDs.insert(profileID).inserted {
            do {
                try persistDeletionState()
            } catch {
                removedProfileIDs.remove(profileID)
                throw error
            }
            mutationGeneration &+= 1
        }
        pendingPurgeProfileIDs.insert(profileID)
        try await purgeProfileStorage(profileID)
        pendingPurgeProfileIDs.remove(profileID)
        ledgersByProfile[profileID] = nil
        snapshotsByProfile[profileID] = nil
        if activeProfileID == profileID {
            activeProfileID = nil
        }
    }

    private func ledger(for profileID: String) async throws -> MediaAliasLedger {
        try ensureDeletionStateAvailable()
        guard !removedProfileIDs.contains(profileID) else {
            throw MediaAliasLedgerError.profileDeleted(profileID)
        }
        if let existing = ledgersByProfile[profileID] {
            return existing
        }
        if let loading = loadingLedgersByProfile[profileID] {
            return try await loading.value
        }
        let store = try makeStore(for: profileID)
        let loading = Task.detached(priority: .userInitiated) {
            try MediaAliasLedger(profileID: profileID, store: store)
        }
        loadingLedgersByProfile[profileID] = loading
        let created: MediaAliasLedger
        do {
            created = try await loading.value
        } catch {
            loadingLedgersByProfile[profileID] = nil
            throw error
        }
        loadingLedgersByProfile[profileID] = nil
        guard !removedProfileIDs.contains(profileID) else {
            try await created.removeForProfileDeletion()
            throw MediaAliasLedgerError.profileDeleted(profileID)
        }
        ledgersByProfile[profileID] = created
        return created
    }

    private func makeStore(for profileID: String) throws -> any MediaAliasStoring {
        if let storageDirectory {
            let legacyStore: (any MediaAliasStoring)?
            if let legacyDurableStore {
                legacyStore = try DurableMediaAliasStore(
                    store: legacyDurableStore,
                    profileID: profileID
                )
            } else {
                legacyStore = nil
            }
            return try AtomicFileMediaAliasStore(
                directoryURL: storageDirectory,
                profileID: profileID,
                legacyStore: legacyStore
            )
        } else if legacyDurableStore != nil {
            throw DurableLocalStateError.storageUnavailable
        } else {
            return InMemoryMediaAliasStore()
        }
    }

    private func purgeProfileStorage(_ profileID: String) async throws {
        if let ledger = ledgersByProfile[profileID] {
            try await ledger.removeForProfileDeletion()
        } else {
            try makeStore(for: profileID).destructiveRemove()
        }
        ledgersByProfile[profileID] = nil
        snapshotsByProfile[profileID] = nil
    }

    private func reviveProfiles(_ profileIDs: Set<String>) throws {
        try ensureDeletionStateAvailable()
        let revived = removedProfileIDs.intersection(profileIDs)
        guard !revived.isEmpty else { return }
        removedProfileIDs.subtract(revived)
        pendingPurgeProfileIDs.subtract(revived)
        do {
            try persistDeletionState()
            mutationGeneration &+= 1
        } catch {
            removedProfileIDs.formUnion(revived)
            pendingPurgeProfileIDs.formUnion(revived)
            throw error
        }
    }

    private func ensureDeletionStateAvailable() throws {
        // Kept as the single gate for future storage-health checks.
    }

    private func persistDeletionState() throws {
        guard let storageDirectory else { return }
        let state = DeletedProfilesState(
            version: DeletedProfilesState.currentVersion,
            profileIDs: removedProfileIDs.sorted()
        )
        let data = try MediaAliasEncodingMetrics.canonicalData(state)
        let url = Self.deletionStateURL(in: storageDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func deletionStateURL(in directory: URL) -> URL {
        directory.appendingPathComponent(
            "deleted-profiles-v1.json",
            isDirectory: false
        )
    }

    private static func deletedProfileIDs(from data: Data) throws -> Set<String> {
        let state = try JSONDecoder().decode(DeletedProfilesState.self, from: data)
        guard state.version >= DeletedProfilesState.currentVersion,
              state.profileIDs.allSatisfy(isValidProfileID) else {
            throw DurableLocalStateError.malformedPayload
        }
        return Set(state.profileIDs)
    }

    private static func isValidProfileID(_ profileID: String) -> Bool {
        !profileID.isEmpty
            && profileID == profileID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    private static func quarantineCorruptDeletionState(at url: URL) {
        let quarantineURL = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).json")
        try? FileManager.default.moveItem(at: url, to: quarantineURL)
    }

    private static func defaultStorageDirectory() -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Plozz", isDirectory: true)
            .appendingPathComponent("MediaAliasLedger", isDirectory: true)
    }
}
