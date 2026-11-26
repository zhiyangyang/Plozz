import Foundation
import CoreModels
import CoreNetworking
import CoreUI
import FeatureAuthCore
import MediaTransportCore
import MetadataKit
import ProviderShare

final class MetadataEnrichmentConfigCache: @unchecked Sendable {
    private let baseline: MetadataEnrichmentConfig
    private let settingsStore: any MetadataProviderSettingsStoring
    private let center: NotificationCenter
    private let lock = NSLock()
    private var cached: MetadataEnrichmentConfig
    private var observer: NSObjectProtocol?

    init(
        baseline: MetadataEnrichmentConfig,
        settingsStore: any MetadataProviderSettingsStoring,
        center: NotificationCenter = .default
    ) {
        self.baseline = baseline
        self.settingsStore = settingsStore
        self.center = center
        self.cached = baseline.merged(withUserOverrides: settingsStore.load())
        self.observer = center.addObserver(
            forName: .metadataProviderSettingsDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }

    func value() -> MetadataEnrichmentConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    private func reload() {
        let updated = baseline.merged(withUserOverrides: settingsStore.load())
        lock.lock()
        cached = updated
        lock.unlock()
    }
}

/// The atomic, app-wide ownership bundle for one media-share runtime
/// generation. It ties together the single share catalog coordinator used by
/// both catalog providers and playback leases, the transport composition
/// (adapters + resolver registry), and the network-file resolver — so no caller
/// can pair a coordinator from one generation with a resolver/registry from
/// another (the split-brain E3 targets).
///
/// `AppState` owns exactly one of these and forwards every media-share concern
/// (provider registration, scan reporter wiring, playback lease, credential
/// retirement, account invalidation, preferred-account priority) to it, rather
/// than storing the pieces independently. Tests inject one complete fake runtime
/// instead of assembling registry A + resolver B + coordinator C by hand.
public protocol MediaShareRuntime: Sendable {
    /// The network-file resolver used for direct-file playback of share media.
    var networkFileResolver: any MediaTransportNetworkFileResolving { get }

    /// Registers the `.mediaShare` provider factory into the supplied registry,
    /// wiring each resolved provider to this runtime's coordinator, transport
    /// composition, and network-file resolver.
    func registerProvider(
        into registry: ProviderRegistry,
        durableLocalStateStore: DurableLocalStateStore?
    )

    /// Wires the scan/enrich progress reporter into the coordinator's scanners
    /// and enrichers.
    func configure(reporter: ShareScanReporter) async

    /// Invalidates all cached catalog/scan/playback state for one account key
    /// (used when the account is removed).
    func invalidate(accountKey: String) async

    /// Gives every registered share a chance to notice new files, without
    /// disturbing anything on screen. Default no-op so conformers that manage no
    /// shares (tests, previews) need not implement it.
    func pollForChanges() async

    /// Allows foreground-only scan/enrichment work to run. Passing false closes
    /// local persistence admission before returning, then lets cancellation-
    /// insensitive transport teardown drain independently. A newer true revision
    /// returns without awaiting that teardown: the scanner's actor-owned frontier
    /// snapshot is flushed first, local reads resume promptly, and only replacement
    /// scan transport waits for exact old ownership to drain.
    func setBackgroundWorkAllowed(_ allowed: Bool, revision: UInt64) async

    /// Retires the transport sessions bound to one account's credential
    /// revision (used on credential rotation and account removal).
    func retire(accountID: String, credentialRevision: CredentialRevision) async

    /// Updates the active profile's preferred media-share account keys so their
    /// passive backlog drains before work retained for other profiles.
    func setPreferredAccountKeys(_ accountKeys: Set<String>, revision: UInt64) async

    /// A hard admission gate for automatic scans and metadata, independent of
    /// cache priority. Explicit one-off requests retain their own intent.
    func setAutomaticWorkScope(_ scope: MediaShareWorkScope, revision: UInt64) async

    /// A point-in-time snapshot of the metadata enrichment subsystem for the Step 6
    /// Settings "Diagnostics" section (per-source counts, cache bytes, breaker state,
    /// scan/queue status). Default: an empty snapshot (test fakes need not implement).
    func metadataDiagnosticsSnapshot() async -> MetadataEnrichmentDiagnosticsSnapshot

    /// Applies the user's cache budgets to the metadata + derived-artwork caches,
    /// evicting immediately (Step 6). Default: no-op.
    func applyCacheBudgets(_ settings: CacheBudgetSettings) async

