#if os(iOS)
import AppRuntime
import CoreModels
import CoreNetworking
import CoreSecureStore
import CoreUI
import EnginePlozzigen
import FeatureAuthCore
import FeatureHomeCore
import FeatureProfiles
import FeatureSettings
import FeatureWatchlistCore
import Foundation
import MediaDownloads
import MediaTransportCore
import MetadataKit
import Observation
import ProviderJellyfin
import ProviderPlex
import ProviderSilo
import ProviderShare
import UIKit

@MainActor
@Observable
final class PlozziOSAppModel {

    /// One scoped detail-snapshot cache per profile/account identity, memoized for
    /// the app's lifetime. The iOS detail pages previously used
    /// `DetailSnapshotCache.ephemeral`, so nothing they loaded was restored: every
    /// visit rebuilt the page instead of painting the cached hero/seasons.
    @ObservationIgnored private let detailCacheFactory = DetailSnapshotCacheFactory()
    @ObservationIgnored private var recentDetailArtwork: (scope: String, replay: ArtworkBitmapReplay)?
    let detailSchedules = PlozziOSDetailScheduleReplay()

    /// The cache for the active profile and its current servers. Switching profile
    /// or Plex Home user switches scope, so one household member never restores
    /// another's cached page.
    var detailSnapshotCache: DetailSnapshotCache {
        detailCacheFactory.cache(for: detailCacheScope)
    }

    var detailArtworkReplay: ArtworkBitmapReplay {
        let scope = detailCacheScope.digest
        if let recentDetailArtwork, recentDetailArtwork.scope == scope { return recentDetailArtwork.replay }
        let replay = ArtworkBitmapReplay()
        recentDetailArtwork = (scope, replay)
        return replay
    }

    var detailArtworkScopeID: String { detailCacheScope.digest }

    private var detailCacheScope: DetailSnapshotCacheScope {
        let accounts = accountsProviders.homeAccounts.map(\.account)
        let profile = profiles.activeProfile
        let material = profile.plexPlaybackIdentityKey(for: accounts)
            + "|" + accounts.map(\.connectionScopeKey).sorted().joined(separator: "|")
        return DetailSnapshotCacheScope(profileID: profiles.activeProfileID, identityMaterial: material)
    }

    private let appAdmission: AppAdmissionModel
    let offlineMode: PlozziOSOfflineModeModel
    var isOfflineModeAvailable: Bool {
        runtimeFeatureFlags.isEnabled(.offlineMode) && OfflineMode.shared.isAvailable
    }
    var isOfflineMode: Bool { offlineMode.isEnabled }
    var isChangingOfflineMode: Bool { offlineMode.isChanging }
    var offlineModeGeneration: Int { offlineMode.generation }
    static var isStandalonePlaybackAvailable: Bool {
        true
    }

    var admissionContext: AppAdmissionContext {
        appAdmission.context(
            hasMediaAccounts: !accountsProviders.accounts.isEmpty,
            standalonePlaybackAvailable: Self.isStandalonePlaybackAvailable
        )
    }

    var canEnterApp: Bool { admissionContext.canEnterApp }
    var isProfilePlaybackAuthorized: Bool { isActiveProfileAuthorized && !isOfflineMode }

    var isActiveProfileAuthorized: Bool {
        return canEnterApp && !mustChooseProfile
            && (!requiresLaunchProfileSelection || didCompleteLaunchProfileSelection)
            && lockedSwitch == nil && parentalSwitch == nil
            && pendingIdentityAccount == nil && pendingLibrarySelection == nil
            && pendingFirstRunStep == nil && profileOnboardingStep == nil
            && plexHomeUsers.pendingPlexPINRequest == nil
            && !activeProfileNeedsUnlock
            && !accountsProviders.activeProfileAwaitsIdentity
    }

    var allowsHomeContentAccess: Bool {
        isActiveProfileAuthorized && !profiles.activeProfile.needsSetup
    }
    var allowsHomeContentLoading: Bool { allowsHomeContentAccess && !isSettingsPresented }
    var allowsStandalonePlayback: Bool { admissionContext.explicitStandaloneChoice }
    private struct HeroTrailerCacheEntry {
        let source: HeroTrailerSource?
        let expiresAt: Date
    }

    struct PendingLibrarySelection: Identifiable {
        let id = UUID()
        let accountIDs: [String]
    }

    /// Every screen of the post-sign-in first-run sequence, in order.
    ///
    /// One enum drives the whole flow so it can live in a SINGLE presentation:
    /// the Plex-user and library steps used to be their own sheets, so handing
    /// off between them dismissed to Home and re-presented. Outside first run
    /// those two screens still present individually (adding a server later is
    /// not a flow), which is why the model only populates this while first-run
    /// setup is actually running.
    enum FirstRunStep: String, Identifiable, CaseIterable {
        case plexUser
        case libraries
        case confirmProfile
        case theme

        var id: Self { self }

        /// Drives the direction of the in-flow transition.
        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    let accountsProviders: AccountsProvidersModel
    private let navigationLibraryDiscovery = NavigationLibraryDiscovery()

    var navigationLibrariesScopeKey: String {
        let credentials = accounts.map(\.connectionScopeKey).sorted().joined(separator: "|")
        let active = accountsProviders.activeAccountIDs.sorted().joined(separator: ",")
        return "\(profiles.activeProfileID)#\(credentials)#\(active)#\(plexHomeUsers.plexIdentityGeneration)#\(offlineModeGeneration)"
    }

    var visibleNavigationLibraries: [AggregatedLibrary] {
        let accountIDs = Set(accountsProviders.navigationAccounts.map(\.id))
        let downloadedLibraries: Set<String>? = isOfflineMode ? Set(downloads.playableRecords.compactMap { record in
            guard let accountID = record.snapshot.sourceAccountID
                ?? record.managedHTTPSource?.accountID ?? record.directShareSource?.accountID else { return nil }
            let libraryID = record.snapshot.libraryID
                ?? (record.snapshot.kind == .movie ? "offline.movies" : "offline.series")
            return accountID + "|" + libraryID
        }) : nil
        return NavigationRailPlan.browsableLibraries(settings.navigation.contentLibraries).filter {
            accountIDs.contains($0.accountID)
                && settings.homeVisibility.isEnabled($0.key)
                && !$0.isRetiredCollectionShortcut
                && (downloadedLibraries?.contains($0.accountID + "|" + $0.library.id) ?? true)
        }
    }

    @discardableResult
    func refreshNavigationLibraries() async -> Bool {
        guard !Task.isCancelled else { return false }
        let scope = navigationLibrariesScopeKey
        let currentSettings = settings
        let accountIDs = Set(accountsProviders.navigationAccounts.map(\.id))
        let accounts = accountsProviders.homeAccounts
        let cached = HomeAggregator.cachedLibraries(from: accounts)
        currentSettings.discoveredLibraries.seed(
            libraries: cached.libraries, cachedAccountIDs: cached.accountIDs, accountIDs: accountIDs
        )
        let request = currentSettings.discoveredLibraries.beginRefresh(
            accountIDs: accountIDs.subtracting(cached.accountIDs)
        )
        defer { currentSettings.discoveredLibraries.cancelRefresh(request) }
        guard let discovered = await navigationLibraryDiscovery.refresh(
            from: accounts,
            expectedAccountIDs: accountIDs,
            navigation: currentSettings.navigation,
            isCurrent: { self.settings === currentSettings && self.navigationLibrariesScopeKey == scope }
        ) else { return false }
        currentSettings.discoveredLibraries.finishRefresh(
            with: discovered.libraries,
            unreachableAccountIDs: discovered.unreachableAccountIDs,
            failures: discovered.failures,
            request: request
        )
        return true
    }

    let profiles: ProfilesModel
    @ObservationIgnored
    private(set) lazy var familyGuidance = FamilyGuidanceService(
        accounts: accountsProviders, profiles: profiles, plexHome: plexHomeUsers
    )
    /// Generic durable title identity for Plozz-owned profile state.
    let mediaAliasLedger: MediaAliasLedgerModel
    let transientStatusPresenter = TransientStatusPresenter()
    let universalWatchlist: WatchlistModel
    let runtimeFeatureFlags: RuntimeFeatureFlags
    let authenticatedHTTPResolver: ManagedAuthenticatedHTTPResolver
    let mediaShareRuntime: DefaultMediaShareRuntime

    @ObservationIgnored
    private lazy var mediaShareWorkScope = MediaShareWorkScopeController(
        snapshot: { [weak self] in
            guard let self else { return .paused }
            return .resolve(
                profileID: profiles.activeProfileID,
                isProfileAuthorized: isActiveProfileAuthorized && !isOfflineMode,
                activeAccountIDs: accountsProviders.activeAccountIDs,
                accounts: accountsProviders.accounts,
                visibility: settings.homeVisibility.visibility
            )
        },
        apply: { [runtime = mediaShareRuntime] scope, revision in
            await runtime.setAutomaticWorkScope(scope, revision: revision)
        }
    )
    /// Household-wide metadata provider roles/order override (mirrors tvOS `AppState`).
    /// App-wide like the enrichment pipeline itself, so created once.
    let metadataProviderSettingsModel = MetadataProviderSettingsModel()
    /// Household-wide metadata/artwork cache byte budgets. Device-level, created once.
    let cacheBudgetSettingsModel = CacheBudgetSettingsModel()
    /// Household-wide optional user-supplied TMDB API key (bring-your-own-key). Stored
    /// in the same `com.plozz.app.household` Keychain service as tvOS so the key matches
    /// across platforms.
    let tmdbUserKeyModel: TMDBUserKeyModel
    let shareScanStatus: ShareScanStatusModel
    let appLanguage: AppLanguageSettingsModel
    private(set) var requiresLaunchProfileSelection: Bool
    private(set) var settings: PlozziOSSettingsModel
    @ObservationIgnored
    private(set) var applicationIsActive = true
    @ObservationIgnored
    private var downloadProfileGeneration = 0
    @ObservationIgnored
    private var sceneSessionIDs: [String: UUID] = [:]
    @ObservationIgnored
    private var sceneNotificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored
    private lazy var applicationLifecycle = ApplicationSceneLifecycle(
        initiallyActive: applicationIsActive,
        makeSuspensionLease: { expiration in
            Self.makeSuspensionLease(expiration: expiration)
        },
        operation: { [weak self] transition in
            await self?.applyApplicationActivity(transition)
        },
        expirationOperation: { [weak self] transition in
            guard let self else { return }
            PlozzLog.boot(
                "ios.lifecycle suspension lease expired revision=\(transition.revision)"
            )
            await self.applyApplicationActivity(transition)
        }
    )
    private(set) var seriesTrackStore: SeriesTrackPreferenceStore
    private(set) var versionPreferences: VersionPreferenceStore
    private(set) var downloads: PlozziOSDownloadsModel
    var pendingDownloadSelection: MediaItem?
    private(set) var pendingLibrarySelection: PendingLibrarySelection?
    private(set) var pendingFirstRunStep: FirstRunStep?
    /// Drives the app to a named screen for an automated capture run. Inert unless
    /// the capture environment seeded this launch — see ``PlozziOSScreenshotSeed``.
    let screenshotDirector = PlozziOSScreenshotDirector()
    @ObservationIgnored
    private(set) var plexHomeUsers: PlexHomeUsersModel!
    @ObservationIgnored
    private(set) lazy var mediaItemActionHandler: any MediaItemActionHandling =
        MediaItemActionCoordinator(
            providerResolver: { [unowned self] accountID in
                accountID.flatMap {
                    self.accountsProviders.provider(forAccountID: $0)
                } ?? self.accountsProviders.primaryProvider
            },
            providerCapabilityResolver: { [unowned self] accountID in
                let provider = accountID.flatMap { id in
                    self.accountsProviders.homeAccounts.first {
                        $0.account.id == id
                    }?.provider
                } ?? self.accountsProviders.homeAccounts.first?.provider
                guard let provider else { return nil }
                return (
                    provider is WatchStateProviding,
                    provider is WatchlistProviding,
                    provider is MetadataRefreshing
                )
            },
            additionalSources: { [weak self] item in
                self?.identityIndex.identitySnapshot.sourceRefs(for: item) ?? []
            },
            primaryAccountID: { [unowned self] in
                self.accountsProviders.primaryActiveAccount?.id
            },
            crossServerWatchSyncEnabled: { [unowned self] in
                self.settings.playback.settings.syncWatchAcrossServers
            },
            enqueueWatchMutation: { [unowned self] mutation in
                self.applyWatchMutation(mutation, confirmsUserAction: true)
            },
            universalWatchlistEnabled: { [unowned self] in
                self.runtimeFeatureFlags.isEnabled(.universalWatchlist)
            },
            watchlistMembership: { [unowned self] item in
                self.universalWatchlistMembership(item)
                    || self.universalWatchlistMembershipByProviderBinding(item)
            },
            watchlistMembershipRevision: { [unowned self] in
                self.universalWatchlistMembershipRevision
            },
            performUniversalWatchlist: { [unowned self] adding, item in
                await self.performUniversalWatchlist(
                    adding: adding,
                    item: item
                )
            },
            presentUniversalWatchlistFeedback: {
                [unowned self] icon, text in
                self.transientStatusPresenter.present(
                    icon: icon,
                    text: text
                )
            },
            beginUniversalWatchlistFanOut: {
                [unowned self] adding, item in
                self.beginUniversalWatchlistFanOut(
                    adding: adding,
                    item: item
                )
            },
            watchlistProviderChange: { [unowned self] accountID in
                self.watchlistProviderChange(for: accountID)
            },
            resolveDurableWatchlist: { [unowned self] items in
                let resolved = self.resolvedUniversalWatchlistItems(candidates: items)
                return self.isOfflineMode ? resolved.compactMap(self.downloads.offlineWatchlistItem) : resolved
            },
            durableWatchlistPresentationReady: { [unowned self] in
                self.isOfflineMode || self.isUniversalWatchlistPresentationReady
            },
            durableWatchlistLoadingTarget: { [unowned self] in
                self.isOfflineMode ? nil : self.universalWatchlistLoadingTargetCount
            },
            rehydratePersistedArtworkItems: { [unowned self] items in
                self.isOfflineMode ? items.compactMap(self.downloads.offlineWatchlistItem) : self.rehydratedPersistedArtwork(items)
            },
            seedLegacyUniversalWatchlist: { [weak self] _ in
                try? await self?.seedLegacyUniversalWatchlist()
            },
            // Downloads are an iOS/iPadOS capability, so only this shell supplies
            // them; tvOS omits both closures and the catalog offers no download
            // actions there. Reads the registry synchronously (it's already loaded
            // in memory) so the menu can be built without awaiting.
            downloadState: { [unowned self] item in
                .some(self.downloads.cachedRecord(forSelectedVersionOf: item)?.menuState)
            },
            performDownloadAction: { [unowned self] action, item in
                let profileID = self.profiles.activeProfileID
                Task {
                    guard self.profiles.activeProfileID == profileID else { return }
                    await self.performDownloadMenuAction(action, on: item)
                }
            },
            makeActionConfirmation: { [unowned self] in self.makeLibraryActionFeedback() },
            makeWatchlistFailureFeedback: { [unowned self] in self.makeLibraryActionFeedback(onCompletion: .error) }
        )

