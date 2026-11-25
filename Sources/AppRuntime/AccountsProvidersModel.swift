import Foundation
import Observation
import CoreModels
import CoreNetworking
import FeatureAuthCore
import CoreSecureStore
import CoreUI

/// The accounts + providers hub, extracted from `AppState`.
///
/// Owns the multi-account core: the persisted `AccountPersisting` store, the
/// `ProviderRegistry`, the signed-in `accounts` and the active-account subset,
/// and every provider-resolution accessor (`provider(forAccountID:)`,
/// `homeAccounts`, `resolvedActiveAccounts`, …). This is the dependency HUB the
/// Plex-home-user, media-share, profile-flow, and household facets sit downstream
/// of, so it's extracted first and exposes a stable typed interface rather than
/// throwaway closures.
///
/// It depends OUTWARD only through narrow injected seams so the hub never reaches
/// back into the domains that will later be split out of `AppState`:
///  - `tokenResolver` — the effective auth token for an account (Plex Home-user
///    override aware). Wired by `AppState` today; becomes the Plex-home-user
///    facet's responsibility in a later batch.
///  - `credentialRevision` — the effective credential revision (override aware).
///  - `onActiveAccountsChanged` — fired after `reloadAccounts` recomputes the
///    active set, so the media-share runtime can update its preferred-account
///    keys. Keeps the media-share concern out of the hub.
///
/// Kept `@MainActor @Observable` so `accounts` / `activeAccountIDs` observation is
/// identical to when they lived on `AppState`.
@MainActor
@Observable
public final class AccountsProvidersModel {
    @ObservationIgnored public var onLocalAccountAuthentication: (String) -> Void = { _ in }
    /// All signed-in accounts, in stable order.
    public private(set) var accounts: [Account] = []
    /// Whether `accounts` reflects what is on disk yet. `false` until the first
    /// `reloadAccounts()` completes: consumers that would prune durable state on an
    /// empty list (Home's cached snapshot is the first) must wait for this, or they
    /// throw away a perfectly good snapshot during launch, before the account store
    /// has been read, and the page has to re-fetch everything.
    public private(set) var hasResolvedAccounts = false
    /// The subset of `accounts` currently included in the active set. Sourced
    /// from the active profile (falling back to the household-global active set
    /// for the default profile).
    public private(set) var activeAccountIDs: Set<String> = []
    /// Snapshot on reload so rendering picker badges never reads the Keychain.
    private var householdActiveAccountIDs: [String] = []

    /// An explicit selection has no locally available accounts, including when
    /// its selected accounts were removed. Never substitute an excluded account.
    public private(set) var watchesNothingByChoice = false
    /// Non-nil replaces, never supplements, online providers while browsing downloads.
    public var localProviders: [String: any MediaProvider]?

    /// The persisted multi-account store (token per account in the Keychain).
    @ObservationIgnored
    public let accountStore: AccountPersisting
    /// Resolves the right `MediaProvider` per account, with a per-account cache.
    @ObservationIgnored
    public let registry: ProviderRegistry

    /// The household's profiles + active selection. Shared reference (the same
    /// instance `AppState` holds); read for the active-set resolution and the
    /// media-share local-media context.
    @ObservationIgnored
    private let profilesModel: ProfilesModel
    /// The auth token to use for an account id, preferring an in-memory Plex
    /// Home-user override over the account's stored (admin) token. Injected so the
    /// hub doesn't own Plex-home-user state.
    @ObservationIgnored
    public var tokenResolver: @MainActor (String) -> String? = { _ in nil }
    /// The effective credential revision for an account (Plex override aware).
    @ObservationIgnored
    public var credentialRevision: @MainActor (Account) -> CredentialRevision = { $0.credentialRevision }
    @ObservationIgnored
    public var cloudTokenResolver: @MainActor (Account, CredentialRevision) async throws -> String? = { _, _ in nil }
    /// Fired after `reloadAccounts` recomputes the active set, with the resolved
    /// active ids and the full account list, so the media-share runtime can update
    /// its preferred-account keys without the hub knowing about media shares.
    @ObservationIgnored
    public var onActiveAccountsChanged: @MainActor (Set<String>, [Account]) -> Void = { _, _ in }
    /// Fired at the START of every `reloadAccounts`, before anything is
    /// recomputed, so caches keyed on the account set are dropped rather than
    /// serving a stale answer. Separate from `onActiveAccountsChanged` (which
    /// fires at the end, after the new set is known) because an invalidation must
    /// happen even if the recompute below returns early.
    public var onAccountsInvalidated: @MainActor () -> Void = {}
    public init(
        accountStore: AccountPersisting,
        registry: ProviderRegistry,
        profilesModel: ProfilesModel
    ) {
        self.accountStore = accountStore
        self.registry = registry
        self.profilesModel = profilesModel
    }