    /// Clears the resolved-URL metadata cache and the derived-artwork cache
    /// (Step 6 "Clear cache now"). Default: no-op.
    func clearMetadataCaches() async

}

public extension MediaShareRuntime {
    func metadataDiagnosticsSnapshot() async -> MetadataEnrichmentDiagnosticsSnapshot {
        MetadataEnrichmentDiagnosticsSnapshot()
    }
    func applyCacheBudgets(_ settings: CacheBudgetSettings) async {}
    func clearMetadataCaches() async {}

    /// Default: nothing to poll.
    func pollForChanges() async {}
    func setBackgroundWorkAllowed(_ allowed: Bool, revision: UInt64) async {}
    func setAutomaticWorkScope(_ scope: MediaShareWorkScope, revision: UInt64) async {}
}

/// The single production `MediaShareRuntime`. Construct it only through
/// ``make(accountStore:)`` — that is the one default construction path the
/// Batch 11 gate requires.
public final class DefaultMediaShareRuntime: MediaShareRuntime {
    private let coordinator: ShareCatalogCoordinator
    private let composition: MediaShareTransportComposition
    private let artworkCacheLifecycle: any ShareLocalArtworkCacheLifecycle
    public let networkFileResolver: any MediaTransportNetworkFileResolving
    private let streamProber: (any NetworkFileStreamProbing)?
    private init(
        coordinator: ShareCatalogCoordinator,
        composition: MediaShareTransportComposition,
        artworkCacheLifecycle: any ShareLocalArtworkCacheLifecycle,
        networkFileResolver: any MediaTransportNetworkFileResolving,
        streamProber: (any NetworkFileStreamProbing)?
    ) {
        self.coordinator = coordinator
        self.composition = composition
        self.artworkCacheLifecycle = artworkCacheLifecycle
        self.networkFileResolver = networkFileResolver
        self.streamProber = streamProber
    }

    /// The one default construction path: a fresh coordinator, the media-share
    /// transport composition, and a network-file resolver whose playback lease
    /// comes from that same coordinator and whose session key comes from that
    /// same composition. Nothing outside this method assembles the three pieces.
    public static func make(
        accountStore: any AccountPersisting,
        artworkCacheLifecycle: any ShareLocalArtworkCacheLifecycle =
            NoopShareLocalArtworkCacheLifecycle(),
        sourcePreparer: (@Sendable (
            NetworkFileLocator, Double, any MediaTransportByteSource
        ) async throws -> Void)? = nil,
        streamProberFactory: @Sendable (
            any MediaTransportNetworkFileResolving
        ) -> (any NetworkFileStreamProbing)? = { _ in nil }
    ) -> DefaultMediaShareRuntime {
        let coordinator = ShareCatalogCoordinator(
            artworkCacheLifecycle: artworkCacheLifecycle,
            initialWorkScope: .paused
        )
        // Apply persisted cache budgets to the live caches at startup (eviction runs
        // immediately if a budget was lowered since last launch).
        let cacheBudgets = CacheBudgetSettingsStore().load()
        Task {
            await MetadataDiskCache.shared.setMaxBytes(cacheBudgets.metadataCacheBytes)
            await ArtworkImageCache.shared.setDerivedArtworkCacheByteCap(cacheBudgets.artworkCacheBytes)
        }
        let composition = MediaShareTransportComposition.make(accountStore: accountStore)
        let resolver = MediaTransportNetworkFileResolver(
            registry: composition.resolverRegistry,
            playbackLeaseProvider: { locator in
                try await coordinator.acquirePlayback(accountKey: locator.accountID)
            },
            sourcePreparer: sourcePreparer
        ) { locator in
            guard locator.sourceID == locator.accountID,
                  let account = accountStore.loadAccounts().first(where: {
                      $0.id == locator.accountID
                  }),
                  account.server.provider == .mediaShare,
                  account.credentialRevision == locator.credentialRevision else {
                throw MediaTransportError.authentication(reason: "inactive network-file identity")
            }
            return try MediaShareTransportComposition.mediaShareSessionKey(
                for: account,
                role: .playback,
                accountStore: accountStore
            )
        }
        return DefaultMediaShareRuntime(
            coordinator: coordinator,
            composition: composition,
            artworkCacheLifecycle: artworkCacheLifecycle,
            networkFileResolver: resolver,
            streamProber: streamProberFactory(resolver)
        )
    }

