#if os(iOS)
import AppRuntime
import CoreModels
import CoreUI
import FeatureHomeCore
import MetadataKit
import SwiftUI

/// Programmatic navigation to an item's detail page.
///
/// iOS pushes detail with inline `NavigationLink { … }`, which works for tapping
/// a card but gives the app no way to navigate *itself* — so
/// `Environment.mediaItemNavigator` was never installed, and every navigation
/// action ("Go to Season", "Go to Movie") was silently filtered out of iOS
/// context menus. tvOS installs one from its path-based stack and offers them.
///
/// This adds a value-typed destination alongside the existing links: the menu
/// sets the item, the stack builds the page once. Applied per navigation stack,
/// so a push lands in the tab the user is actually in.
/// A person plus the server that listed them — see
/// ``EnvironmentValues/mediaPersonSourceNavigator``.
private struct PlozziOSPersonRoute: Identifiable, Hashable {
    let person: MediaPerson
    let sourceAccountID: String?

    var id: String { "\(person.id)#\(sourceAccountID ?? "")" }
}

struct PlozziOSArtworkItemRoute: Hashable {
    let item: MediaItem
    let source: MediaArtworkZoomSource
}

private struct PlozziOSItemNavigationModifier: ViewModifier {
    let appModel: PlozziOSAppModel
    var registersScreenshotRouting = false
    @State private var navigatedItem: MediaItem?
    @State private var navigatedArtwork: PlozziOSArtworkItemRoute?
    @State private var navigatedPerson: PlozziOSPersonRoute?
    @State private var navigatedLibrary: PlozziOSLibraryRoute?

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $navigatedItem) { item in
                PlozziOSItemPage(appModel: appModel, item: item)
                    .modifier(ScreenshotArrivalBeacon(appModel: appModel, enabled: registersScreenshotRouting))
            }
            .navigationDestination(item: $navigatedArtwork) { route in
                PlozziOSItemPage(appModel: appModel, item: route.item)
                    .mediaArtworkZoomDestination(route.source)
            }
            .navigationDestination(item: $navigatedPerson) { route in
                PlozziOSPersonPage(appModel: appModel, route: route)
                    .modifier(ScreenshotArrivalBeacon(appModel: appModel, enabled: registersScreenshotRouting))
            }
            // The programmatic twin of the value-typed `plozziOSLibraryDestination`
            // push, so the screenshot router can open a library grid without a
            // `NavigationLink`. Both build `PlozziOSLibraryDestinationView`, so the
            // page is the same one a tap opens.
            .navigationDestination(item: $navigatedLibrary) { route in
                PlozziOSLibraryDestinationView(appModel: appModel, route: route)
                    .modifier(ScreenshotArrivalBeacon(appModel: appModel, enabled: registersScreenshotRouting))
            }
            // Applied *after* the destinations so the environment encloses them
            // and pushed pages inherit the router. The other order leaves the
            // destination outside the environment, so navigation actions are
            // dropped from every menu on a pushed page.
            .mediaItemNavigator { navigatedItem = $0 }
            .mediaItemArtworkNavigator { item, source in
                navigatedArtwork = .init(item: item, source: source)
            }
            // Account-less: for surfaces that have a person but no idea which
            // server listed them. Their credits come from the keyless ladder and
            // whatever the other servers can match by name.
            .mediaPersonNavigator { navigatedPerson = .init(person: $0, sourceAccountID: nil) }
            .mediaPersonSourceNavigator { person, accountID in
                navigatedPerson = .init(person: person, sourceAccountID: accountID)
            }
            .modifier(ScreenshotRoutingRegistration(
                appModel: appModel,
                enabled: registersScreenshotRouting,
                setItem: { navigatedItem = $0 },
                setPerson: { navigatedPerson = .init(person: $0, sourceAccountID: $1) },
                setLibrary: { navigatedLibrary = $0 },
                reset: {
                    navigatedItem = nil
                    navigatedArtwork = nil
                    navigatedPerson = nil
                    navigatedLibrary = nil
                }
            ))
    }
}

/// Reports a pushed page's appearance to the director so the out-of-stack router
/// can ack a navigation only once the page is really on screen — see the note on
/// `pageArrivals`. Compiled to nothing outside DEBUG and reporting only from the
/// stack that the router drives, so a shipped build never counts and the search
/// stack's own pushes don't wake the rig.
private struct ScreenshotArrivalBeacon: ViewModifier {
    let appModel: PlozziOSAppModel
    let enabled: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.onAppear {
            guard enabled else { return }
            appModel.screenshotDirector.notePageArrival()
        }
        #else
        content
        #endif
    }
}