    /// This device's stable client identifier.
    public var deviceID: String { accountStore.deviceID() }

    public func configureAuthenticatedArtwork() {
        ArtworkSession.authenticatedLoader = { [weak self] reference in
            guard let self else { throw AppError.cancelled }
            let profileID = self.profilesModel.activeProfileID
            @MainActor func authorizedProvider() throws -> any AuthenticatedArtworkProviding {
                guard self.localProviders == nil, !self.accountSelectionIsUnavailable,
                      self.profilesModel.activeProfileID == profileID,
                      self.homeAccounts.contains(where: {
                          $0.account.id == reference.accountID
                            && self.credentialRevision($0.account) == reference.credentialRevision
                      }),
                      let provider = self.provider(forAccountID: reference.accountID)
                        as? any AuthenticatedArtworkProviding else { throw AppError.unauthorized }
                return provider
            }
            let bytes = try await authorizedProvider().artworkData(for: reference)
            try Task.checkCancellation()
            _ = try authorizedProvider()
            return bytes
        }
    }

    public func downloadUserID(for accountID: String, profileID: String) -> String? {
        guard profilesModel.activeProfileID == profileID, activeAccountIDs.contains(accountID),
              let account = accounts.first(where: { $0.id == accountID }) else { return nil }
        return WatchMutationServerScope.AccountIdentity(
            account: account, profile: profilesModel.activeProfile
        ).downloadUserID
    }

    public func makeAccountReauthentication(
        account: Account, isAuthorized: @escaping () -> Bool, onComplete: @escaping () -> Void
    ) -> AccountReauthenticationModel {
        let profile = AutomaticSignInStore.Session.ProfileAccess(profilesModel.activeProfile)
        return AccountReauthenticationModel(
            account: account, deviceID: deviceID, store: accountStore,
            isAuthorized: { [weak self] in
                guard let self else { return false }
                return profile == .init(self.profilesModel.activeProfile) && isAuthorized()
            },
            onComplete: { [weak self] in
                guard let self else { return }
                self.onLocalAccountAuthentication(account.id)
                self.registry.invalidate(accountID: account.id)
                self.reloadAccounts()
                onComplete()
            }
        )
    }

    private var accountSelectionIsUnavailable: Bool {
        profilesModel.unconfirmedAccountSelectionProfileIDs.contains(profilesModel.activeProfileID)
    }

    /// Sync may record a question before the account's provider is known.
    /// Only locally present, active Plex accounts can require an identity choice.
    public var activeProfileAwaitsIdentity: Bool {
        profilesModel.activeProfile.awaitsIdentity(
            amongAccounts: accounts.lazy.filter {
                self.activeAccountIDs.contains($0.id) && $0.server.provider == .plex
            }.map(\.id)
        )
    }

    /// The provider for the primary active account — the single-provider Home in
    /// this branch. `nil` when not signed in.
    public var primaryProvider: (any MediaProvider)? {
        if let localProviders {
            return primaryActiveAccount.flatMap { localProviders[$0.id] }
        }
        guard let account = primaryActiveAccount,
              let token = tokenResolver(account.id) else { return nil }
        return resolveProvider(for: providerResolutionContext(for: account, token: token))
    }

    /// The active account that drives the current single-provider UI.
    public var primaryActiveAccount: Account? {
        // A profile that chose to watch nothing has no primary account. Without
        // this the `?? accounts.first` below answered with the household's first
        // server, so Settings showed every server off while Home played from one.
        if watchesNothingByChoice || accountSelectionIsUnavailable { return nil }
        return accounts.first { activeAccountIDs.contains($0.id) } ?? accounts.first
    }