    public var artworkNetworkFileService: ArtworkNetworkFileService {
        ArtworkNetworkFileService(
            loader: MediaShareArtworkLoader(
                // Artwork is a small display-time JPEG read. Taking a PLAYBACK
                // lease for it drained the running library scan — and artwork
                // loads continuously while browsing, so the scan was cancelled
                // over and over and never completed. That, not the scan interval,
                // was the battery drain.
                resolver: networkFileResolver.withoutPlaybackAdmission(),
                catalogCoordinator: coordinator
            ),
            failureReporter: self
        )
    }

    public func registerProvider(
        into registry: ProviderRegistry,
        durableLocalStateStore: DurableLocalStateStore?
    ) {
        let composition = self.composition
        let coordinator = self.coordinator
        let streamProber = self.streamProber
        registry.register(.mediaShare) { context in
            guard let localMediaContext = context.localMediaContext else {
                throw ProviderResolutionError.localMediaContextRequired(.mediaShare)
            }
            let sessionFactory = try composition.makeSessionFactory(
                server: context.session.server,
                accountID: context.accountID,
                credentialRevision: context.credentialRevision
            )
            return ShareProvider(
                session: context.session,
                localMediaContext: localMediaContext,
                credentialRevision: context.credentialRevision,
                sessionFactory: sessionFactory,
                catalogCoordinator: coordinator,
                durableLocalStateStore: durableLocalStateStore,
                streamProber: streamProber
            )
        }
    }

    public func configure(reporter: ShareScanReporter) async {
        await coordinator.configure(reporter: reporter)
    }

    public func invalidate(accountKey: String) async {
        await coordinator.invalidate(accountKey: accountKey)
        await artworkCacheLifecycle.purge(accountID: accountKey)
    }

    public func pollForChanges() async {
        await coordinator.pollForChanges()
    }

    public func setBackgroundWorkAllowed(_ allowed: Bool, revision: UInt64) async {
        await coordinator.setBackgroundWorkAllowed(allowed, revision: revision)
    }

    public func retire(accountID: String, credentialRevision: CredentialRevision) async {
        await composition.resolverRegistry.retire(
            accountID: accountID,
            credentialRevision: credentialRevision
        )
        await artworkCacheLifecycle.purge(
            accountID: accountID,
            credentialRevision: credentialRevision
        )
    }

    public func setPreferredAccountKeys(_ accountKeys: Set<String>, revision: UInt64) async {
        await coordinator.setPreferredAccountKeys(accountKeys, revision: revision)
    }

    public func setAutomaticWorkScope(_ scope: MediaShareWorkScope, revision: UInt64) async {
        await coordinator.setAutomaticWorkScope(scope, revision: revision)
    }

    public func metadataDiagnosticsSnapshot() async -> MetadataEnrichmentDiagnosticsSnapshot {
        // Point-in-time, cross-actor: capture the timestamp first, then gather each
        // field from its own actor. The parts may be a few ms apart by design.
        let capturedAt = Date()
        let counts = await coordinator.metadataCountPerSource()
        let work = await coordinator.metadataWorkStatus()
        let artworkBytes = await ArtworkImageCache.shared.derivedArtworkCacheByteSize()
        let metadataBytes = await MetadataDiskCache.shared.currentByteSize()
        return MetadataEnrichmentDiagnosticsSnapshot(
            capturedAt: capturedAt,
            metadataCountPerSource: counts,
            artworkCacheBytes: artworkBytes,
            metadataCacheBytes: metadataBytes,
            work: work
        )
    }

    public func applyCacheBudgets(_ settings: CacheBudgetSettings) async {
        await MetadataDiskCache.shared.setMaxBytes(settings.metadataCacheBytes)
        await ArtworkImageCache.shared.setDerivedArtworkCacheByteCap(settings.artworkCacheBytes)
    }

    public func clearMetadataCaches() async {
        await MetadataDiskCache.shared.clear()
        await ArtworkImageCache.shared.clearDerivedArtworkCache()
    }

}

extension DefaultMediaShareRuntime: ArtworkNetworkFileFailureReporting {
    public func reportArtworkFailure(
        _ failure: ArtworkNetworkFileFailure,
        for reference: NetworkArtworkReference
    ) async {
        switch failure {
        case .empty, .tooLarge, .malformed, .unsupported, .unsafeDimensions:
            await coordinator.rejectArtwork(
                accountKey: reference.accountID,
                reference: reference
            )
        case .unavailable, .cancelled:
            break
        }
    }
}