/// Hands this stack's navigation setters to the screenshot director so the
/// out-of-stack router can drive it — see the note on the director's routing
/// seams. Compiled to nothing outside DEBUG and applied only by the Home stack,
/// so the search stack never fights it for the same seams and a shipped build
/// never wires them at all.
private struct ScreenshotRoutingRegistration: ViewModifier {
    let appModel: PlozziOSAppModel
    let enabled: Bool
    let setItem: (MediaItem) -> Void
    let setPerson: (MediaPerson, String?) -> Void
    let setLibrary: (PlozziOSLibraryRoute) -> Void
    let reset: () -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.onAppear {
            guard enabled else { return }
            let director = appModel.screenshotDirector
            director.navigateToItem = setItem
            director.navigateToPerson = setPerson
            director.navigateToLibrary = setLibrary
            director.resetNavigation = reset
        }
        #else
        content
        #endif
    }
}

/// A title's detail page, resolved to the best server that holds it.
struct PlozziOSItemPage: View {
    let appModel: PlozziOSAppModel
    let item: MediaItem

    var body: some View {
        let target = PlaybackSourceSelection.bestDetailItem(
            item,
            accounts: appModel.accountsProviders.resolvedActiveAccounts,
            identitySources: appModel.identityIndex.identitySourcesProvider
        )
        if let provider = appModel.provider(for: target) {
            PlozziOSItemDetailView(
                appModel: appModel,
                provider: provider,
                item: target,
                seerService: appModel.seerService,
                // An episode arriving through the menu is "Episode Info", which
                // wants the episode itself. "Go to Season" hands over a season,
                // so the two are distinguishable by kind.
                presentsEpisodeAsSubject: target.kind == .episode
            )
        } else {
            PlozzStateView(
                icon: "exclamationmark.triangle",
                title: Text("Server unavailable"),
                message: Text("This title's server is no longer connected.")
            )
        }
    }
}

/// A person's page, which owns the push to a title of its own.
///
/// The destination lives HERE rather than back at the stack root, and that is
/// the whole reason a poster on this page does something when tapped. Both
/// destinations were declared on the root's content, so a person page pushed
/// from one of them could not drive the other: setting the item from inside the
/// person destination asked the root to present a second page it was already
/// presenting from, and nothing happened at all. A pushed page that pushes
/// further has to carry its own destination.
private struct PlozziOSPersonPage: View {
    let appModel: PlozziOSAppModel
    let route: PlozziOSPersonRoute
    @State private var navigatedItem: MediaItem?
    @State private var navigatedArtwork: PlozziOSArtworkItemRoute?

    var body: some View {
        let person = route.person
        let viewModel = Self.makeViewModel(
            appModel: appModel,
            person: person,
            sourceAccountID: route.sourceAccountID
        )
        Group {
            if PlozzCustomization.isCustomBuild {
                PlozziOSPersonFilmographyGrid(
                    appModel: appModel,
                    viewModel: viewModel,
                    onSelectItem: { navigatedItem = $0 }
                )
            } else {
                PersonDetailView(
                    person: person,
                    viewModel: viewModel,
                    onSelectItem: { navigatedItem = $0 }
                )
                .artworkNavigation { navigatedArtwork = .init(item: $0, source: $1) }
            }
        }
        .navigationDestination(item: $navigatedArtwork) { route in
            PlozziOSItemPage(appModel: appModel, item: route.item)
                .mediaArtworkZoomDestination(route.source)
        }
        .navigationDestination(item: $navigatedItem) { item in
            PlozziOSItemPage(appModel: appModel, item: item)
        }
    }

    private static func makeViewModel(
        appModel: PlozziOSAppModel,
        person: MediaPerson,
        sourceAccountID: String?
    ) -> PersonDetailViewModel {
        let accounts = appModel.accountsProviders.resolvedActiveAccounts
        return PersonDetailViewModel(
            person: person,
            // The person's OWN server, by its own person id.
            //
            // Load STOPS here without one — the view model returns
            // `.unavailable` before it ever fans out — so passing nil
            // and relying on the by-name rung, as this briefly did,
            // reported "nothing else in your library" for everybody.
            // The account travels with the route because a person id
            // means nothing to any other server.
            //
            // `resolveOptional`, never a fallback to the primary
            // account: that sent Jellyfin and share person ids to
            // Plex and got nothing back. No account means no credits,
            // not wrong credits.
            provider: sourceAccountID.flatMap { id in
                accounts.first(where: { $0.account.id == id })?.provider
            },
            // Every OTHER signed-in server, asked by name, since person ids do
            // not cross servers.
            otherProviders: accounts
                .filter { $0.account.id != sourceAccountID }
                .map(\.provider),
            // Keyless, so it works for every user out of the box, and only
            // reached when no server stored a biography.
            biographyProviders: appModel.isOfflineMode || PlozzCustomization.isCustomBuild
                ? [] : [WikipediaPersonBiographyProvider()],
            // The same ladder the in-player Cast card uses — without it this
            // page can only answer with what the viewer already owns, which is
            // not what "known for" means.
            creditsProviders: appModel.isOfflineMode || PlozzCustomization.isCustomBuild
                ? [] : PlayerCastCredits.providers,
            artworkResolver: PlayerCastCredits.artworkResolver,
            // So a credit the viewer owns isn't marked absent — see the tvOS
            // person page and `PersonDetailViewModel`.
            librarySources: { [identityIndex = appModel.identityIndex] item in
                identityIndex.identitySnapshot.sourceRefs(for: item)
            }
        )
    }
}