    /// The active accounts paired with their resolved providers. Multi-account
    /// Home/Search fan out over this list (one provider call per account,
    /// merged by the view model). Tokens are resolved on demand and never
    /// stored on the value.
    public var resolvedActiveAccounts: [ResolvedAccount] {
        guard !accountSelectionIsUnavailable else { return [] }
        if let localProviders {
            return accounts.compactMap { account in
                guard activeAccountIDs.contains(account.id), let provider = localProviders[account.id] else { return nil }
                return resolvedAccount(account, provider: provider)
            }
        }
        return accounts.compactMap { account in
            guard activeAccountIDs.contains(account.id),
                  let token = tokenResolver(account.id),
                  let provider = resolveProvider(
                      for: providerResolutionContext(for: account, token: token)
                  )
            else { return nil }
            return resolvedAccount(account, provider: provider)
        }
    }

    /// Resolves specific account ids into `ResolvedAccount`s for the onboarding
    /// "choose your libraries" step (which fans a library-listing call out over
    /// the just-added accounts). Tokens are resolved on demand.
    public func resolvedAccounts(withIDs ids: [String]) -> [ResolvedAccount] {
        if let localProviders {
            return accounts.compactMap { account in
                guard ids.contains(account.id), activeAccountIDs.contains(account.id),
                      let provider = localProviders[account.id] else { return nil }
                return resolvedAccount(account, provider: provider)
            }
        }
        return ids.compactMap { id in
            guard let account = accounts.first(where: { $0.id == id }),
                  let token = tokenResolver(account.id),
                  let provider = resolveProvider(
                      for: providerResolutionContext(for: account, token: token)
                  )
            else { return nil }
            return resolvedAccount(account, provider: provider)
        }
    }

    /// The accounts the unified Home/Search fan out over. Normally the active
    /// set; falls back to the primary account so the signed-in UI is never empty
    /// when the active-id set is empty for a reason the user didn't ask for.
    ///
    /// The fallback is deliberately NOT applied when the profile chose to watch
    /// nothing — that's an instruction, not a gap to paper over, and honouring it
    /// is what stops a Kids Profile with every server switched off still being
    /// fed the household's first server.
    public var homeAccounts: [ResolvedAccount] {
        let active = resolvedActiveAccounts
        if localProviders != nil { return active }
        if !active.isEmpty { return active }
        if watchesNothingByChoice { return [] }
        guard let account = primaryActiveAccount,
              let token = tokenResolver(account.id),
              let provider = resolveProvider(
                  for: providerResolutionContext(for: account, token: token)
              )
        else { return [] }
        return [resolvedAccount(account, provider: provider)]
    }

    /// Configured sources for navigation, not authorization to access their data.
    /// Pending credentials must not turn a media profile into an empty one.
    public var navigationAccounts: [Account] {
        guard !watchesNothingByChoice, !accountSelectionIsUnavailable else { return [] }
        let active = accounts.filter { activeAccountIDs.contains($0.id) }
        if !active.isEmpty { return active }
        return primaryActiveAccount.map { [$0] } ?? []
    }

    private func resolvedAccount(_ account: Account, provider: any MediaProvider) -> ResolvedAccount {
        ResolvedAccount(
            account: account, provider: provider,
            plexHomeUserID: account.server.provider == .plex
                ? profilesModel.activeProfile.homeUserBinding(forPlexAccount: account.id)?.homeUserID : nil,
            credentialRevision: credentialRevision(account)
        )
    }

    /// Resolves the provider for a specific account id — used to route a tapped
    /// library/item from the merged Home back to its owning provider. Tokens are
    /// resolved on demand and never stored on the value.
    public func provider(forAccountID id: String) -> (any MediaProvider)? {
        if let localProviders {
            guard activeAccountIDs.contains(id), !accountSelectionIsUnavailable else { return nil }
            return localProviders[id]
        }
        guard let account = accounts.first(where: { $0.id == id }),
              let token = tokenResolver(account.id)
        else { return nil }
        return resolveProvider(for: providerResolutionContext(for: account, token: token))
    }