    /// The shared account store used by provider services and app extensions.
    let accountStore: AccountPersisting
    private let durableLocalStateStore: DurableLocalStateStore?
    private let mediaShareAccountService: MediaShareAccountService
    private let mediaShareConfigurationService: MediaShareAccountConfigurationService
    private let mediaShareRescanService: MediaShareRescanService
    @ObservationIgnored private var plexUserSelectionGeneration: UInt64 = 0
    @ObservationIgnored private var appliesPlexIdentityAfterLibrarySelection = false
    @ObservationIgnored private var beginsFirstRunAfterLibrarySelection = false
    @ObservationIgnored private var isManagedServerPresentationActive = false
    @ObservationIgnored
    private var queuedPlexUserSelection: PlexHomeUsersModel.PendingPlexUserSelection?
    @ObservationIgnored private var queuedLibraryAccountIDs: [String]?
    @ObservationIgnored private var queuedLibrarySelectionBeginsFirstRun = false
    @ObservationIgnored private var postAddPresentationGeneration: UInt64 = 0
    @ObservationIgnored private var watchReconcilers: [String: WatchStateReconciler] = [:]
    @ObservationIgnored private lazy var watchOutboxConnectivity = WatchOutboxConnectivity { [weak self] in
        self?.retryWatchOutboxIfAllowed()
    }
    @ObservationIgnored var universalWatchlistReconciler: WatchlistReconciler?
    @ObservationIgnored var universalWatchlistMutationStore: DurableWatchlistMutationStore?
    @ObservationIgnored var universalWatchlistNativeView: NativeWatchlistView = .empty
    @ObservationIgnored
    private(set) lazy var universalWatchlistAnimeBridge = AnimeIDBridgeStore(
        directoryURL: Self.universalWatchlistStorageDirectory()
    )
    @ObservationIgnored var universalWatchlistNativeViewStore:
        (any NativeWatchlistViewStoring)?
    @ObservationIgnored var universalWatchlistDestinationIDs:
        Set<WatchlistDestinationID> = []
    @ObservationIgnored var universalWatchlistRefreshGeneration: UInt64 = 0
    @ObservationIgnored var universalWatchlistNativeViewLoaded = false
    @ObservationIgnored var universalWatchlistProfileID: String?
    @ObservationIgnored var universalWatchlistRetryScheduler:
        WatchlistRetryScheduler?
    @ObservationIgnored var universalWatchlistShouldResumeAuthentication = false
    @ObservationIgnored var universalWatchlistIdentityUpdateTask:
        Task<Void, Never>?
    @ObservationIgnored private var heroTrailerCache: [String: HeroTrailerCacheEntry] = [:]
    @ObservationIgnored
    private(set) lazy var identityIndex = IdentityIndexModel(
        activeAccounts: { [weak self] in
            self?.accountsProviders.homeAccounts ?? []
        },
        namespace: { [weak self] in
            self?.profiles.activeNamespace
        },
        onPublish: { [weak self] in
            self?.drainWatchOutbox()
            self?.universalWatchlistIdentityDidUpdate()
        },
        isWarmingAllowed: { [weak self] in
            self?.profiles.activeProfile.needsSetup == false
        }
    )

    private var watchReconciler: WatchStateReconciler {
        _ = watchOutboxConnectivity
        let profileID = profiles.activeProfileID
        if let existing = watchReconcilers[profileID] {
            return existing
        }
        let reconciler = makeWatchReconciler(profileID: profileID)
        watchReconcilers[profileID] = reconciler
        return reconciler
    }

    var accountError: String?

    init(
        appAdmissionStore: any AppAdmissionStoring = AppAdmissionStore(),
        accountStore suppliedAccountStore: AccountStore? = nil,
        profileStore: (any ProfilePersisting)? = nil,
        appLanguage: AppLanguageSettingsModel? = nil,
        runtimeFeatureFlags: RuntimeFeatureFlags = .buildDefault
    ) {
        let bootStart = DispatchTime.now().uptimeNanoseconds
        func boot(_ label: String) {  // l10n:content — developer boot telemetry
            PlozzLog.boot(
                "AppModel.init \(label) ms=\(Double(DispatchTime.now().uptimeNanoseconds - bootStart) / 1_000_000)"
            )
        }
        boot("START")
        let offlineAvailable = runtimeFeatureFlags.isEnabled(.offlineMode) && OfflineMode.shared.isAvailable
        let offline = offlineAvailable && UserDefaults.standard.bool(forKey: OfflineMode.preferenceKey)
        self.offlineMode = PlozziOSOfflineModeModel(isEnabled: offline, monitorsConnectivity: offlineAvailable)
        OfflineMode.shared.setEnabled(offline)
        self.appLanguage = appLanguage ?? AppLanguageSettingsModel()
        let appAdmission = AppAdmissionModel(store: appAdmissionStore)
        self.appAdmission = appAdmission
        let authenticatedHTTPResolver = ManagedAuthenticatedHTTPResolver()
        let accountStore: AccountStore
        var launchErrors: [String] = []
        if let suppliedAccountStore {
            accountStore = suppliedAccountStore
        } else {
            do {
                accountStore = try DefaultAccountStoreFactory.make()
            } catch {
                accountStore = DefaultAccountStoreFactory.makeCredentialOnlyFallback()
                launchErrors.append(
                    "Network-share credential storage is unavailable: \(error.localizedDescription)"
                )
            }
        }
        boot("accountStore")
        let mediaShareRuntime = DefaultMediaShareRuntime.make(
            accountStore: accountStore,
            artworkCacheLifecycle: PlozziOSMediaShareArtworkCacheLifecycle(),
            sourcePreparer: PlozzigenNetworkFileStreamProber.preparePlaybackSource
        )
        ArtworkImageCache.shared.configure(
            networkFileService: mediaShareRuntime.artworkNetworkFileService
        )
        let durableLocalStateStore: DurableLocalStateStore?
        do {
            durableLocalStateStore = try DurableLocalStateStoreFactory.userIndependent()
        } catch {
            durableLocalStateStore = nil
            launchErrors.append(
                "Local network-share library storage is unavailable: \(error.localizedDescription)"
            )
        }
        let registry = ManagedProviderRegistry.make(
            siloCredentials: accountStore as? any RotatingCredentialStoring, durableStore: durableLocalStateStore
        )
        mediaShareRuntime.registerProvider(
            into: registry,
            durableLocalStateStore: durableLocalStateStore
        )
        boot("registry")
        let profiles = ProfilesModel(
            store: profileStore ?? ProfileStore(
                secureStore: KeychainStore(service: "com.plozz.app.household")
            ),
            defaultActiveAccountIDs: accountStore.activeAccountIDs()
        )
        boot("profiles")
        // Forced when the profile we'd restore is locked, so its content never
        // renders behind the PIN prompt — the unlock then runs through the
        // ordinary `selectProfile(_:)` gate with the picker behind it.
        let requiresLaunchProfileSelection =
            profiles.activeProfile.isLocked
            || profiles.profiles.count > 1
        let accountsProviders = AccountsProvidersModel(
            accountStore: accountStore,
            registry: registry,
            profilesModel: profiles
        )
        boot("accountsProviders")
        if offline { accountsProviders.localProviders = [:] }
        let shareScanStatus = ShareScanStatusModel()
        self.accountStore = accountStore
        self.profiles = profiles
        self.accountsProviders = accountsProviders
        self.authenticatedHTTPResolver = authenticatedHTTPResolver
        self.mediaShareRuntime = mediaShareRuntime
        let tmdbKeyRuntime = mediaShareRuntime
        self.tmdbUserKeyModel = TMDBUserKeyModel(
            store: TMDBUserKeyStore(secureStore: KeychainStore(service: "com.plozz.app.household")),
            validator: { token in await tmdbKeyRuntime.validateTMDBUserKey(token) },
            onCredentialSuperseded: { token in await tmdbKeyRuntime.invalidateTMDBCredential(forToken: token) }
        )
        self.shareScanStatus = shareScanStatus
        self.durableLocalStateStore = durableLocalStateStore
        let aliasStorageDirectory = Self.isRunningUnitTests
            ? nil
            : Self.mediaAliasStorageDirectory()
        self.mediaAliasLedger = MediaAliasLedgerModel(
            durableStore: aliasStorageDirectory == nil ? nil : durableLocalStateStore,
            storageDirectory: aliasStorageDirectory
        )
        self.runtimeFeatureFlags = runtimeFeatureFlags
        self.universalWatchlist = WatchlistModel(
            storageDirectory: Self.isRunningUnitTests
                ? nil
                : Self.universalWatchlistStorageDirectory()
        )
        self.requiresLaunchProfileSelection = requiresLaunchProfileSelection
        let initialSettings = PlozziOSSettingsModel(
            namespace: profiles.activeNamespace,
            allowsDiscovery: { !profiles.activeProfile.isKids }
        )
        self.settings = initialSettings
        boot("settings")
        self.seriesTrackStore = SeriesTrackPreferenceStore(
            namespace: profiles.activeNamespace
        )
        self.versionPreferences = VersionPreferenceStore(
            namespace: profiles.activeNamespace
        )
        self.downloads = Self.makeDownloadsModel(
            namespace: profiles.activeProfileID,
            durableStore: durableLocalStateStore,
            mediaShareRuntime: mediaShareRuntime,
            accountsProviders: accountsProviders,
            settingsNamespace: profiles.activeNamespace,
            authenticatedHTTPResolver: authenticatedHTTPResolver,
            statusPresenter: transientStatusPresenter
        )
        boot("downloads")
        self.pendingLibrarySelection = nil
        self.pendingFirstRunStep =
            appAdmission.context(
                hasMediaAccounts: !accountsProviders.accounts.isEmpty,
                standalonePlaybackAvailable: Self.isStandalonePlaybackAvailable
            ).canEnterApp
                && !profiles.firstRunProfileSetupComplete
            ? .confirmProfile
            : nil
        self.mediaShareAccountService = MediaShareAccountService(runtime: mediaShareRuntime)
        self.mediaShareConfigurationService = MediaShareAccountConfigurationService(
            accountStore: accountStore
        )
        self.mediaShareRescanService = MediaShareRescanService(
            accountsProviders: accountsProviders
        )
        self.plexHomeUsers = PlexHomeUsersModel(
            accountsProviders: accountsProviders,
            profilesModel: profiles,
            runtimeFeatureFlags: runtimeFeatureFlags,
            switchProfile: { [weak self] profileID in
                self?.selectProfile(profileID)
            },
            // Same seam as tvOS: watching as someone else changes whose library,
            // watch state and watchlist this is, without moving the profile or
            // the account set, so nothing else asks anything to reload.
            onIdentityChanged: { [weak self] in
                self?.refreshForPlexIdentityChange()
            }
        )
        accountsProviders.tokenResolver = { [weak self] accountID in
            self?.plexHomeUsers.resolvedToken(for: accountID)
        }
        accountsProviders.onAccountsInvalidated = { [weak self] in
            self?.mediaItemActionHandler.invalidateAccountCaches()
            self?.universalWatchlistProfileID = nil
            self?.universalWatchlistRetryScheduler = nil
            self?.universalWatchlistShouldResumeAuthentication = true
            Task { await self?.prepareUniversalWatchlist() }
        }
        accountsProviders.onActiveAccountsChanged = { [weak self] _, _ in
            self?.plexHomeUsers.activeAccountsDidChange()
            self?.refreshOfflineProviders()
        }
        accountsProviders.credentialRevision = { [weak self] account in
            self?.plexHomeUsers.effectiveCredentialRevision(for: account)
                ?? account.credentialRevision
        }
        accountsProviders.cloudTokenResolver = { [weak self] account, revision in
            guard let self else { throw CancellationError() }
            return try await self.plexHomeUsers.resolveCloudToken(for: account, expectedRevision: revision)
        }
        accountsProviders.configureAuthenticatedArtwork()
        authenticatedHTTPResolver.configure { [weak accountsProviders] locator in
            guard let accountsProviders,
                  let account = accountsProviders.accounts.first(where: {
                      $0.id == locator.accountID
                  }),
                  account.server.provider == locator.provider,
                  accountsProviders.credentialRevision(account) == locator.credentialRevision,
                  let token = accountsProviders.tokenResolver(account.id),
                  !token.isEmpty else {
                throw MediaTransportError.authentication(
                    reason: "inactive authenticated HTTP identity"
                )
            }
            let baseURL: URL
            if account.server.provider == .plex {
                let provider = try accountsProviders.registry.provider(
                    for: accountsProviders.providerResolutionContext(
                        for: account,
                        token: token
                    )
                )
                guard let originProvider = provider as? AuthenticatedHTTPOriginProviding else {
                    throw MediaTransportError.unsupportedCapability(
                        "dynamic authenticated HTTP origin"
                    )
                }
                baseURL = originProvider.authenticatedHTTPOrigin
            } else {
                baseURL = account.server.baseURL
            }
            return ManagedAuthenticatedHTTPResolver.Context(
                provider: account.server.provider,
                accountID: account.id,
                credentialRevision: accountsProviders.credentialRevision(account),
                baseURL: baseURL,
                token: token,
                resourceResolver: accountsProviders.provider(forAccountID: account.id) as? any ProviderHTTPResourceResolving,
                originProvider: accountsProviders.provider(forAccountID: account.id) as? any AuthenticatedHTTPOriginProviding,
                connectionScopeKey: account.connectionScopeKey
            )
        }
        do {
            try accountStore.recoverCredentialMutations()
        } catch {
            PlozzLog.auth.error(
                "Credential recovery failed; incomplete shares remain hidden"
            )
            launchErrors.append(
                "An interrupted network-share update could not be recovered."
            )
        }
        accountError = launchErrors.isEmpty ? nil : launchErrors.joined(separator: "\n")
        accountsProviders.reloadAccounts()
        refreshOfflineProviders()
        boot("accountsLoaded")
        if plexHomeUsers.restoreAutomaticSignInAtLaunch() {
            self.requiresLaunchProfileSelection = false
        }
        // Self-heal any stale server names (shared path with tvOS).
        accountsProviders.refreshServerNames()
        if canEnterApp,
           !profiles.firstRunProfileSetupComplete {
            pendingFirstRunStep = .confirmProfile
        }
        if !isOfflineMode { identityIndex.warmIdentityIndex() }
        let scanReporter = shareScanStatus.reporter()
        Task { await mediaShareRuntime.configure(reporter: scanReporter) }
        if !self.requiresLaunchProfileSelection {
            plexHomeUsers.ensurePlexIdentityForActiveProfile()
        }
        drainWatchOutbox()
        Task { @MainActor in
            await prepareUniversalWatchlist()
        }
        prepareMediaAliasLedger()
        observeApplicationScenes()
        // The tvOS root prewarms this before exposing Home; the iOS shell learned
        // to paint the snapshot but kept its first read on the main thread. Decode
        // the same per-profile snapshot off-main so HomeViewModel.init is a memo
        // lookup when the tab shell is first built.
        if !isOfflineMode {
            let namespace = profiles.activeNamespace
            Task.detached(priority: .utility) {
                await HomeContentPrewarmer.shared.prepare {
                    HomeContentStore(namespace: namespace)
                }
            }
        }
        mediaShareWorkScope.start()
        boot("END")
    }