/// The personal build's person page is a filmography wall, not a profile.
///
/// The actor's name is the only header, and the page is the same poster grid as
/// a library. Series credits are filtered out because "the films this actor was
/// in" is the question this page answers; the shared `PersonDetailView` keeps
/// its headshot, biography and Known for shelves for the canonical app and tvOS.
struct PlozziOSPersonFilmographyGrid: View {
    let appModel: PlozziOSAppModel
    @State private var viewModel: PersonDetailViewModel
    @State private var favoriteStateRevision = 0
    let onSelectItem: (MediaItem) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.themePalette) private var palette

    init(
        appModel: PlozziOSAppModel,
        viewModel: PersonDetailViewModel,
        onSelectItem: @escaping (MediaItem) -> Void
    ) {
        self.appModel = appModel
        _viewModel = State(initialValue: viewModel)
        self.onSelectItem = onSelectItem
    }

    static func movieCredits(from credits: [MediaItem]) -> [MediaItem] {
        credits.filter { $0.kind == .movie }
    }

    private var movies: [MediaItem] {
        Self.movieCredits(from: viewModel.libraryCredits)
    }

    private var isLoading: Bool {
        switch viewModel.state {
        case .loading: true
        case .loaded: !viewModel.creditsAreFinal
        case .unavailable: false
        }
    }

    var body: some View {
        ScrollView {
            if isLoading {
                PlozzPosterGridSkeleton(
                    columns: gridColumns,
                    spacing: gridSpacing,
                    horizontalPadding: gridPadding,
                    style: .poster
                )
                .padding(.top, PlozziOSMediaRailLayout.posterGridTopPadding)
                .padding(.bottom, 24)
            } else if movies.isEmpty {
                PlozzStateView(
                    icon: "film",
                    title: Text("No titles to show")
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                    ForEach(movies, id: \.stablePresentationID) { item in
                        Button {
                            onSelectItem(item)
                        } label: {
                            PlozziOSPosterCard(
                                item: item,
                                style: .poster,
                                reservesSubtitleSpace: true,
                                isFavorite: isFavorite(item),
                                rating: PlozziOSLibraryGridView.displayedRating(
                                    customBuild: PlozzCustomization.isCustomBuild,
                                    item: item
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, gridPadding)
                .padding(.top, PlozziOSMediaRailLayout.posterGridTopPadding)
                .padding(.bottom, 24)
                .accessibilityIdentifier("person-filmography-grid")
            }
        }
        .background { AppBackground(palette: palette) }
        // The wall itself identifies the person; a title would repeat the actor
        // name above a grid that may hold only one film.
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.plozzCardCaptionView, .filmography)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistIntentDidChange)) { _ in
            favoriteStateRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .universalWatchlistDidChange)) { _ in
            favoriteStateRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .universalWatchlistCacheDidLoad)) { _ in
            favoriteStateRevision &+= 1
        }
    }

    private var gridColumns: [GridItem] {
        PlozziOSPosterGridStyle.columns(
            density: appModel.settings.density.density,
            horizontalSizeClass: horizontalSizeClass,
            dynamicTypeSize: dynamicTypeSize,
            isRunningOnMac: metrics.usesDesktopSizing,
            spacing: gridSpacing
        )
    }

    private var gridSpacing: CGFloat {
        PlozziOSPosterGridStyle.spacing(metrics: metrics, cardStyle: cardStyle)
    }

    private var gridPadding: CGFloat {
        PlozziOSPosterGridStyle.gridPadding(
            horizontalSizeClass: horizontalSizeClass,
            usesDesktopSizing: metrics.usesDesktopSizing,
            metrics: metrics,
            cardStyle: cardStyle
        )
    }

    private func isFavorite(_ item: MediaItem) -> Bool {
        _ = favoriteStateRevision
        return PlozziOSLibraryGridView.showsFavoriteBadge(
            customBuild: PlozzCustomization.isCustomBuild,
            item: item,
            isWatchlisted: {
                appModel.mediaItemActionHandler.isWatchlisted($0) || $0.isFavorite
            }
        )
    }
}

extension View {
    /// Lets menu actions push an item's detail page within this navigation stack.
    ///
    /// `registersScreenshotRouting` hands this stack's programmatic navigation to
    /// the screenshot director; only the Home stack passes `true`, so the search
    /// stack does not overwrite the seams the capture run drives.
    func plozziOSItemNavigation(
        appModel: PlozziOSAppModel,
        registersScreenshotRouting: Bool = false
    ) -> some View {
        modifier(PlozziOSItemNavigationModifier(
            appModel: appModel,
            registersScreenshotRouting: registersScreenshotRouting
        ))
    }
}
#endif