    /// Builds the provider-resolution context for an account + resolved token.
    public func providerResolutionContext(
        for account: Account,
        token: String
    ) -> ProviderResolutionContext {
        let localMediaContext = [.mediaShare, .plex].contains(account.server.provider)
            ? LocalMediaContext(
                accountID: account.id,
                profileID: profilesModel.activeProfileID,
                profileNamespace: profilesModel.activeNamespace,
                serverUserID: account.server.provider == .plex
                    ? (profilesModel.activeProfile.homeUserBinding(forPlexAccount: account.id)?.homeUserID ?? account.userID)
                    : nil
            )
            : nil
        let revision = credentialRevision(account)
        let cloudTokenResolver: (@Sendable () async throws -> String?)?
        if account.server.provider == .plex {
            cloudTokenResolver = { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.cloudTokenResolver(account, revision)
            }
        } else {
            cloudTokenResolver = nil
        }
        return ProviderResolutionContext(
            session: account.session(token: token),
            accountID: account.id,
            credentialRevision: revision,
            localMediaContext: localMediaContext,
            cloudTokenResolver: cloudTokenResolver
        )
    }

    /// Resolves a provider through the registry, logging any resolution error
    /// (unregistered provider, missing/stale credential revision, local-media
    /// context mismatch) instead of silently swallowing it. Returns `nil` on
    /// failure exactly as the previous `try?` did, so the observable resolution
    /// behavior is unchanged — the only new effect is a diagnostic log line so
    /// config/state bugs aren't invisible.
    private func resolveProvider(for context: ProviderResolutionContext) -> (any MediaProvider)? {
        do {
            return try registry.provider(for: context)
        } catch {
            PlozzLog.app.error("Provider resolution failed for account \(context.accountID): \(error)")
            return nil
        }
    }

    /// The active account ids for a specific profile, filtered to accounts that
    /// are still signed in. Only an unset selection inherits the household set;
    /// missing selected accounts never authorize other accounts.
    public func activeAccountIDs(forProfile id: String) -> [String] {
        let known = Set(accounts.map(\.id))
        if let stored = profilesModel.storedActiveAccountIDs(for: id) {
            return stored.filter { known.contains($0) }
        }
        return householdActiveAccountIDs.filter { known.contains($0) }
    }

    /// Stable authorization scope for device-local playback/session state.
    /// Survives token rotation is intentionally NOT guaranteed: a credential
    /// replacement should invalidate the scope.
    public var playbackAuthorizationID: String {
        let identities = accounts.filter { activeAccountIDs.contains($0.id) }
            .map(authorizationIdentity(for:)).sorted()
        return profilesModel.activeProfileID + (localProviders == nil ? "|online|" : "|offline|")
            + identities.joined(separator: "|")
    }

    private func authorizationIdentity(for account: Account) -> String {
        ([
            account.id, account.server.id, account.server.provider.rawValue,
            account.server.baseURL.absoluteString, account.userID, account.deviceID,
            credentialRevision(account).rawValue.uuidString
        ] + (account.server.connectionURLs ?? []).map(\.absoluteString)).joined(separator: ":")
    }

    /// Stable watch-state ownership. Unlike the live authorization fingerprint,
    /// this survives token rotation and process restarts.
    public var watchMutationServerScope: WatchMutationServerScope {
        let primaryID = primaryActiveAccount?.id
        return WatchMutationServerScope(
            profile: profilesModel.activeProfile,
            accounts: accounts.filter { activeAccountIDs.contains($0.id) || $0.id == primaryID }
        )
    }

    public func requireWatchMutationServerScope(
        _ scope: WatchMutationServerScope,
        isPlexIdentityResolved: (String) -> Bool
    ) throws {
        guard profilesModel.activeProfileID == scope.profileID else {
            throw WatchMutationServerScopeError.unavailable
        }
        let current = watchMutationServerScope
        guard scope.accounts.allSatisfy({ expected in
            current.accounts.contains(expected)
                && (expected.providerKind != .plex || isPlexIdentityResolved(expected.accountID))
        }) else {
            throw WatchMutationServerScopeError.unavailable
        }
    }

    public func isCurrentWatchMutationServerScope(
        _ scope: WatchMutationServerScope?,
        isPlexIdentityResolved: (String) -> Bool
    ) -> Bool {
        guard let scope else { return true }
        do {
            try requireWatchMutationServerScope(scope, isPlexIdentityResolved: isPlexIdentityResolved)
            return true
        } catch {
            return false
        }
    }