    func setOfflineMode(_ enabled: Bool) async {
        guard !enabled || isOfflineModeAvailable else {
            PlozzLog.app.error("Offline Mode activation refused: feature flag disabled")
            return
        }
        guard enabled != isOfflineMode, !isChangingOfflineMode else { return }
        offlineMode.isChanging = true
        defer { offlineMode.isChanging = false }
        OfflineMode.shared.setEnabled(enabled)
        offlineMode.isEnabled = enabled
        offlineMode.generation &+= 1
        UserDefaults.standard.set(enabled, forKey: OfflineMode.preferenceKey)
        pendingDownloadSelection = nil
        identityIndex.reset()
        if enabled {
            accountsProviders.localProviders = [:]
            await mediaShareWorkScope.synchronize()
            await downloads.suspendForOfflineMode()
            await OfflineNetworkSession.cancelRequests()
        } else {
            accountsProviders.localProviders = nil
            plexHomeUsers.beginExplicitProfileActivation()
        }
        refreshOfflineProviders()
        accountsProviders.registry.invalidateCache()
        plexHomeUsers.retryPlexPINRequirement()
        plexHomeUsers.ensurePlexIdentityForActiveProfile()
        await transitionDownloads(to: profiles.activeProfileID).value
        if !enabled {
            accountsProviders.refreshServerNames()
            identityIndex.warmIdentityIndex()
            retryWatchOutboxIfAllowed()
            await prepareUniversalWatchlist()
        }
    }

    private func refreshOfflineProviders() {
        guard isOfflineMode else { return }
        offlineMode.generation &+= 1
        let profileID = profiles.activeProfileID
        let generation = offlineModeGeneration
        accountsProviders.localProviders = Dictionary(uniqueKeysWithValues:
            accountsProviders.accounts.compactMap { account in
                guard let userID = accountsProviders.downloadUserID(for: account.id, profileID: profileID) else {
                    return nil
                }
                let libraries = settings.navigation.contentLibraries.filter { $0.accountID == account.id }.map(\.library)
                let provider = downloads.offlineProvider(account: account, libraries: libraries) { [weak self] in
                    try await MainActor.run {
                        guard let self, self.isOfflineMode, self.offlineModeGeneration == generation,
                              self.profiles.activeProfileID == profileID, self.isActiveProfileAuthorized,
                              self.accountsProviders.activeAccountIDs.contains(account.id),
                              self.accountsProviders.downloadUserID(for: account.id, profileID: profileID) == userID,
                              self.accountsProviders.accounts.contains(account)
                        else { throw AppError.unauthorized }
                    }
                }
                return provider.map { (account.id, $0) }
            }
        )
    }

    var accounts: [Account] {
        accountsProviders.accounts
    }

    private func reloadAccountsAndHeroCache() {
        heroTrailerCache.removeAll()
        accountsProviders.reloadAccounts()
    }

    func provider(for item: MediaItem) -> (any MediaProvider)? {
        if let accountID = item.sourceAccountID {
            return accountsProviders.provider(forAccountID: accountID)
        }
        return accountsProviders.primaryProvider
    }

    func heroTrailerResolver() -> HeroTrailerResolving {
        { [weak self] item in
            await self?.resolveHeroTrailer(for: item)
        }
    }

    private func resolveHeroTrailer(for item: MediaItem) async -> HeroTrailerSource? {
        guard !isOfflineMode else { return nil }
        let cacheKey = "\(item.sourceAccountID ?? "_"):\(item.id)"
        let now = Date()
        if let cached = heroTrailerCache[cacheKey], cached.expiresAt > now {
            return cached.source
        }

        let source = await FastHeroTrailerResolver.resolve(
            item: item,
            identitySources: identityIndex.identitySourcesProvider(item),
            providerForAccountID: {
                accountsProviders.provider(forAccountID: $0)
            },
            authenticatedHTTPResolver: authenticatedHTTPResolver
        )
        guard !Task.isCancelled else { return nil }

        // A session grant belongs to one player; even a short TTL outlives a stop.
        if let source, !source.isCacheable { return source }
        // Other signed playback URLs can expire, so positive entries stay short-lived.
        // Negative entries use an even shorter TTL so a newly-added trailer appears
        // without requiring an app restart.
        let ttl: TimeInterval = source == nil ? 120 : 600
        heroTrailerCache[cacheKey] = HeroTrailerCacheEntry(
            source: source,
            expiresAt: now.addingTimeInterval(ttl)
        )
        if heroTrailerCache.count > 64 {
            heroTrailerCache = heroTrailerCache.filter { $0.value.expiresAt > now }
            if heroTrailerCache.count > 64,
               let oldest = heroTrailerCache.min(by: {
                   $0.value.expiresAt < $1.value.expiresAt
               })?.key {
                heroTrailerCache[oldest] = nil
            }
        }
        return source
    }

    func rescanShare(accountID: String) {
        mediaShareRescanService.rescan(accountID: accountID)
    }

    private func observeApplicationScenes() {
        guard sceneNotificationTokens.isEmpty else { return }
        for name in [
            UIScene.didActivateNotification,
            UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification,
            UIScene.didDisconnectNotification
        ] {
            sceneNotificationTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.refreshApplicationScenes(notification: notification)
                }
            })
        }
        refreshApplicationScenes(notification: nil)
    }

    private func refreshApplicationScenes(notification: Notification?) {
        let changedScene = notification?.object as? UIScene
        let changedID = changedScene?.session.persistentIdentifier
        var scenes: [UUID: Bool] = [:]
        var connected = Set<String>()
        for scene in UIApplication.shared.connectedScenes {
            let sessionID = scene.session.persistentIdentifier
            if sessionID == changedID,
               notification?.name == UIScene.didDisconnectNotification { continue }
            connected.insert(sessionID)
            let id = sceneSessionIDs[sessionID] ?? UUID()
            sceneSessionIDs[sessionID] = id
            if sessionID == changedID {
                scenes[id] = notification?.name == UIScene.didActivateNotification
            } else {
                scenes[id] = scene.activationState == .foregroundActive
            }
        }
        sceneSessionIDs = sceneSessionIDs.filter { connected.contains($0.key) }
        if let transition = applicationLifecycle.replaceScenes(scenes) {
            applicationIsActive = transition.isActive
            if transition.isActive { retryWatchOutboxIfAllowed() }
        }
    }

    private func applyApplicationActivity(
        _ transition: ApplicationActivityTransition
    ) async {
        let downloads = downloads
        async let mediaShareTransition: Void =
            mediaShareRuntime.setBackgroundWorkAllowed(
                transition.isActive,
                revision: transition.revision
            )
        async let downloadTransition: Void =
            downloads.setApplicationActive(
                transition.isActive,
                revision: transition.revision
            )
        async let storageTransition: Void =
            ApplicationStorageLifecycle.shared.setApplicationActive(
                transition.isActive,
                revision: transition.revision
            )
        _ = await (mediaShareTransition, downloadTransition, storageTransition)
    }

    private static func makeSuspensionLease(
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> ApplicationLifecycleLease? {
        let lease = ApplicationLifecycleLease(expiration: expiration)
        let identifier = UIApplication.shared.beginBackgroundTask(
            withName: "Plozz suspension safety"
        ) {
            // UIKit documents background-task expiration handlers as main-thread
            // callbacks. Run inline so the assertion is ended in that callback,
            // rather than relying on another task that may not be scheduled.
            MainActor.assumeIsolated {
                lease.expire()
            }
        }
        guard identifier != .invalid else {
            lease.end()
            return nil
        }
        lease.installEndAction {
            UIApplication.shared.endBackgroundTask(identifier)
        }
        return lease
    }

    /// Media-share account ids signed in on this device. Scopes the Settings
    /// status header so a removed share's late scanner event can't leave a ghost
    /// row. Deliberately NOT the busy states themselves: the header does that
    /// (high-frequency) lookup in its own body so progress ticks can't invalidate
    /// the whole Settings page.
    var mediaShareAccountIDs: Set<String> {
        Set(
            accountsProviders.accounts
                .filter { $0.server.provider == .mediaShare }
                .map(\.id)
        )
    }

    var deviceID: String {
        accountStore.deviceID()
    }

    /// Debug-only: clear all accounts + profiles so the app returns to the
    /// first-run / onboarding empty state.
    @discardableResult
    func resetToFirstRunForDebugging() -> Bool {
        do {
            try accountStore.clearAll()
        } catch {
            PlozzLog.auth.error("First-run reset could not remove every account")
            accountError = error.localizedDescription
            return false
        }
        accountsProviders.reloadAccounts()
        guard accountsProviders.accounts.isEmpty else { return false }
        plexHomeUsers.resetAllForDebug()
        do {
            profiles.resetToPristineDefaultForDebugging()
        } catch {
            PlozzLog.sync.error("First-run reset could not remove every profile")
            accountError = error.localizedDescription
            return false
        }
        if accountsProviders.accounts.isEmpty { appAdmission.resetForDebugging() }
        pendingLibrarySelection = nil
        pendingFirstRunStep = nil
        // Bypass the lock gate deliberately: this is the debug "reset to first
        // run" path and it has just wiped the profiles back to a pristine default.
        performSelectProfile(profiles.activeProfileID)
        return true
    }

    /// Everything guarding entry to a profile, in ONE observable property.
    ///
    /// These four are only ever meaningful together — an error without a pending
    /// switch is nonsense, and "the launch picker is satisfied" is the same
    /// question as "did a gated switch complete" — and this model is already over
    /// the observable-fan-out ceiling, so the feature is one property rather than
    /// four. The read-only accessors below keep the call sites reading plainly.
    private(set) var gate = ProfileGate()

    /// The state guarding entry to a profile. See `gate`.
    struct ProfileGate {
        /// A profile waiting on its PIN before it can be opened, or `nil`.
        var lockedSwitch: ParentalSwitchRequest?
        /// A switch out of a Kids Profile, held until the Parental PIN is entered.
        var parentalSwitch: ParentalSwitchRequest?
        /// The enforced Kids Profile the device was moved OUT of without anyone
        /// asking — a local or synced deletion re-points the active profile on
        /// its own. Held until the Parental PIN clears it; see the tvOS twin.
        var parentalFallThrough: Profile?
        /// Whether the launch picker has been satisfied by a switch that actually
        /// completed. See `performSelectProfile`.
        var didCompleteLaunchSelection = false
        var inlinePlexPINRequest: PlexHomeUsersModel.PlexPINRequest?
    }

    /// `PlozziOSRootView` presents the profile-lock PIN screen off this.
    var lockedSwitch: ParentalSwitchRequest? { gate.lockedSwitch }
    /// `PlozziOSRootView` presents the Parental PIN screen off this.
    var parentalSwitch: ParentalSwitchRequest? { gate.parentalSwitch }
    var parentalFallThrough: Profile? { gate.parentalFallThrough }
    var didCompleteLaunchProfileSelection: Bool { gate.didCompleteLaunchSelection }

    /// Whether profile management (add/edit) must be withheld right now: the
    /// household policy plus the fall-through hold.
    var managementRequiresParentalPIN: Bool {
        profiles.managementRequiresParentalPIN || gate.parentalFallThrough != nil
    }
    /// Where a newly created profile is in its setup sequence.
    ///
    /// An explicit sequence rather than a handful of overlapping optionals: the
    /// steps are ordered, only one is ever on screen, and "which comes next" is a
    /// single `switch` instead of an invariant spread across five booleans.
    enum ProfileOnboardingStep: String, Identifiable, CaseIterable {
        /// Which servers this profile uses, and who it watches as on each.
        case libraries
        /// Its colour scheme, which is per-profile.
        case theme
        /// Whether to put a PIN on it — offered at creation, like on tvOS, since
        /// that's when someone setting up a household profile is thinking about
        /// who should be able to open it.
        case lockOffer

        var id: Self { self }

        var next: ProfileOnboardingStep? {
            switch self {
            case .libraries: .theme
            case .theme: .lockOffer
            case .lockOffer: nil
            }
        }
    }

    /// Which screen puts the setup sequence on screen.
    ///
    /// A cover can only be presented by a view that isn't itself covered, and the
    /// sequence starts from two very different places: creating (or resuming) a
    /// profile from Settings, which is a sheet — so a cover asked for from the
    /// root would be silently dropped — and resuming an abandoned setup at
    /// launch, when Settings isn't open and the Profiles page isn't on screen to
    /// ask from. Both sites are wired up, and this says which one owns it, so
    /// they can never both try.
    enum ProfileOnboardingOrigin {
        case settings
        case launch
    }

    /// Whether the Settings sheet is on screen. Set by the sheet itself.
    private(set) var isSettingsPresented = false

    /// The exact request owned by an on-screen Plex user chooser, not another modal.
    var inlinePlexPINRequest: PlexHomeUsersModel.PlexPINRequest? {
        get { gate.inlinePlexPINRequest }
        set { gate.inlinePlexPINRequest = newValue }
    }

    var plexPINRequestForAppPresentation: PlexHomeUsersModel.PlexPINRequest? {
        guard plexHomeUsers.pendingPlexUserSelection == nil, pendingLibrarySelection == nil else { return nil }
        let request = plexHomeUsers.pendingPlexPINRequest
        return request == inlinePlexPINRequest ? nil : request
    }

    func noteSettingsPresented(_ presented: Bool) {
        isSettingsPresented = presented
    }

    /// DERIVED from what's actually on screen rather than recorded when the flow
    /// starts. A stored origin has to be written by whoever begins the sequence,
    /// and the resume path — which can begin it too, from either place — had no
    /// way to know which it was; it guessed `.launch`, so resuming an unfinished
    /// profile from Settings asked the covered root to present and the cover
    /// silently never appeared, with the step left set so nothing retried.
    var profileOnboardingOrigin: ProfileOnboardingOrigin {
        isSettingsPresented ? .settings : .launch
    }

    /// Whether `origin` should present the sequence right now.
    func isPresentingProfileOnboarding(from origin: ProfileOnboardingOrigin) -> Bool {
        profileOnboardingStep != nil && profileOnboardingOrigin == origin
    }

    /// The setup step currently being presented, if any.
    private(set) var profileOnboardingStep: ProfileOnboardingStep?
    /// The profile being set up. Held by ID, not by value: the record changes
    /// underneath us as each step writes to it.
    private(set) var profileOnboardingID: String?
    /// Additional identity being added from this profile's "Watching as" page.
    private var pendingAdditionalUser: (serverKey: String, profileID: String)?

    /// The profile the sequence is currently about, read live.
    var profileBeingOnboarded: Profile? {
        guard let profileOnboardingID else { return nil }
        return profiles.profiles.first { $0.id == profileOnboardingID }
    }

    /// Re-presents setup for a profile that never finished it.
    ///
    /// The gate is PERSISTED, so quitting mid-setup leaves it set — and a profile
    /// stuck behind it never imports a watchlist at all, silently and forever.
    /// Resuming asks the question that was never answered: importing anyway is
    /// the leak the gate exists to prevent, and clearing it without asking is the
    /// same thing by another route.
    func resumeProfileOnboardingIfNeeded() {
        // `profileOnboardingID` — not just the step — because creation claims the
        // id and origin synchronously and only raises the step a runloop turn
        // later (so the editor sheet can close first). Switching into the new
        // profile schedules a resume in that same window; guarding on the step
        // alone let the resume win the race and relabel a `.settings` flow as
        // `.launch`, so the cover was asked for from the root while Settings was
        // still up — and silently never appeared. Exactly what the origin split
        // exists to prevent.
        guard profileOnboardingStep == nil, profileOnboardingID == nil,
              pendingFirstRunStep == nil, plexHomeUsers.pendingPlexUserSelection == nil,
              pendingLibrarySelection == nil else { return }
        guard profiles.activeProfile.needsSetup else { return }
        profileOnboardingID = profiles.activeProfileID
        profileOnboardingStep = .libraries
    }

    /// Advances to the next setup step, releasing the watchlist import when the
    /// server/identity step is finished.
    func advanceProfileOnboarding() {
        guard let step = profileOnboardingStep, let id = profileOnboardingID else { return }
        if step == .libraries {
            // Only NOW — with this profile's servers and identity settled — is an
            // import meaningful. Until `finishSetup` clears the gate the profile
            // holds every server it inherited, and importing against that pulls
            // the household's aggregate watchlist into it.
            if profiles.finishSetup(for: id) {
                identityIndex.warmIdentityIndex()
                Task { @MainActor in
                            await prepareUniversalWatchlist()
                }
            }
        }
        if let next = step.next {
            profileOnboardingStep = next
        } else {
            profileOnboardingStep = nil
            profileOnboardingID = nil
        }
    }

    /// Ends setup early (the cover was swiped away). The gate still has to be
    /// released, or the profile would never import a watchlist at all.
    func cancelProfileOnboarding() {
        guard let id = profileOnboardingID else { return }
        if profiles.finishSetup(for: id) {
            identityIndex.warmIdentityIndex()
            Task { @MainActor in
                    await prepareUniversalWatchlist()
            }
        }
        profileOnboardingStep = nil
        profileOnboardingID = nil
    }

    /// The Plex account this profile has just enabled and not yet picked a user
    /// on. The Libraries screen presents the picker from this.
    ///
    /// Read from the PROFILE, not from memory: the question has to outlive a
    /// relaunch, because the enabled-but-unidentified server does. See
    /// `Profile.accountsAwaitingIdentity`.
    var pendingIdentityAccount: Account? {
        guard let id = profiles.actionableIdentityAccountIDs(
            forProfile: profiles.activeProfileID,
            importAccountIDs: ProfileServerIdentityPolicy
                .importPlexAccountIDs(
                    in: NativeWatchlistAccounts.resolve(
                        profiles: profiles,
                        accountsProviders: accountsProviders
                    )
                )
        ).first else { return nil }
        return accounts.first { $0.id == id }
    }

    private func noteServerAwaitingIdentity(_ accountID: String, profileID: String) {
        guard let account = accounts.first(where: { $0.id == accountID }),
              var profile = profiles.profiles.first(where: { $0.id == profileID }),
              ProfileServerIdentityPolicy.shouldAsk(
                  provider: account.server.provider,
                  hasExistingBinding: profile.homeUserBinding(forPlexAccount: accountID) != nil
              ),
              profile.noteAccountAwaitingIdentity(accountID)
        else { return }
        profiles.update(profile)
    }

    struct ServerIdentityQuestion: Identifiable {
        struct ID: Hashable {
            let profileID: String
            let accountID: String
        }
        let id: ID
        let account: Account
    }

    /// The import stays gated by the persisted question even when a profile
    /// picker or unlock screen must come first.
    var presentableIdentityQuestion: ServerIdentityQuestion? {
        guard canEnterApp, !mustChooseProfile,
              !requiresLaunchProfileSelection || didCompleteLaunchProfileSelection,
              lockedSwitch == nil, parentalSwitch == nil, !activeProfileNeedsUnlock,
              !profiles.activeProfile.needsSetup, pendingFirstRunStep == nil, profileOnboardingStep == nil,
              pendingLibrarySelection == nil, plexHomeUsers.pendingPlexUserSelection == nil,
              !isManagedServerPresentationActive, plexPINRequestForAppPresentation == nil,
              let account = pendingIdentityAccount else { return nil }
        return .init(id: .init(profileID: profiles.activeProfileID, accountID: account.id), account: account)
    }

    /// Closes the question when the sheet goes away.
    ///
    /// Closing is NOT declining. Inferring a decline from "no Home-user binding
    /// was written" looked equivalent and was badly wrong: watching as the
    /// account OWNER is the normal case and leaves no binding either, so simply
    /// closing the sheet declined the viewer's own server and emptied their
    /// watchlist completely. Declining has to be something a person chooses,
    /// which is what `declineIdentityPrompt` and the button that calls it are
    /// for.
    func concludeIdentityPrompt(_ question: ServerIdentityQuestion, decline: Bool = false) {
        guard presentableIdentityQuestion?.id == question.id, inlinePlexPINRequest == nil else { return }
        if decline { declineIdentityPrompt(for: question.account.id) }
        else { resolveIdentityPrompt(for: question.account.id) }
    }

    /// Re-reads everything scoped to the Plex identity after "watching as"
    /// changes. See `AppState.refreshForPlexIdentityChange()` — the shells keep
    /// this in step deliberately.
    func refreshForPlexIdentityChange() {
        accountsProviders.reloadAccounts()
        transitionDownloads(to: profiles.activeProfileID)
        Task { [weak self] in
            await self?.prepareUniversalWatchlist()
        }
    }

    /// Clears the question once a user is chosen.
    func resolveIdentityPrompt(for accountID: String) {
        applyIdentityAnswer(for: accountID) {
            $0.resolveAccountAwaitingIdentity(accountID)
        }
    }

    /// Records that nobody said who this profile is on this server, so its own
    /// watchlist is left alone. See `Profile.watchlistDeclinedAccountIDs`.
    func declineIdentityPrompt(for accountID: String) {
        applyIdentityAnswer(for: accountID) {
            $0.declineAccountWatchlist(accountID)
        }
    }

    private func applyIdentityAnswer(
        for accountID: String,
        _ apply: (inout Profile) -> Bool
    ) {
        let profileID = profiles.activeProfileID
        guard var profile = profiles.profiles.first(where: { $0.id == profileID }),
              apply(&profile)
        else { return }
        profiles.update(profile)
        // The import was deferred while this was outstanding; with the answer in
        // it can finally run, against the identity that was just chosen.
        guard !profile.needsSetup, profiles.actionableIdentityAccountIDs(
            forProfile: profile.id,
            importAccountIDs: ProfileServerIdentityPolicy
                .importPlexAccountIDs(
                    in: NativeWatchlistAccounts.resolve(
                        profiles: profiles,
                        accountsProviders: accountsProviders
                    )
                )
        ).isEmpty else { return }
        Task { @MainActor in
            await prepareUniversalWatchlist()
        }
    }

    /// Whether the profile that is already active is locked and unproven — the
    /// backstop for paths that make a profile active without going through
    /// `selectProfile(_:)` (a synced deletion re-pointing at `profiles.first`).
    var activeProfileNeedsUnlock: Bool {
        let active = profiles.activeProfile
        return active.isLocked && !profiles.isProfileUnlocked(active.id)
            && !plexHomeUsers.isAutomaticallySignedIn(active)
    }

    func setAutomaticallySignIn(_ enabled: Bool) {
        plexHomeUsers.setAutomaticallySignIn(
            enabled,
            profileIsUnlocked: !activeProfileNeedsUnlock && !mustChooseProfile
        )
    }

    /// Switches to `id`, unless its lock needs proof for this activation — in which case
    /// the PIN prompt is raised and nothing is re-scoped until it's satisfied.
    ///
    /// The lock rides the synced profile record, so a profile locked on the Apple
    /// TV arrives here locked too; without this gate it would open with one tap
    /// and the lock would be worthless.
    @ObservationIgnored
    private var plexOnboardingSelection: (id: String, onActivated: @MainActor () -> Void)?

    func selectProfileForPlexOnboarding(_ id: String, onActivated: @escaping @MainActor () -> Void) {
        plexOnboardingSelection = (id, onActivated)
        requestProfileSelection(id)
    }

    func selectProfile(_ id: String) {
        plexOnboardingSelection = nil
        requestProfileSelection(id)
    }

    private func requestProfileSelection(_ id: String) {
        guard let target = profiles.profiles.first(where: { $0.id == id }) else {
            performSelectProfile(id)
            return
        }
        // May you leave? Walking out of a Kids Profile needs the household
        // Parental PIN, and is checked before the target's own lock — same order
        // as tvOS, from the same shared policy on `ProfilesModel`.
        // The hold wins over `activeProfile`: after an involuntary fall-through
        // the active profile is already the grown-up one, so asking it whether we
        // may leave a Kids Profile answers "there is no Kids Profile here".
        if profiles.requiresParentalPIN(
            switchingFrom: gate.parentalFallThrough ?? profiles.activeProfile,
            to: target
        ) {
            gate.parentalSwitch = ParentalSwitchRequest(target: target)
            return
        }
        continueSelect(target)
    }

    /// The switch past the parental gate, still subject to the target's own lock.
    private func continueSelect(_ target: Profile) {
        if target.isLocked,
           target.id != profiles.activeProfileID || !profiles.isProfileUnlocked(target.id) {
            gate.lockedSwitch = ParentalSwitchRequest(target: target)
            return
        }
        performSelectProfile(target.id)
    }

    /// Checks `pin` against the household Parental PIN and lets the held switch
    /// continue. Deliberately not remembered for the run — see the tvOS twin.
    @discardableResult
    func submitParentalPIN(_ pin: String) -> Bool {
        guard let target = gate.parentalSwitch?.target else { return false }
        guard profiles.matchesParentalPIN(pin) else {
            gate.parentalSwitch?.error = ProfileLockCopy.incorrectPIN
            return false
        }
        gate.parentalSwitch = nil
        continueSelect(target)
        return true
    }

    /// Abandons a held switch, leaving the child where they were.
    func cancelParentalSwitch() {
        plexOnboardingSelection = nil
        // Deliberately does NOT clear `parentalFallThrough`: cancelling a switch
        // the child never asked for must not hand them the profile they were
        // dropped into.
        gate.parentalSwitch = nil
    }

    /// Checks `pin` against the pending profile's lock, completing the held-back
    /// switch on a match.
    @discardableResult
    func submitProfileLockPIN(_ pin: String) async -> Bool {
        guard let request = gate.lockedSwitch, let lock = request.target.lock else { return false }
        let selection = profiles.selectionGeneration
        let matches = await lock.matchesOffMainActor(pin: pin)
        guard !Task.isCancelled, gate.lockedSwitch?.id == request.id,
              profiles.selectionGeneration == selection else { return false }
        guard profiles.profiles.first(where: { $0.id == request.target.id })?.lock == lock else {
            gate.lockedSwitch?.error = ProfileLockCopy.profileChanged
            return false
        }
        guard matches else {
            gate.lockedSwitch?.error = ProfileLockCopy.incorrectPIN
            return false
        }
        gate.lockedSwitch = nil
        if lock.matchesPlexPIN {
            plexHomeUsers.prefillPlexPIN(pin, forProfile: request.target.id)
        }
        performSelectProfile(request.target.id, unlocking: lock)
        return true
    }

    /// Abandons a pending unlock, leaving the active profile untouched.
    func cancelProfileLockPrompt() {
        plexOnboardingSelection = nil
        gate.lockedSwitch = nil
    }

    /// Sets or clears a profile's PIN gate, dropping any unlock credit the
    /// previous PIN granted.
    func setLock(_ lock: ProfileLock?, forProfile id: String) {
        guard var profile = profiles.profiles.first(where: { $0.id == id }) else { return }
        profile.replaceLock(with: lock)
        profiles.update(profile)
        // Drop any unlock the OLD PIN granted, then re-grant it when a new PIN
        // was just chosen: whoever typed it demonstrably knows it.
        profiles.forgetProfileUnlock(id)
        if lock != nil { profiles.noteProfileUnlocked(id) }
    }

    /// Whether a profile's PIN has been proved since the last profile change.
    func isUnlockedThisRun(_ id: String) -> Bool {
        profiles.isProfileUnlocked(id)
    }

    /// Records that a profile's PIN was proved outside `submitProfileLockPIN` —
    /// e.g. to edit it. Knowing the PIN is knowing the PIN.
    func noteUnlocked(_ id: String) {
        profiles.noteProfileUnlocked(id)
    }

    /// Marks a profile as restricted, or lifts the restriction.
    func setKidsProfile(_ isKids: Bool, forProfile id: String) {
        guard var profile = profiles.profiles.first(where: { $0.id == id }) else { return }
        profile.isKids = isKids
        profiles.update(profile)
    }

    /// Forces the profile picker with no way past it.
    ///
    /// The iOS counterpart of tvOS's non-cancelable `isChoosingProfile`. The PIN
    /// cover alone isn't a gate: it has a Cancel button, and cancelling it while
    /// a locked profile is already active simply reveals that profile. The picker
    /// behind it is what makes cancelling harmless — there's nothing to cancel
    /// *into*.
    private(set) var mustChooseProfile = false

    /// Raises the PIN gate if the profile that just became active is locked and
    /// unproven this run.
    ///
    /// `selectProfile(_:)` gates the deliberate route, but the store also
    /// re-points `activeProfileID` on its own — deleting the active profile falls
    /// through to whichever is left, and a deletion arriving over sync does the
    /// same with no user action at all. Landing that way skipped the gate
    /// entirely, so deleting a profile could drop you straight inside a locked
    /// one. The prompt has no "cancel into the profile" path: dismissing it
    /// returns to the picker.
    /// - Returns: `true` when the gate was raised, meaning the caller must NOT
    ///   go on to scope this profile in — applying its Plex identity or importing
    ///   its watchlist before anyone has proved the PIN is most of what the lock
    ///   is supposed to withhold.
    /// - Parameter leaving: the profile that was active before the fall-through,
    ///   when the caller knows it. A deleted Kids Profile drops the device into
    ///   whatever profile is left — a route out of the child's profile that never
    ///   passes `selectProfile`'s parental gate. The lock check below can't catch
    ///   it, because the whole point of the Parental PIN is that grown-up
    ///   profiles no longer need individual locks.
    @discardableResult
    func enforceActiveProfileLock(leaving outgoing: Profile? = nil) -> Bool {
        if let outgoing,
           profiles.requiresParentalPIN(switchingFrom: outgoing, to: profiles.activeProfile) {
            // Held for the whole episode, not just this call: `activeProfile` is
            // already the grown-up, so every predicate derived from it would
            // stand aside — including the picker's Add/Edit gate.
            gate.parentalFallThrough = outgoing
            mustChooseProfile = true
            gate.parentalSwitch = ParentalSwitchRequest(target: profiles.activeProfile)
            return true
        }
        guard activeProfileNeedsUnlock else { return false }
        mustChooseProfile = true
        gate.lockedSwitch = ParentalSwitchRequest(target: profiles.activeProfile)
        return true
    }

    func performSelectProfile(_ id: String, unlocking lock: ProfileLock? = nil) {
        let onboarding = plexOnboardingSelection?.id == id ? plexOnboardingSelection : nil
        plexOnboardingSelection = nil
        universalWatchlistRetryScheduler = nil
        profiles.select(id)
        // `select` NO-OPS for an id this device doesn't have — a peer can delete
        // a profile between the picker rendering and the tap, which is exactly
        // the fall-through case. Releasing the hold and lifting the forced picker
        // on a switch that never happened would leave the child in the grown-up
        // profile the gate exists to withhold, so everything below is conditional
        // on the switch having actually landed.
        guard profiles.activeProfileID == id else { return }
        if onboarding != nil, profileOnboardingID != nil {
            profileOnboardingID = profiles.activeProfile.needsSetup ? id : nil
            profileOnboardingStep = profiles.activeProfile.needsSetup ? .libraries : nil
        }
        if let lock, profiles.activeProfile.lock == lock { profiles.noteProfileUnlocked(id) }
        TouchFeedback.shared.invalidatePendingConfirmations()
        plexHomeUsers.beginExplicitProfileActivation()
        // Past both gates, so the hold has done its job. Released here rather
        // than on PIN success so that switching into another Kids Profile (which
        // needs no PIN) also releases it.
        gate.parentalFallThrough = nil
        // The launch picker is satisfied by an ACTUAL switch, never by the tap
        // that merely asked for one: tapping a locked profile only raises its
        // PIN, so marking completion at the tap let a cancel fall straight
        // through into the profile the lock was protecting.
        gate.didCompleteLaunchSelection = true
        // Reached only past the lock gate, so this is where the forced picker
        // lifts: a profile has been chosen and proved.
        mustChooseProfile = false
        // Switching INTO a profile that never finished setup — abandoned here, or
        // created on another device and synced across — asks the question again
        // rather than leaving it permanently unable to import. Deferred by a
        // runloop turn for the same reason creation is: this can run from inside
        // a sheet that has to close first.
        if onboarding == nil {
            Task { @MainActor in
                await Task.yield()
                resumeProfileOnboardingIfNeeded()
            }
        }
        refreshActiveProfileConfiguration(deferPlexIdentity: onboarding != nil && lock?.matchesPlexPIN != true)
        onboarding?.onActivated()
    }

    func refreshActiveProfileSettings() {
        settings = PlozziOSSettingsModel(
            namespace: profiles.activeNamespace,
            allowsDiscovery: { [profiles] in !profiles.activeProfile.isKids }
        )
        seriesTrackStore = SeriesTrackPreferenceStore(
            namespace: profiles.activeNamespace
        )
        versionPreferences = VersionPreferenceStore(
            namespace: profiles.activeNamespace
        )
    }

    /// Reapply settings and reconcile sources without granting a new profile
    /// activation or discarding an unchanged Plex authentication in progress.
    func refreshActiveProfileConfiguration() {
        refreshActiveProfileConfiguration(deferPlexIdentity: false)
    }

    private func refreshActiveProfileConfiguration(deferPlexIdentity: Bool) {
        refreshActiveProfileSettings()
        transitionDownloads(to: profiles.activeProfileID)
        reloadAccountsAndHeroCache()
        if !deferPlexIdentity { plexHomeUsers.ensurePlexIdentityForActiveProfile() }
        identityIndex.reset()
        if !isOfflineMode { identityIndex.warmIdentityIndex() }
        drainWatchOutbox()
        Task { @MainActor in
            await prepareUniversalWatchlist()
        }

    }

    @discardableResult
    private func transitionDownloads(to profileID: String) -> Task<Void, Never> {
        if isOfflineMode { accountsProviders.localProviders = [:] }
        pendingDownloadSelection = nil
        let outgoing = downloads
        outgoing.beginProfileTransition()
        downloads = PlozziOSDownloadsModel(
            initializationError: "Switching download profiles."
        )
        downloadProfileGeneration &+= 1
        let generation = downloadProfileGeneration
        return Task { @MainActor [weak self] in
            await outgoing.quiesceForProfileSwitch()
            guard let self,
                  self.downloadProfileGeneration == generation,
                  self.profiles.activeProfileID == profileID else {
                return
            }
            self.downloads = Self.makeDownloadsModel(
                namespace: profileID,
                durableStore: self.durableLocalStateStore,
                mediaShareRuntime: self.mediaShareRuntime,
                accountsProviders: self.accountsProviders,
                settingsNamespace: self.profiles.activeNamespace,
                startsActive: self.applicationIsActive,
                authenticatedHTTPResolver: self.authenticatedHTTPResolver,
                statusPresenter: self.transientStatusPresenter
            )
            self.refreshOfflineProviders()
        }
    }

    private func makeLibraryActionFeedback(
        onCompletion event: TouchFeedback.Event = .confirmation
    ) -> @MainActor @Sendable () -> Void {
        let profileID = profiles.activeProfileID
        return TouchFeedback.shared.acknowledgeAction(onCompletion: event) { [weak self] in
            self?.profiles.activeProfileID == profileID
        }
    }

    private func applyWatchMutation(
        _ mutation: WatchMutation,
        confirmsUserAction: Bool = false
    ) {
        let confirmation = confirmsUserAction && mutation.played != nil ? makeLibraryActionFeedback() : nil
        let mutation = mutation.bindingServerScope(accountsProviders.watchMutationServerScope)
        let reconciler = watchReconciler
        let capturedDownloads = downloads
        Task {
            await reconciler.enqueue(mutation) {
                Task { @MainActor in
                    await capturedDownloads.applyWatchMutation(mutation)
                    confirmation?()
                }
            }
            await reconciler.drain()
        }
    }

    /// Kept by the presentation across teardown/episode handoff, never rebuilt
    /// from whichever profile is visible when a delayed callback arrives.
    struct PlaybackSession: Sendable {
        let profileID: String
        let namespace: String?
        let serverAuthorization: String
        let serverScope: WatchMutationServerScope
        let primaryAccountID: String?
        let initialSnapshot: IdentityIndexSnapshot
        let reconciler: WatchStateReconciler
        let downloads: PlozziOSDownloadsModel
    }

    func makePlaybackSession() -> PlaybackSession {
        let namespace = profiles.activeNamespace
        return PlaybackSession(
            profileID: profiles.activeProfileID,
            namespace: namespace,
            serverAuthorization: accountsProviders.playbackAuthorizationID,
            serverScope: accountsProviders.watchMutationServerScope,
            primaryAccountID: accountsProviders.primaryActiveAccount?.id,
            initialSnapshot: identityIndex.identitySnapshotStore.current,
            reconciler: watchReconciler,
            downloads: downloads
        )
    }

    func externalPlaybackContext() -> ExternalPlaybackContext {
        ExternalPlaybackContext(
            profileID: profiles.activeProfileID,
            authorizationID: accountsProviders.playbackAuthorizationID,
            accounts: accountsProviders.resolvedActiveAccounts,
            isAuthorized: isActiveProfileAuthorized,
            resolver: authenticatedHTTPResolver,
            offlineResolver: downloads.offlineResolver,
            networkFileResolver: mediaShareRuntime.networkFileResolver
        )
    }

    func finishExternalPlayback(_ result: ExternalPlaybackCompletion) async throws {
        guard isActiveProfileAuthorized else { throw CancellationError() }
        guard var mutation = WatchMutationFactory.playbackStop(
                item: result.item, position: result.position, watchedPercent: result.watchedPercent,
                primaryAccountID: result.item.sourceAccountID,
                additionalSources: identityIndex.identitySnapshotStore.current.sourceRefs(for: result.item),
                crossServerSync: settings.playback.settings.syncWatchAcrossServers
              )?.bindingServerScope(accountsProviders.watchMutationServerScope) else { return }
        mutation.id = result.id
        mutation.capturedAt = result.reportedAt
        let identity = externalPlaybackContext().identity
        guard try await result.enqueue(mutation, using: watchReconciler),
              externalPlaybackContext().identity == identity else { return }
        await downloads.applyWatchMutation(mutation)
        publishPlaybackMutation(mutation, item: result.item, watchedPercent: result.watchedPercent)
    }

    func isCurrentPlaybackSession(_ session: PlaybackSession) -> Bool {
        profiles.activeProfileID == session.profileID
            && accountsProviders.playbackAuthorizationID == session.serverAuthorization
            && accountsProviders.watchMutationServerScope == session.serverScope
    }

    private func playbackSources(for item: MediaItem, session: PlaybackSession) -> [MediaSourceRef] {
        let snapshot = isCurrentPlaybackSession(session)
            ? identityIndex.identitySnapshotStore.current
            : session.initialSnapshot
        return snapshot.sourceRefs(for: item)
    }

    func beginPlayback(for item: MediaItem, session: PlaybackSession) {
        guard let accountID = item.sourceAccountID
            ?? session.primaryAccountID else {
            return
        }
        let reconciler = session.reconciler
        Task {
            await reconciler.beginLiveSession(
                accountID: accountID,
                itemID: item.id,
                serverScope: session.serverScope
            )
        }
    }

    func checkpointPlayback(
        for item: MediaItem,
        session: PlaybackSession,
        position: TimeInterval,
        watchedPercent: Double
    ) {
        guard let mutation = WatchMutationFactory.playbackStop(
            item: item,
            position: position,
            watchedPercent: watchedPercent,
            primaryAccountID: session.primaryAccountID,
            additionalSources: playbackSources(for: item, session: session),
            crossServerSync: PlaybackSettingsStore.currentSyncAcrossServers(namespace: session.namespace)
        )?.bindingServerScope(session.serverScope) else {
            return
        }
        let reconciler = session.reconciler
        let capturedDownloads = session.downloads
        Task {
            await reconciler.enqueue(mutation) {
                Task { await capturedDownloads.applyWatchMutation(mutation) }
            }
            await reconciler.drain()
        }
    }

    func finishPlayback(
        for item: MediaItem,
        session: PlaybackSession,
        position: TimeInterval,
        watchedPercent: Double
    ) {
        let accountID = item.sourceAccountID
            ?? session.primaryAccountID
        let mutation = WatchMutationFactory.playbackStop(
            item: item,
            position: position,
            watchedPercent: watchedPercent,
            primaryAccountID: session.primaryAccountID,
            // The eager identity index's known servers for this title. Without
            // it the fan-out only covers the item's own `sources`, so a title
            // reached from a Home row that only one server populated never gets
            // marked played on the OTHER servers that also have it — silent,
            // invisible data loss. tvOS has always passed this.
            additionalSources: playbackSources(for: item, session: session),
            crossServerSync: PlaybackSettingsStore.currentSyncAcrossServers(namespace: session.namespace)
        )?.bindingServerScope(session.serverScope)
        if isCurrentPlaybackSession(session) {
            publishPlaybackMutation(
                mutation,
                item: item,
                watchedPercent: watchedPercent
            )
        }
        let reconciler = session.reconciler
        let capturedDownloads = session.downloads
        Task {
            await reconciler.finishLiveSession(
                accountID: accountID, itemID: item.id, mutation: mutation, serverScope: session.serverScope
            ) {
                if let mutation {
                    Task { await capturedDownloads.applyWatchMutation(mutation) }
                }
            }
        }
    }

    private func publishPlaybackMutation(
        _ mutation: WatchMutation?,
        item: MediaItem,
        watchedPercent: Double
    ) {
        guard let mutation else { return }
        let targets = mutation.effectiveOptimisticTargets
        guard !targets.isEmpty else { return }
        var itemIDs = Set(targets.map(\.itemID))
        itemIDs.insert(item.id)
        MediaItemMutation(
            itemIDs: itemIDs,
            scopedItemIDs: Set(targets.map(\.id)),
            played: mutation.played,
            resumePosition: mutation.resumePosition,
            playedPercentage: mutation.played == true
                ? 1
                : max(0, min(1, watchedPercent / 100)),
            item: item
        ).post()
    }

    private func drainWatchOutbox() {
        guard !isOfflineMode else { return }
        let reconciler = watchReconciler
        Task { await reconciler.drain() }
    }

    func retryWatchOutboxIfAllowed() {
        guard applicationIsActive, isActiveProfileAuthorized,
              watchOutboxConnectivity.isConnected else { return }
        drainWatchOutbox()
    }

    func pendingWatchMutations() async -> [WatchMutation] {
        let profileID = profiles.activeProfileID
        let pending = await watchReconciler.snapshot().pending
        guard profiles.activeProfileID == profileID else { return [] }
        return pending.filter {
            accountsProviders.isCurrentWatchMutationServerScope(
                $0.serverScope, isPlexIdentityResolved: plexHomeUsers.hasResolvedWatchMutationIdentity
            )
        }
    }

    func appliedWatchRecency() async -> [String: AppliedResumeRecord] {
        let profileID = profiles.activeProfileID
        let recency = await watchReconciler.snapshot().appliedRecency
        guard profiles.activeProfileID == profileID else { return [:] }
        return recency.filter {
            accountsProviders.isCurrentWatchMutationServerScope(
                $0.value.serverScope, isPlexIdentityResolved: plexHomeUsers.hasResolvedWatchMutationIdentity
            )
        }
    }

    private func makeWatchReconciler(profileID: String) -> WatchStateReconciler {
        let profile = profiles.profiles.first { $0.id == profileID } ?? profiles.activeProfile
        let namespace = profile.settingsNamespace(isDefault: profiles.isDefault(profile))
        let store: any WatchMutationStoring
        if let durableLocalStateStore {
            do {
                store = try DurableWatchMutationStore(
                    store: durableLocalStateStore,
                    profileID: profileID,
                    onLoadFailure: {
                        PlozzLog.app.error(
                            "iOS durable watch outbox unavailable; preserving corrupt state"
                        )
                    }
                )
            } catch {
                PlozzLog.app.error(
                    "iOS durable watch outbox address invalid; using memory only"
                )
                store = InMemoryWatchMutationStore()
            }
        } else {
            store = InMemoryWatchMutationStore()
        }
        let applier = AppShellWatchMutationApplier(
            isActive: { [weak self] in
                await MainActor.run {
                    self?.profiles.activeProfileID == profileID && self?.isOfflineMode == false
                }
            },
            validateServerScope: { [weak self] scope in
                try await MainActor.run {
                    guard let self else { throw WatchMutationServerScopeError.unavailable }
                    try self.accountsProviders.requireWatchMutationServerScope(
                        scope, isPlexIdentityResolved: self.plexHomeUsers.hasResolvedWatchMutationIdentity
                    )
                }
            },
            resolveProvider: { [weak self] accountID in
                await MainActor.run {
                    guard let self, self.profiles.activeProfileID == profileID else { return nil }
                    return self.accountsProviders.provider(
                        forWatchMutationAccountID: accountID,
                        isPlexIdentityResolved: self.plexHomeUsers.hasResolvedWatchMutationIdentity
                    )
                }
            },
            allAccountIDs: { [weak self] in
                await MainActor.run {
                    guard let self, self.profiles.activeProfileID == profileID else { return [] }
                    if let scope = WatchMutationDeliveryAuthorization.current?.serverScope {
                        do {
                            try self.accountsProviders.requireWatchMutationServerScope(
                                scope, isPlexIdentityResolved: self.plexHomeUsers.hasResolvedWatchMutationIdentity
                            )
                            return scope.accounts.map(\.accountID)
                        } catch { return [] }
                    }
                    return self.accountsProviders.homeAccounts.map(\.account.id)
                }
            },
            indexedSeriesSources: {
                [identitySnapshotStore = identityIndex.identitySnapshotStore]
                originSeries in
                identitySnapshotStore.current.sources(for: originSeries)
                    .filter { $0.kind == .series }
            },
            indexedSources: {
                [identitySnapshotStore = identityIndex.identitySnapshotStore]
                identities, kind, anchorTitle, anchorYear, rejectedSourceIDs in
                identitySnapshotStore.current.sources(
                    forIdentities: identities,
                    kind: kind,
                    anchorTitle: anchorTitle,
                    anchorYear: anchorYear,
                    rejectedSourceIDs: rejectedSourceIDs
                )
            },
            indexedAccountIDs: {
                [identitySnapshotStore = identityIndex.identitySnapshotStore] in
                identitySnapshotStore.current.indexedAccountIDs
            }
        )
        return WatchStateReconciler(
            store: store,
            applier: applier,
            onPersistenceFailure: {
                PlozzLog.app.error("iOS durable watch outbox write failed")
            },
            onServerStateApplied: { [weak self] mutation in
                guard let refresh = MediaItemMutation(confirmedWatchMutation: mutation) else { return }
                Task { @MainActor in
                    guard let self, self.profiles.activeProfileID == profileID else { return }
                    if let scope = mutation.serverScope {
                        do {
                            try self.accountsProviders.requireWatchMutationServerScope(
                                scope, isPlexIdentityResolved: self.plexHomeUsers.hasResolvedWatchMutationIdentity
                            )
                        } catch { return }
                    }
                    refresh.post()
                }
            },
            automaticRetryAllowed: { [weak self] in
                await MainActor.run {
                    guard let self else { return false }
                    return !self.isOfflineMode && self.applicationIsActive && self.isActiveProfileAuthorized
                        && self.profiles.activeProfileID == profileID
                        && self.watchOutboxConnectivity.isConnected
                }
            }
        )
    }

    private static func makeDownloadsModel(
        namespace: String,
        durableStore: DurableLocalStateStore?,
        mediaShareRuntime: DefaultMediaShareRuntime,
        accountsProviders: AccountsProvidersModel,
        settingsNamespace: String?,
        startsActive: Bool = true,
        authenticatedHTTPResolver: ManagedAuthenticatedHTTPResolver,
        statusPresenter: TransientStatusPresenter
    ) -> PlozziOSDownloadsModel {
        guard let durableStore else {
            return PlozziOSDownloadsModel(
                profileID: namespace,
                initializationError: "Durable download storage is unavailable."
            )
        }
        // Read current preferences at download preparation time, not a settings
        // model that a same-profile cloud update can replace.
        let playbackStore = PlaybackSettingsStore(namespace: settingsNamespace)
        let audioPolicyStore = AudioPolicyStore(namespace: settingsNamespace)
        let artworkStore = ArtworkSettingsStore(namespace: settingsNamespace)
        do {
            let model = PlozziOSDownloadsModel(
                profileID: namespace,
                registry: DownloadedMediaRegistry(store: try DurableDownloadedMediaStore(
                    store: durableStore, profileID: namespace
                )),
                storage: PlatformDownloadStorageLocator(subdirectory: "PlozzDownloads/\(namespace)"),
                networkFileResolver: mediaShareRuntime.networkFileResolver,
                providerKind: { accountID in
                    accountsProviders.accounts.first {
                        $0.id == accountID
                    }?.server.provider
                },
                sourceUserID: { accountID in
                    accountsProviders.downloadUserID(for: accountID, profileID: namespace)
                },
                preferredAudioLanguages: { item in
                    let playbackSettings = playbackStore.load()
                    let policy = audioPolicyStore.resolvedPolicy(
                        settings: playbackSettings
                    )
                    return AudioLanguagePolicy.preferredAudioLanguages(
                        remembered: nil,
                        preference: policy.effectivePreference(
                            for: ContentClassifier.audioCategory(for: item)
                        ),
                        originalLanguage:
                            ContentClassifier.originalAudioLanguage(for: item),
                        deviceLanguage: LanguageMatch.deviceLanguageCode
                    )
                },
                artworkSettings: { artworkStore.load() },
                startsActive: startsActive,
                resolveArtworkItem: { record in
                    guard let accountID = record.snapshot.sourceAccountID
                        ?? record.managedHTTPSource?.accountID
                        ?? record.directShareSource?.accountID,
                          let itemID = record.snapshot.sourceItemID ?? record.managedHTTPSource?.itemID,
                          let provider = accountsProviders.provider(forAccountID: accountID) else { return nil }
                    return try await provider.item(id: itemID).taggingSource(accountID)
                },
                managedURLResolver: {
                    source,
                    sourceUserID,
                    updateSource,
                    updatePreparationProgress in
                    let provider: (any MediaProvider)? = await MainActor.run {
                        guard accountsProviders.accounts.first(where: {
                            $0.id == source.accountID
                        })?.server.provider == source.provider else {
                            return nil
                        }
                        return accountsProviders.provider(
                            forAccountID: source.accountID
                        )
                    }
                    guard let provider else {
                        throw MediaTransportError.authentication(
                            reason: "inactive managed download account"
                        )
                    }
                    if source.provider == .emby, source.includesAllAudioTracks,
                       source.quality != .original {
                        guard let sourceUserID else { throw CancellationError() }
                        let authorize: @Sendable () async throws -> Void = {
                            try Task.checkCancellation()
                            let permitted = await MainActor.run {
                                !OfflineMode.shared.isEnabled
                                    && accountsProviders.downloadUserID(
                                        for: source.accountID, profileID: namespace
                                    ) == sourceUserID
                            }
                            guard permitted else { throw CancellationError() }
                        }
                        return try await EmbyOfflineAudioDownload.prepare(
                            source: source, authorize: authorize,
                            provider: {
                                try await authorize()
                                let current = await MainActor.run {
                                    accountsProviders.provider(forAccountID: source.accountID) as? JellyfinProvider
                                }
                                guard let current, current.kind == .emby else { throw AppError.unauthorized }
                                return current
                            },
                            resolve: { try await authenticatedHTTPResolver.resolve($0) },
                            updateSource: updateSource
                        )
                    }
                    if let silo = provider as? SiloProvider {
                        do {
                            return try await SiloOfflineDownload.prepare(
                                provider: silo, source: source, updateSource: updateSource)
                        } catch let error as AppError {
                            throw PlozziOSDownloadError.nativeServer(error.userMessage)
                        }
                    }
                    let playback = try await provider.playbackInfo(
                        for: source.itemID,
                        mediaSourceID: source.mediaSourceID,
                        forceTranscode: source.quality != .original
                    )
                    if case .constrained(let constraint) = source.quality {
                        let streamURL: URL
                        if case .authenticatedHTTP(let locator) =
                            playback.playbackSource {
                            streamURL = try await authenticatedHTTPResolver.resolve(
                                locator
                            )
                        } else if let legacyURL = playback.streamURL {
                            streamURL = legacyURL
                        } else {
                            throw MediaTransportError.unsupportedCapability(
                                "This server did not provide an offline rendition."
                            )
                        }
                        guard
                              var components = URLComponents(
                                url: streamURL,
                                resolvingAgainstBaseURL: false
                              ) else {
                            throw MediaTransportError.unsupportedCapability(
                                "This server did not provide an offline rendition."
                            )
                        }
                        var items = components.queryItems ?? []
                        func setQueryItem(_ name: String, _ value: String) {
                            items.removeAll {
                                $0.name.caseInsensitiveCompare(name) == .orderedSame
                            }
                            items.append(URLQueryItem(name: name, value: value))
                        }
                        switch source.provider {
                        case .plex:
                            let audioStreamID = playback.audioTracks.first {
                                track in
                                source.preferredAudioLanguages.contains {
                                    preferred in
                                    Self.languagesMatch(
                                        preferred,
                                        track.language
                                    )
                                }
                            }?.id
                                ?? playback.audioTracks.first {
                                    $0.isDefault
                                }?.id
                                ?? playback.audioTracks.first?.id
                            let textSubtitleStreamID = playback.subtitleTracks
                                .first {
                                    $0.isDefault && !$0.isImageBasedSubtitle
                                }?.id
                                ?? playback.subtitleTracks.first {
                                    !$0.isImageBasedSubtitle
                                }?.id
                            guard let constrainedURL =
                                    PlexOfflineTranscodeURLBuilder.makeURL(
                                        from: streamURL,
                                        maximumVideoBitrateBps:
                                            constraint.maximumVideoBitrateBps,
                                        maximumHeight: constraint.maximumHeight,
                                        audioStreamID: audioStreamID,
                                        textSubtitleStreamID:
                                            textSubtitleStreamID,
                                        includesTextSubtitle:
                                            source.includesTextSubtitleTracks,
                                        includesAllAudioTracks:
                                            source.includesAllAudioTracks
                                    ) else {
                                throw MediaTransportError.unsupportedCapability(
                                    "This Plex server did not provide a compatible offline rendition."
                                )
                            }
                            return try await PlexOfflineDownloadQueue.prepare(
                                progressiveURL: constrainedURL,
                                source: source,
                                expectedDuration: playback.item.runtime,
                                expectedAudioLanguages: source.includesAllAudioTracks
                                    ? playback.audioTracks.map(\.language) : nil,
                                updateSource: updateSource,
                                updatePreparationProgress:
                                    updatePreparationProgress
                            )
                        case .jellyfin, .emby:
                            if let audioStreamID = playback.audioTracks.first(
                                where: { track in
                                    source.preferredAudioLanguages.contains {
                                        Self.languagesMatch(
                                            $0,
                                            track.language
                                        )
                                    }
                                }
                            )?.id {
                                setQueryItem(
                                    "AudioStreamIndex",
                                    String(audioStreamID)
                                )
                            }
                            setQueryItem(
                                "VideoBitrate",
                                String(constraint.maximumVideoBitrateBps)
                            )
                            setQueryItem(
                                "MaxHeight",
                                String(constraint.maximumHeight)
                            )
                        default:
                            throw MediaTransportError.unsupportedCapability(
                                "This server cannot create reduced-quality downloads."
                            )
                        }

                        components.queryItems = items
                        guard let constrainedURL = components.url else {
                            throw MediaTransportError.unsupportedCapability(
                                "The offline rendition URL was invalid."
                            )
                        }
                        return .init(
                            url: constrainedURL,
                            expectedDuration: playback.item.runtime,
                            cleanupURL: nil
                        )
                    }
                    guard case .authenticatedHTTP(let locator) =
                            playback.downloadableOriginalSource,
                          locator.deliveryMode == .directFile else {
                        throw MediaTransportError.unsupportedCapability(
                            "managed background download requires a direct file"
                        )
                    }
                    return .init(
                        url: try await authenticatedHTTPResolver.resolve(locator),
                        expectedDuration: playback.item.runtime,
                        cleanupURL: nil
                    )
                },
                saveSubtitles: { record, destination, policy in
                    guard let accountID = record.managedHTTPSource?.accountID ?? record.directShareSource?.accountID,
                          let userID = record.snapshot.sourceUserID else { throw CancellationError() }
                    let authorize: @Sendable () async throws -> Void = {
                        try Task.checkCancellation()
                        let authorized = await MainActor.run {
                            !OfflineMode.shared.isEnabled
                                && accountsProviders.downloadUserID(for: accountID, profileID: namespace) == userID
                        }
                        guard authorized else { throw CancellationError() }
                    }
                    try await authorize()
                    let provider = await MainActor.run { accountsProviders.provider(forAccountID: accountID) }
                    guard let provider else { throw AppError.unauthorized }
                    return try await PlozziOSOfflineSubtitles.save(
                        record: record, destination: destination, policy: policy, provider: provider,
                        authorize: authorize, resolve: { try await authenticatedHTTPResolver.resolve($0) }
                    )
                },
                managedRemoval: { source in
                    guard source.provider == .silo, let saved = source.preparationReference,
                          saved.queueIdentifier.hasPrefix("silo:"),
                          let revision = Int(saved.queueIdentifier.dropFirst(5)) else { throw AppError.invalidResponse }
                    let provider = await MainActor.run {
                        accountsProviders.provider(forAccountID: source.accountID) as? SiloProvider
                    }
                    guard let provider else { throw AppError.unauthorized }
                    try await provider.removeDownload(.init(id: saved.itemIdentifier, revision: revision))
                },
                managedCompletion: { source, timestamp in
                    guard source.provider == .silo, let saved = source.preparationReference,
                          saved.queueIdentifier.hasPrefix("silo:"),
                          let revision = Int(saved.queueIdentifier.dropFirst(5)) else { throw AppError.invalidResponse }
                    let provider = await MainActor.run {
                        accountsProviders.provider(forAccountID: source.accountID) as? SiloProvider
                    }
                    guard let provider else { throw AppError.unauthorized }
                    try await provider.reportDownload(.init(id: saved.itemIdentifier, revision: revision),
                                                      status: "completed", at: timestamp)
                }
            )
            model.statusPresenter = statusPresenter
            return model
        } catch {
            return PlozziOSDownloadsModel(
                profileID: namespace,
                initializationError: error.localizedDescription
            )
        }
    }

    nonisolated private static func languagesMatch(
        _ preferred: String,
        _ candidate: String?
    ) -> Bool {
        LanguageMatch.matches(preferred, candidate)
    }

    /// Creates or updates a profile from a shared `ProfileEditorView` draft —
    /// the single draft-based persistence path shared with tvOS. Cosmetic fields
    /// (name, avatar symbol/emoji/photo, colours) are written through; every
    /// non-cosmetic field (linked account, Plex Home bindings,
    /// active-account subset) is preserved. A new profile is seeded with the
    /// current household accounts, selected, and handed to the first-run theme
    /// step — mirroring the previous `addProfile` behaviour.
    /// - Parameter isKids: whether a NEWLY created profile is a Kids Profile.
    ///   Ignored when editing, where the flag is owned by the profile's own
    ///   settings page. Matches the tvOS picker, which has always been able to
    ///   create one directly.
    func saveProfile(_ draft: ProfileDraft, isKids: Bool = false) {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let id = draft.id {
            guard var profile = profiles.profiles.first(where: { $0.id == id }) else {
                return
            }
            // Cosmetics from the editor…
            profile.name = trimmed
            profile.avatarSymbol = draft.avatarSymbol
            profile.colorIndex = draft.colorIndex
            profile.avatarImageURL = draft.avatarImageURL
            profile.avatarEmoji = draft.avatarEmoji
            profile.avatarEmojiColorIndex = draft.avatarEmojiColorIndex
            // …plus the preserved non-cosmetic fields the draft carried through
            // unchanged, so an edit never wipes Plex Home bindings / linked
            // accounts. Membership (`activeAccountIDs`) is intentionally NOT
            // touched here — the editor sends it empty to mean "leave alone."
            profile.linkedAccountID = draft.linkedAccountID
            profile.plexHomeUserID = draft.plexHomeUserID
            profile.plexHomeUserName = draft.plexHomeUserName
            profile.plexHomeUserAccountID = draft.plexHomeUserAccountID
            profile.plexHomeUserRequiresPIN = draft.plexHomeUserRequiresPIN
            profile.plexHomeUserAvatarURL = draft.plexHomeUserAvatarURL
            profile.plexHomeUserBindings = draft.plexHomeUserBindings
            profiles.update(profile)
        } else {
            // Created AWAITING SETUP, exactly as on tvOS. A new profile inherits
            // every server, so importing a watchlist before the user has said
            // which servers it uses — and who it watches as on them — drops the
            // household's aggregate watchlist into it. `addAwaitingSetup` gates
            // the import until `advanceProfileOnboarding` releases it.
            let created = profiles.addAwaitingSetup(
                draft,
                isKids: isKids,
                activeAccountIDs: accounts.map(\.id)
            )
            // Claimed BEFORE the switch: `performSelectProfile` schedules a
            // deferred resume, and this new profile does need setup, so without
            // the claim already in place that resume would take the flow over and
            // present it from the wrong place. See `resumeProfileOnboardingIfNeeded`.
            profileOnboardingID = created.id
            performSelectProfile(created.id)
            // Yielded, not set inline: this runs from inside the Add Profile
            // sheet, and SwiftUI drops a presentation requested while another is
            // still dismissing. One runloop turn lets the editor close first —
            // the same reason `scheduleFirstRunStep` yields.
            Task { @MainActor in
                await Task.yield()
                profileOnboardingStep = .libraries
            }
        }
    }

    func removeProfile(_ id: String) {
        universalWatchlistRetryScheduler = nil
        let previousActiveProfileID = profiles.activeProfileID
        let outgoingProfile = profiles.activeProfile
        removeMediaAliases(forProfileID: id)
        profiles.remove(id)
        watchReconcilers[id] = nil
        if profiles.activeProfileID != previousActiveProfileID {
            // Deleting the active profile falls the selection through to whatever
            // is left, which can be a LOCKED profile — a route into it that never
            // passes `selectProfile`'s gate. Stop here if so: re-scoping,
            // re-pointing the Plex identity and importing that profile's
            // watchlist is most of what the lock is meant to withhold, and doing
            // it first would mean the PIN only hid a profile that was already
            // open behind it.
            if enforceActiveProfileLock(leaving: outgoingProfile) {
                reloadAccountsAndHeroCache()
                return
            }
            settings = PlozziOSSettingsModel(
                namespace: profiles.activeNamespace,
                allowsDiscovery: { [profiles] in !profiles.activeProfile.isKids }
            )
            seriesTrackStore = SeriesTrackPreferenceStore(
                namespace: profiles.activeNamespace
            )
            versionPreferences = VersionPreferenceStore(
                namespace: profiles.activeNamespace
            )
            transitionDownloads(to: profiles.activeProfileID)
        }
        reloadAccountsAndHeroCache()
        if profiles.activeProfileID != previousActiveProfileID {
            plexHomeUsers.ensurePlexIdentityForActiveProfile()
        }
        identityIndex.reset()
        identityIndex.warmIdentityIndex()
        drainWatchOutbox()
        Task { @MainActor in
            await prepareUniversalWatchlist()
        }
    }

    func activeAccountIDs(for profileID: String) -> Set<String> {
        if profiles.activeProfileID == profileID {
            return accountsProviders.activeAccountIDs
        }
        return Set(
            profiles.activeAccountIDs(
                for: profileID,
                fallback: accountStore.activeAccountIDs()
            )
        )
    }

    func setAccount(_ accountID: String, enabled: Bool, for profileID: String) {
        let previous = activeAccountIDs(for: profileID)
        var ids = previous
        if enabled {
            ids.insert(accountID)
        } else {
            ids.remove(accountID)
        }
        guard ids != previous
            || profiles.storedActiveAccountIDs(for: profileID) == nil
            || profiles.unconfirmedAccountSelectionProfileIDs.contains(profileID)
        else { return }
        profiles.setActiveAccountIDs(Array(ids), for: profileID)
        watchReconcilers[profileID] = nil
        // Noted BEFORE the reload below, which schedules a watchlist import: the
        // whole point is that the import waits for the answer, and a note taken
        // after it has already been scheduled is too late.
        if enabled {
            noteServerAwaitingIdentity(accountID, profileID: profileID)
        } else {
            // Switched back off — there's nothing left to be anyone on, and an
            // unanswerable question would gate the import forever.
            resolveIdentityPrompt(for: accountID)
        }
        if profiles.activeProfileID == profileID {
            // The account set drives what's on screen, so this stays synchronous.
            heroTrailerCache.removeAll()
            accountsProviders.refreshActiveAccountSelection()
            identityIndex.reset()
            // Everything else is bookkeeping, and it was running in the same
            // turn as the toggle — blocking the main actor long enough that the
            // switch's own animation dropped frames and the expanding card
            // appeared to jump. Yield first so the UI settles, then catch up.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.profiles.activeProfileID == profileID else { return }
                self.identityIndex.warmIdentityIndex()
                self.drainWatchOutbox()
            }
        }
    }

    @discardableResult
    func persist(_ sessions: [UserSession]) -> Bool {
        do {
            let existingIDs = Set(accountsProviders.accounts.map(\.id))
            let isFirstRun = existingIDs.isEmpty
                && !profiles.firstRunProfileSetupComplete
            var addedAccounts: [Account] = []
            for session in sessions {
                let registration = try accountStore.registerAuthenticatedSession(session)
                let account = registration.account
                if registration.previousAccount == nil {
                    addedAccounts.append(account)
                }
            }
            let completesAdditionalIdentity = pendingAdditionalUser.map { pending in
                addedAccounts.contains {
                    $0.server.provider.usesMediaBrowserAPI
                        && $0.server.identityKey == pending.serverKey
                }
            } ?? false
            accountError = nil
            reloadAccountsAndHeroCache()
            selectNewlyAddedUserIfNeeded(from: addedAccounts)
            identityIndex.warmIdentityIndex()
            if isFirstRun, let account = addedAccounts.first {
                profiles.seedDefaultProfileIdentity(
                    name: account.userName,
                    avatarImageURL: account.avatarURL?.absoluteString
                )
            }
            if !completesAdditionalIdentity {
                preparePostSignInOnboarding(
                    for: addedAccounts,
                    beginsFirstRun: isFirstRun && !addedAccounts.isEmpty
                )
            }
            return true
        } catch {
            PlozzLog.auth.error("Unable to save authenticated accounts")
            reloadAccountsAndHeroCache()
            accountError = error.localizedDescription
            return false
        }
    }

    func beginAddingUser(on server: MediaServer) {
        pendingAdditionalUser = (
            serverKey: server.identityKey,
            profileID: profiles.activeProfileID
        )
        beginManagedServerPresentation()
    }

    private func selectNewlyAddedUserIfNeeded(from addedAccounts: [Account]) {
        guard let pendingAdditionalUser,
              let account = addedAccounts.last(where: {
                  $0.server.identityKey == pendingAdditionalUser.serverKey
              })
        else { return }

        var selected = activeAccountIDs(for: pendingAdditionalUser.profileID)
        for existing in accountsProviders.accounts
        where existing.server.identityKey == pendingAdditionalUser.serverKey {
            selected.remove(existing.id)
        }
        selected.insert(account.id)
        profiles.setActiveAccountIDs(
            Array(selected),
            for: pendingAdditionalUser.profileID
        )
        watchReconcilers[pendingAdditionalUser.profileID] = nil
        reloadAccountsAndHeroCache()
        self.pendingAdditionalUser = nil
    }

    func selectPlexUserDuringOnboarding(_ user: PlexHomeUser, addAllProfiles: Bool) {
        guard let pending = plexHomeUsers.pendingPlexUserSelection else { return }
        guard plexHomeUsers.selectOnboardingUser(user, addAllProfiles: addAllProfiles) else { return }
        if addAllProfiles, let profileID = plexHomeUsers.importedOnboardingProfileID(for: user) {
            selectProfileForPlexOnboarding(profileID) { [weak self] in
                self?.finishPlexUserOnboarding(user, pending: pending, imported: true)
            }
            return
        }
        finishPlexUserOnboarding(user, pending: pending, imported: false)
    }

    func importPlexHomeProfilesDuringOnboarding() -> PlexHomeProfileImportResult {
        plexHomeUsers.importOnboardingProfiles()
    }

    private func finishPlexUserOnboarding(
        _ user: PlexHomeUser, pending: PlexHomeUsersModel.PendingPlexUserSelection, imported: Bool
    ) {
        if pending.isFirstRun && !imported {
            profiles.seedDefaultProfileIdentity(
                name: user.name,
                avatarImageURL: user.avatarURL?.absoluteString
            )
        }
        appliesPlexIdentityAfterLibrarySelection = true
        plexHomeUsers.clearUserSelection()
        if imported, !pending.isFirstRun, profiles.activeProfile.needsSetup {
            appliesPlexIdentityAfterLibrarySelection = false
            resumeProfileOnboardingIfNeeded()
            plexHomeUsers.ensurePlexIdentityForActiveProfile()
            return
        }
        scheduleLibrarySelection(
            accountIDs: pending.applyToAccountIDs,
            beginsFirstRun: pending.isFirstRun
        )
    }

    func cancelPlexUserSelectionDuringOnboarding() {
        guard let pending = plexHomeUsers.pendingPlexUserSelection else { return }
        plexHomeUsers.clearUserSelection()
        scheduleLibrarySelection(
            accountIDs: pending.applyToAccountIDs,
            beginsFirstRun: pending.isFirstRun
        )
    }

    func beginManagedServerPresentation() {
        postAddPresentationGeneration &+= 1
        plexUserSelectionGeneration &+= 1
        queuedPlexUserSelection = nil
        queuedLibraryAccountIDs = nil
        queuedLibrarySelectionBeginsFirstRun = false
        isManagedServerPresentationActive = true
    }

    func finishManagedServerPresentation() {
        isManagedServerPresentationActive = false
        if let selection = queuedPlexUserSelection {
            queuedPlexUserSelection = nil
            plexHomeUsers.presentUserSelection(selection)
            // Mirrors schedulePlexUserSelection: this drain path bypasses it,
            // so it has to enter the flow itself or the step would present as a
            // bare sheet outside the cover.
            if selection.isFirstRun { pendingFirstRunStep = .plexUser }
        } else if let accountIDs = queuedLibraryAccountIDs {
            let beginsFirstRun = queuedLibrarySelectionBeginsFirstRun
            queuedLibraryAccountIDs = nil
            queuedLibrarySelectionBeginsFirstRun = false
            scheduleLibrarySelection(
                accountIDs: accountIDs,
                beginsFirstRun: beginsFirstRun
            )
        }
        // A dismissed add-user sheet must not make a later unrelated sign-in
        // auto-select itself for this profile.
        pendingAdditionalUser = nil
    }

    func completeLibrarySelection() {
        guard plexHomeUsers.pendingPlexPINRequest == nil else { return }
        pendingLibrarySelection = nil
        if beginsFirstRunAfterLibrarySelection {
            beginsFirstRunAfterLibrarySelection = false
            // Already inside the flow cover, so advance in place. Going through
            // scheduleFirstRunStep would yield a runloop turn to let a sheet
            // dismiss first — which is exactly the gap that flashed Home.
            advanceFirstRunStep(to: .confirmProfile)
        } else if appliesPlexIdentityAfterLibrarySelection {
            appliesPlexIdentityAfterLibrarySelection = false
            plexHomeUsers.ensurePlexIdentityForActiveProfile()
        }
    }

    func confirmFirstRunProfile() {
        advanceFirstRunStep(to: .theme)
    }

    func finishFirstRunThemeSelection() {
        profiles.markFirstRunProfileSetupComplete()
        identityIndex.warmIdentityIndex()
        pendingFirstRunStep = nil
        if appliesPlexIdentityAfterLibrarySelection {
            appliesPlexIdentityAfterLibrarySelection = false
            plexHomeUsers.ensurePlexIdentityForActiveProfile()
        }
    }

    private func preparePostSignInOnboarding(
        for accounts: [Account],
        beginsFirstRun: Bool
    ) {
        plexUserSelectionGeneration &+= 1
        let generation = plexUserSelectionGeneration
        guard let account = accounts.first(where: {
            $0.server.provider == .plex
                && profiles.activeProfile.homeUserBinding(
                    forPlexAccount: $0.id
                ) == nil
        }) else {
            scheduleLibrarySelection(
                accountIDs: accounts.map(\.id),
                beginsFirstRun: beginsFirstRun
            )
            return
        }
        Task {
            let users = await plexHomeUsers.plexHomeUsers(
                forAccountID: account.id
            )
            guard generation == plexUserSelectionGeneration else { return }
            guard users.count >= 2,
                  accountsProviders.accounts.contains(where: {
                      $0.id == account.id
                  }) else {
                scheduleLibrarySelection(
                    accountIDs: accounts.map(\.id),
                    beginsFirstRun: beginsFirstRun
                )
                return
            }
            schedulePlexUserSelection(
                PlexHomeUsersModel.PendingPlexUserSelection(
                    accountID: account.id,
                    serverName: account.server.name,
                    users: users,
                    isFirstRun: beginsFirstRun,
                    applyToAccountIDs: accounts.map(\.id)
                )
            )
        }
    }

    func removeAccount(id: String) {
        let removedAccount = accountsProviders.accounts.first { $0.id == id }
        let shareAccountKey = mediaShareAccountService.mediaShareAccountKey(
            for: removedAccount
        )
        do {
            try accountStore.remove(id: id)
            plexHomeUsers.forgetAccount(id)
            // The "who are you here?" question is persisted and gates the
            // watchlist import. With the account gone nothing can ask it, so an
            // entry left behind would defer every future import forever. Cleared
            // BEFORE the reload, which is what re-triggers preparation. See
            // `withdrawIdentityQuestions(forAccount:)`.
            profiles.withdrawIdentityQuestions(forAccount: id)
            reloadAccountsAndHeroCache()
            identityIndex.reset()
            identityIndex.warmIdentityIndex()
            guard !accountsProviders.accounts.contains(where: { $0.id == id }) else {
                return
            }
            if let removedAccount {
                mediaShareAccountService.retireCredential(for: removedAccount)
            }
            if let shareAccountKey {
                mediaShareAccountService.invalidate(shareAccountKey: shareAccountKey)
            }
            accountError = nil
        } catch {
            accountError = error.localizedDescription
        }
    }

    @discardableResult
    func addNFSShare(
        host: String,
        port: Int?,
        exportPath: String,
        subpath: String = "",
        displayName: String,
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) -> Bool {
        do {
            let prepared = try mediaShareConfigurationService.saveNFS(
                host: host,
                port: port,
                exportPath: exportPath,
                subpath: subpath,
                displayName: displayName,
                libraryConfiguration: libraryConfiguration
            )
            reloadAccountsAndHeroCache()
            identityIndex.warmIdentityIndex()
            preparePostShareOnboarding(prepared)
            accountError = nil
            return true
        } catch {
            accountError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addSMBShare(
        host: String,
        port: Int?,
        share: String,
        username: String,
        password: String,
        displayName: String,
        subpath: String = "",
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) -> Bool {
        do {
            let prepared = try mediaShareConfigurationService.saveSMB(
                host: host,
                port: port,
                share: share,
                username: username,
                password: password,
                displayName: displayName,
                subpath: subpath,
                libraryConfiguration: libraryConfiguration
            )
            reloadAccountsAndHeroCache()
            identityIndex.warmIdentityIndex()
            preparePostShareOnboarding(prepared)
            accountError = nil
            return true
        } catch {
            accountError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addWebDAVShare(
        baseURL: URL,
        auth: MediaShareWebDAVAuth,
        trustPin: SHA256Fingerprint?,
        displayName: String,
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) -> Bool {
        do {
            let prepared = try mediaShareConfigurationService.saveWebDAV(
                baseURL: baseURL,
                auth: auth,
                trustPin: trustPin,
                displayName: displayName,
                libraryConfiguration: libraryConfiguration
            )
            reloadAccountsAndHeroCache()
            identityIndex.warmIdentityIndex()
            preparePostShareOnboarding(prepared)
            accountError = nil
            return true
        } catch {
            accountError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addSFTPShare(
        host: String,
        port: Int?,
        path: String,
        username: String,
        password: String,
        hostKeyPin: SHA256Fingerprint,
        displayName: String,
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) -> Bool {
        do {
            let prepared = try mediaShareConfigurationService.saveSFTP(
                host: host,
                port: port,
                path: path,
                username: username,
                password: password,
                hostKeyPin: hostKeyPin,
                displayName: displayName,
                libraryConfiguration: libraryConfiguration
            )
            reloadAccountsAndHeroCache()
            identityIndex.warmIdentityIndex()
            preparePostShareOnboarding(prepared)
            accountError = nil
            return true
        } catch {
            accountError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addFTPShare(
        baseURL: URL,
        auth: MediaShareFTPAuth,
        displayName: String,
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) -> Bool {
        do {
            let prepared = try mediaShareConfigurationService.saveFTP(
                baseURL: baseURL,
                auth: auth,
                displayName: displayName,
                libraryConfiguration: libraryConfiguration
            )
            reloadAccountsAndHeroCache()
            identityIndex.warmIdentityIndex()
            preparePostShareOnboarding(prepared)
            accountError = nil
            return true
        } catch {
            accountError = error.localizedDescription
            return false
        }
    }

    private func presentLibrarySelection(accountIDs: [String]) {
        let activeIDs = Set(accountsProviders.accounts.map(\.id))
        let available = accountIDs.filter(activeIDs.contains)
        guard !available.isEmpty else {
            let wasFirstRun = beginsFirstRunAfterLibrarySelection
            beginsFirstRunAfterLibrarySelection = false
            appliesPlexIdentityAfterLibrarySelection = false
            // Nothing to choose from. Previously this just meant no sheet
            // appeared; now the flow is already on screen, so it has to be moved
            // on or it would sit on a step that can never complete.
            if wasFirstRun { advanceFirstRunStep(to: .confirmProfile) }
            return
        }
        pendingLibrarySelection = PendingLibrarySelection(accountIDs: available)
        if beginsFirstRunAfterLibrarySelection { pendingFirstRunStep = .libraries }
        plexHomeUsers.ensurePlexIdentityForActiveProfile()
    }

    private func preparePostShareOnboarding(
        _ prepared: PreparedMediaShareAccount
    ) {
        guard prepared.previousAccount == nil else { return }
        let beginsFirstRun = accountsProviders.accounts.count == 1
            && !profiles.firstRunProfileSetupComplete
        if beginsFirstRun {
            profiles.seedDefaultProfileIdentity(
                name: prepared.session.userName,
                avatarImageURL: prepared.session.avatarURL?.absoluteString
            )
        }

        scheduleLibrarySelection(
            accountIDs: [prepared.account.id],
            beginsFirstRun: beginsFirstRun
        )
    }

    /// Move to `step` within the already-presented flow. Unlike
    /// `scheduleFirstRunStep` this never yields, because nothing has to be
    /// dismissed first — the cover is already on screen.
    private func advanceFirstRunStep(to step: FirstRunStep) {
        guard !profiles.firstRunProfileSetupComplete else { return }
        pendingFirstRunStep = step
    }

    private func scheduleFirstRunStep(_ step: FirstRunStep) {
        // Don't start (or re-start) first-run onboarding if the household is already
        // set up — e.g. profiles arrived via sync on a fresh device. Guards against a
        // "use profiles?"/theme prompt when the user already has profiles.
        guard !profiles.firstRunProfileSetupComplete else { return }
        Task {
            await Task.yield()
            pendingFirstRunStep = step
        }
    }

    /// Dismiss any queued first-run onboarding step once the household is known to be
    /// already set up (e.g. profiles arrived via sync after a race queued the step).
    /// Lives here so it can touch `private(set)` state.
    func clearFirstRunStepIfHouseholdSetUp() {
        if pendingFirstRunStep != nil, profiles.firstRunProfileSetupComplete {
            pendingFirstRunStep = nil
        }
    }

    private func schedulePlexUserSelection(
        _ selection: PlexHomeUsersModel.PendingPlexUserSelection
    ) {
        if isManagedServerPresentationActive {
            queuedPlexUserSelection = selection
        } else {
            plexHomeUsers.presentUserSelection(selection)
            // First run renders this step inside the flow cover; the standalone
            // sheet stays for the later add-a-server case.
            if selection.isFirstRun { pendingFirstRunStep = .plexUser }
        }
    }

    private func scheduleLibrarySelection(
        accountIDs: [String],
        beginsFirstRun: Bool = false
    ) {
        guard !accountIDs.isEmpty else {
            // Same dead-end guard as presentLibrarySelection: don't strand a
            // presented flow on a step with nothing in it.
            if beginsFirstRun { advanceFirstRunStep(to: .confirmProfile) }
            return
        }
        beginsFirstRunAfterLibrarySelection = beginsFirstRun
        postAddPresentationGeneration &+= 1
        let generation = postAddPresentationGeneration
        if isManagedServerPresentationActive {
            queuedLibraryAccountIDs = accountIDs
            queuedLibrarySelectionBeginsFirstRun = beginsFirstRun
            return
        }
        Task {
            await Task.yield()
            guard generation == postAddPresentationGeneration else { return }
            presentLibrarySelection(accountIDs: accountIDs)
        }
    }
}

private struct PlozziOSMediaShareArtworkCacheLifecycle:
    ShareLocalArtworkCacheLifecycle
{
    func setPreferredAccountKeys(_ accountKeys: Set<String>, revision: UInt64) async {
        await ArtworkImageCache.shared.setPreferredNetworkArtworkAccounts(
            accountKeys,
            revision: revision
        )
    }

    func setBackgroundWorkAllowed(_ allowed: Bool, revision: UInt64) async {
        await ArtworkImageCache.shared.setBackgroundWorkAllowed(
            allowed,
            revision: revision
        )
    }

    func purge(accountID: String) async {
        await ArtworkImageCache.shared.purgeNetworkArtwork(accountID: accountID)
    }

    func purge(accountID: String, credentialRevision: CredentialRevision) async {
        await ArtworkImageCache.shared.purgeNetworkArtwork(
            accountID: accountID,
            credentialRevision: credentialRevision
        )
    }
}
#endif

#if os(iOS)
private enum PlexOfflineDownloadQueue {
    static func prepare(
        progressiveURL: URL,
        source: ManagedHTTPDownloadSource,
        expectedDuration: TimeInterval?,
        expectedAudioLanguages: [String?]?,
        updateSource: @escaping PlozziOSBackgroundHTTPDownloadEngine.SourceUpdater,
        updatePreparationProgress:
            @escaping PlozziOSBackgroundHTTPDownloadEngine.PreparationProgressUpdater
    ) async throws -> PlozziOSBackgroundHTTPDownloadEngine.Resolution {
        guard let rootURL =
                PlexOfflineTranscodeURLBuilder.makeDownloadQueueURL(
                    from: progressiveURL
                ) else {
            throw PlexOfflineDownloadQueueError.invalidRequest
        }

        let reference: ManagedHTTPPreparationReference
        if let existing = source.preparationReference {
            reference = existing
        } else {
            let queueResponse = try await send(
                QueueResponse.self,
                to: rootURL,
                method: "POST"
            )
            guard let queueID =
                    queueResponse.MediaContainer.DownloadQueue.first?.id else {
                throw PlexOfflineDownloadQueueError.invalidResponse
            }
            let addURL = try makeAddURL(
                rootURL: rootURL,
                progressiveURL: progressiveURL,
                queueID: queueID,
                source: source
            )
            let addResponse = try await send(
                AddResponse.self,
                to: addURL,
                method: "POST"
            )
            guard let itemID =
                    addResponse.MediaContainer.AddedQueueItems.first?.id
                    ?? addResponse.MediaContainer.DownloadQueueItem.first?.id
            else {
                throw PlexOfflineDownloadQueueError.invalidResponse
            }
            reference = ManagedHTTPPreparationReference(
                queueIdentifier: String(queueID),
                itemIdentifier: String(itemID)
            )
            try await updateSource(
                ManagedHTTPDownloadSource(
                    provider: source.provider,
                    accountID: source.accountID,
                    itemID: source.itemID,
                    mediaSourceID: source.mediaSourceID,
                    quality: source.quality,
                    includesAllAudioTracks:
                        source.includesAllAudioTracks,
                    includesTextSubtitleTracks:
                        source.includesTextSubtitleTracks,
                    preferredAudioLanguages:
                        source.preferredAudioLanguages,
                    preparationReference: reference
                )
            )
        }

        while true {
            try Task.checkCancellation()
            let itemsURL = try endpoint(
                rootURL: rootURL,
                path: [
                    reference.queueIdentifier,
                    "items"
                ]
            )
            let response = try await send(
                ItemsResponse.self,
                to: itemsURL,
                method: "GET"
            )
            guard let item = response.MediaContainer.DownloadQueueItem.first(
                where: {
                    String($0.id) == reference.itemIdentifier
                }
            ) else {
                await discard(
                    rootURL: rootURL,
                    reference: reference,
                    source: source,
                    updateSource: updateSource
                )
                throw PlexOfflineDownloadQueueError.missingItem
            }
            if item.TranscodeSession?.error == true {
                await discard(
                    rootURL: rootURL,
                    reference: reference,
                    source: source,
                    updateSource: updateSource
                )
                throw PlexOfflineDownloadQueueError.serverFailure
            }
            await updatePreparationProgress(
                item.TranscodeSession?.progress.map {
                    min(1, max(0, $0 / 100))
                }
            )
            switch item.status.lowercased() {
            case "available":
                await updatePreparationProgress(1)
                let mediaURL = try endpoint(
                    rootURL: rootURL,
                    path: [
                        reference.queueIdentifier,
                        "item",
                        reference.itemIdentifier,
                        "media"
                    ]
                )
                let cleanupURL = try endpoint(
                    rootURL: rootURL,
                    path: [
                        reference.queueIdentifier,
                        "items",
                        reference.itemIdentifier
                    ]
                )
                return .init(
                    url: mediaURL,
                    expectedDuration: expectedDuration,
                    cleanupURL: cleanupURL,
                    expectedAudioLanguages: expectedAudioLanguages
                )
            case "failed", "error", "cancelled", "expired":
                await discard(
                    rootURL: rootURL,
                    reference: reference,
                    source: source,
                    updateSource: updateSource
                )
                throw PlexOfflineDownloadQueueError.serverFailure
            case "waiting", "pending", "processing", "transcoding",
                 "preparing", "queued":
                try await Task.sleep(nanoseconds: 2_000_000_000)
            default:
                throw PlexOfflineDownloadQueueError.invalidStatus(
                    item.status
                )
            }
        }
    }

    private static func makeAddURL(
        rootURL: URL,
        progressiveURL: URL,
        queueID: Int,
        source: ManagedHTTPDownloadSource
    ) throws -> URL {
        let progressiveItems = URLComponents(
            url: progressiveURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        func value(_ name: String) -> String? {
            progressiveItems.first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }?.value
        }
        let metadataPath =
            value("path") ?? "/library/metadata/\(source.itemID)"
        let sessionID = UUID().uuidString.lowercased()
        var queryItems = [
            URLQueryItem(name: "keys", value: metadataPath),
            URLQueryItem(name: "path", value: metadataPath),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(
                name: "mediaIndex",
                value: value("mediaIndex") ?? "0"
            ),
            URLQueryItem(
                name: "partIndex",
                value: value("partIndex") ?? "0"
            ),
            URLQueryItem(name: "mediaBufferSize", value: "50000"),
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "subtitleSize", value: "0"),
            URLQueryItem(name: "videoQuality", value: "100"),
            URLQueryItem(
                name: "videoResolution",
                value: value("videoResolution")
            ),
            URLQueryItem(
                name: "maxVideoBitrate",
                value: value("maxVideoBitrate")
            ),
            URLQueryItem(name: "audioBoost", value: "0"),
            URLQueryItem(name: "autoAdjustSubtitle", value: "0"),
            URLQueryItem(
                name: "advancedSubtitles",
                value: source.includesTextSubtitleTracks ? "text" : "none"
            ),
            URLQueryItem(name: "copyts", value: "1"),
            URLQueryItem(
                name: "X-Plex-Client-Profile-Name",
                value: "Generic"
            ),
            URLQueryItem(
                name: "X-Plex-Client-Profile-Extra",
                value: PlexOfflineTranscodeURLBuilder.downloadQueueProfile(
                    includesAllAudioTracks: source.includesAllAudioTracks
                )
            )
        ]
        if !source.includesAllAudioTracks, let audioStreamID = value("audioStreamID") {
            queryItems.append(
                URLQueryItem(name: "audioStreamID", value: audioStreamID)
            )
        }
        if source.includesTextSubtitleTracks,
           let subtitleStreamID = value("subtitleStreamID") {
            queryItems.append(
                URLQueryItem(
                    name: "subtitleStreamID",
                    value: subtitleStreamID
                )
            )
            queryItems.append(
                URLQueryItem(name: "subtitles", value: "auto")
            )
        } else {
            queryItems.append(
                URLQueryItem(name: "subtitles", value: "none")
            )
        }
        return try endpoint(
            rootURL: rootURL,
            path: [String(queueID), "add"],
            queryItems: queryItems
        )
    }

    private static func discard(
        rootURL: URL,
        reference: ManagedHTTPPreparationReference,
        source: ManagedHTTPDownloadSource,
        updateSource: @escaping PlozziOSBackgroundHTTPDownloadEngine.SourceUpdater
    ) async {
        if let url = try? endpoint(
            rootURL: rootURL,
            path: [
                reference.queueIdentifier,
                "items",
                reference.itemIdentifier
            ]
        ) {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 20
            )
            request.httpMethod = "DELETE"
            _ = try? await OfflineNetworkSession.shared.data(for: request)
        }
        do {
            try await updateSource(
                ManagedHTTPDownloadSource(
                    provider: source.provider,
                    accountID: source.accountID,
                    itemID: source.itemID,
                    mediaSourceID: source.mediaSourceID,
                    quality: source.quality,
                    includesAllAudioTracks: source.includesAllAudioTracks,
                    includesTextSubtitleTracks:
                        source.includesTextSubtitleTracks,
                    preferredAudioLanguages:
                        source.preferredAudioLanguages
                )
            )
        } catch {
            PlozzLog.networking.error("Unable to persist cleared offline preparation")
        }
    }

    private static func endpoint(
        rootURL: URL,
        path: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(
            url: rootURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw PlexOfflineDownloadQueueError.invalidRequest
        }
        components.path += "/" + path.joined(separator: "/")
        components.queryItems = (components.queryItems ?? []) + queryItems
        guard let url = components.url else {
            throw PlexOfflineDownloadQueueError.invalidRequest
        }
        return url
    }

    private static func send<Response: Decodable>(
        _ type: Response.Type,
        to url: URL,
        method: String
    ) async throws -> Response {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = method
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "1.0.0",
            forHTTPHeaderField: "X-Plex-Pms-Api-Version"
        )
        let (data, response) = try await OfflineNetworkSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexOfflineDownloadQueueError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlexOfflineDownloadQueueError.rejected(
                status: httpResponse.statusCode
            )
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PlexOfflineDownloadQueueError.invalidResponse
        }
    }

    private struct QueueResponse: Decodable {
        struct Container: Decodable {
            struct Queue: Decodable {
                let id: Int
            }
            let DownloadQueue: [Queue]
        }
        let MediaContainer: Container
    }

    private struct AddResponse: Decodable {
        struct Container: Decodable {
            struct Item: Decodable {
                let id: Int
            }
            let AddedQueueItems: [Item]
            let DownloadQueueItem: [Item]

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(
                    keyedBy: CodingKeys.self
                )
                AddedQueueItems = try container.decodeIfPresent(
                    [Item].self,
                    forKey: .AddedQueueItems
                ) ?? []
                DownloadQueueItem = try container.decodeIfPresent(
                    [Item].self,
                    forKey: .DownloadQueueItem
                ) ?? []
            }

            private enum CodingKeys: String, CodingKey {
                case AddedQueueItems
                case DownloadQueueItem
            }
        }
        let MediaContainer: Container
    }

    private struct ItemsResponse: Decodable {
        struct Container: Decodable {
            struct Item: Decodable {
                struct Session: Decodable {
                    let progress: Double?
                    let error: Bool?
                }
                let id: Int
                let status: String
                let TranscodeSession: Session?
            }
            let DownloadQueueItem: [Item]
        }
        let MediaContainer: Container
    }
}

private enum PlexOfflineDownloadQueueError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case rejected(status: Int)
    case missingItem
    case serverFailure
    case invalidStatus(String)

    var errorDescription: String? { // l10n:content — LocalizedError protocol requires resolved text
        let resource: LocalizedStringResource
        switch self {
        case .invalidRequest:
            resource = "Plex could not build the offline download request."
        case .invalidResponse:
            resource = "Plex returned an invalid offline download response."
        case let .rejected(status):
            resource = "Plex rejected offline download preparation with HTTP \(status)."
        case .missingItem:
            resource = "Plex removed the prepared download before it could be transferred."
        case .serverFailure:
            resource = "Plex could not prepare this offline rendition."
        case let .invalidStatus(status):
            resource = "Plex returned an unknown offline download status: \(status)."
        }
        return String(localized: resource) // l10n:content — LocalizedError requires resolved text.
    }
}
#endif