    /// Validate and resolve without a suspension between them. The returned
    /// provider therefore cannot belong to a replacement viewer, even if a
    /// switch happens while the caller awaits this main-actor operation.
    public func provider(
        forWatchMutationAccountID accountID: String,
        isPlexIdentityResolved: (String) -> Bool
    ) -> (any MediaProvider)? {
        if let scope = WatchMutationDeliveryAuthorization.current?.serverScope {
            guard scope.accounts.contains(where: { $0.accountID == accountID }) else { return nil }
            do {
                try requireWatchMutationServerScope(scope, isPlexIdentityResolved: isPlexIdentityResolved)
            } catch {
                return nil
            }
        }
        return provider(forAccountID: accountID)
    }

    public func profileShowsPINLock(_ profile: Profile) -> Bool {
        let plexIDs = Set(accounts.filter { $0.server.provider == .plex }.map(\.id))
        return profile.showsPINLock(
            activePlexAccountIDs: Set(activeAccountIDs(forProfile: profile.id)).intersection(plexIDs)
        )
    }

    /// Reloads accounts from the store and recomputes the active set for the
    /// active profile. Invalidates the provider cache first, then fires
    /// `onActiveAccountsChanged` so the media-share runtime can update its
    /// preferred-account keys.
    public func reloadAccounts(updatingServerAddressesFor addressAccountID: String? = nil) {
        profilesModel.retryUnconfirmedAccountSelections()
        let updated = accountStore.loadAccounts()
        if let addressAccountID,
           let account = updated.first(where: { $0.id == addressAccountID }),
           accounts.map({ old in
               var expected = old
               if old.id == addressAccountID {
                   expected.server.alternateConnectionURLs = account.server.alternateConnectionURLs
               }
               return expected
           }) == updated {
            registry.updateServerAddresses(accountID: addressAccountID,
                                           alternatives: account.server.alternateConnectionURLs ?? [])
        } else {
            registry.invalidateCache()
        }
        onAccountsInvalidated()
        accounts = updated
        hasResolvedAccounts = true
        householdActiveAccountIDs = accountStore.activeAccountIDs()
        publishActiveAccountSelection()
    }

    /// Membership edits do not change household credentials or unrelated
    /// providers. Retire only disabled sources, retaining other connections.
    public func refreshActiveAccountSelection() {
        profilesModel.retryUnconfirmedAccountSelections()
        let resolved = Set(activeAccountIDs(forProfile: profilesModel.activeProfileID))
        for id in activeAccountIDs.subtracting(resolved) {
            registry.invalidate(accountID: id)
        }
        onAccountsInvalidated()
        publishActiveAccountSelection()
    }

    private func publishActiveAccountSelection() {
        let resolved = Set(activeAccountIDs(forProfile: profilesModel.activeProfileID))
        activeAccountIDs = resolved
        watchesNothingByChoice = resolved.isEmpty
            && !accountSelectionIsUnavailable
            && profilesModel.storedActiveAccountIDs(for: profilesModel.activeProfileID) != nil
        onActiveAccountsChanged(resolved, accounts)
    }

    /// Retries credentials whose launch-time Keychain read failed, without
    /// rebuilding accounts or providers during an interactive navigation path.
    @discardableResult
    public func retryUnconfirmedCredentials() -> Bool {
        let membershipsRecovered = profilesModel.retryUnconfirmedAccountSelections()
        let credentialsRecovered = accountStore.retryUnconfirmedCredentials()
        guard membershipsRecovered || credentialsRecovered else { return false }
        reloadAccounts()
        return true
    }

    /// Refresh public names and canonical addresses on both platforms. Reloading
    /// propagates address changes to retained providers and library/Home tasks.
    /// Offline servers are skipped; account and credential identities are retained.
    public func refreshServerNames() {
        guard !OfflineMode.shared.isEnabled else { return }
        let store = accountStore
        Task { @MainActor [weak self] in
            let updated = await ServerNameRefresher(accountStore: store).refresh()
            if updated > 0 { self?.reloadAccounts() }
        }
    }
}
