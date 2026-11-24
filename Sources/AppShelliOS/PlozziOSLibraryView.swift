#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import Observation
import SwiftUI

@MainActor
@Observable
final class PlozziOSLibrariesModel {
    private(set) var state: LoadState<[MediaLibrary]> = .idle

    func load(provider: (any MediaProvider)?) async {
        guard let provider else {
            state = .empty
            return
        }
        state = .loading
        do {
            let libraries = try await provider.libraries()
                .filter { !$0.isMusic }
            state = libraries.isEmpty ? .empty : .loaded(libraries)
        } catch is CancellationError {
            return
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }
}

struct PlozziOSLibrariesView: View {
    @State private var model = PlozziOSLibrariesModel()

    let appModel: PlozziOSAppModel
    let onAddServer: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading libraries…")
            case .empty:
                PlozzStateView(
                    icon: "rectangle.stack",
                    title: Text("No video libraries"),
                    message: Text("This server did not return any movie or TV libraries.")
                )
            case let .loaded(libraries):
                PlozziOSLibraryList(
                    libraries: libraries,
                    provider: appModel.accountsProviders.primaryProvider,
                    settings: appModel.settings
                )
            case let .failed(error):
                ContentUnavailableView {
                    Label("Unable to load libraries", systemImage: "exclamationmark.triangle")
                } description: {
                    if let server = appModel.accountsProviders.primaryProvider?.session.server {
                        ServerIdentityChip(server: server)
                    }
                    Text(error.userMessage)
                } actions: {
                    Button("Try Again") {
                        Task {
                            await model.load(
                                provider: appModel.accountsProviders.primaryProvider
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Home")
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onAddServer) {
                    Label {
                        Text(SettingsCopy.addSource)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task(id: appModel.accounts.map(\.connectionScopeKey)) {
            await model.load(provider: appModel.accountsProviders.primaryProvider)
        }
    }
}

private struct PlozziOSLibraryList: View {
    let libraries: [MediaLibrary]
    let provider: (any MediaProvider)?
    let settings: PlozziOSSettingsModel

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(libraries) { library in
                    if provider != nil {
                        // Value-based so the pushed grid survives a re-render of
                        // this list; see PlozziOSLibraryRoute.
                        NavigationLink(
                            value: PlozziOSLibraryRoute(
                                library: library,
                                accountID: library.sourceAccountID
                            )
                        ) {
                            PlozziOSLibraryCard(library: library)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}

struct PlozziOSLibraryCard: View {
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.themePalette) private var palette
    @Environment(\.plozzCardCaptionSettings) private var captions
    let library: MediaLibrary

    var body: some View {
        Group {
            if cardStyle == .framed {
                content
                    .plozzFramedMediaCard(
                        innerCornerRadius: metrics.landscapeArtworkCornerRadius
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(library.displayName)
    }

    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: metrics.landscapeCaptionTopSpacing
        ) {
            AsyncImage(url: library.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(palette.fill)
                    .overlay {
                        Image(systemName: librarySymbol)
                            .font(.largeTitle)
                            .plozzForeground(.secondary)
                    }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: metrics.landscapeArtworkCornerRadius,
                    style: .continuous
                )
            )
            .plozzMediaEdge(
                cornerRadius: metrics.landscapeArtworkCornerRadius
            )

            if captions.showsLabels {
                library.displayName
                    .font(.headline)
                    .lineLimit(2)
                    .padding(.horizontal, metrics.landscapeCaptionHorizontalInset)
                    .padding(
                        .bottom,
                        cardStyle == .framed ? metrics.landscapeCaptionInset : 0
                    )
            }
        }
        .contentShape(Rectangle())
    }

    private var librarySymbol: String {
        switch library.kind {
        case .series: "tv"
        case .collection: "rectangle.stack"
        default: "film"
        }
    }
}

struct PlozziOSLibraryGridView: View {
    @Environment(PlozziOSAppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var accessiblePosterWidth: CGFloat = 116
    /// Per-profile card presentation. Decides how far a grid card insets its
    /// artwork, which is what the banner's edges have to match.
    @Environment(\.plozzCardStyle) private var cardStyle
    @State private var viewModel: LibraryBrowseViewModel
    @State private var selectedRecommendedItem: PlozziOSArtworkItemRoute?
    /// Bumped when the universal watchlist changes so card badges re-read
    /// membership even when the provider's library payload is unchanged.
    @State private var favoriteStateRevision = 0
    private let title: String   // l10n:content — library name from the server
    private let provider: any MediaProvider
    private let settings: PlozziOSSettingsModel
    /// App-wide media-share scan/enrich status, feeding the banner above the grid.
    /// Passed rather than read from the environment so the pushed destination
    /// carries it explicitly, like every other dependency on this route.
    private let scanStatus: ShareScanStatusModel?
    private let isCombinedLibrary: Bool

    init(
        viewModel: LibraryBrowseViewModel,
        title: String,   // l10n:content — library name from the server
        provider: any MediaProvider,
        settings: PlozziOSSettingsModel,
        scanStatus: ShareScanStatusModel? = nil,
        isCombinedLibrary: Bool = false
    ) {
        _viewModel = State(initialValue: viewModel)
        self.title = title
        self.provider = provider
        self.settings = settings
        self.scanStatus = scanStatus
        self.isCombinedLibrary = isCombinedLibrary
    }

    /// Whether the pushed page shows a navigation title at all.
    ///
    /// The personal build hides a single library's name, which only repeats the
    /// navigation entry that opened it. The combined All Libraries page, the
    /// Collections catalog, and collection/playlist member pages keep their
    /// titles because those names describe the page rather than a server
    /// library.
    static func showsNavigationTitle(
        customBuild: Bool,
        isCombinedLibrary: Bool,
        browseScope: LibraryBrowseScope
    ) -> Bool {
        !customBuild || isCombinedLibrary || browseScope != .library
    }

    private var showsNavigationTitle: Bool {
        Self.showsNavigationTitle(
            customBuild: PlozzCustomization.isCustomBuild,
            isCombinedLibrary: isCombinedLibrary,
            browseScope: viewModel.browseScope
        )
    }

    var body: some View {
        let generation = viewModel.contentGeneration
        let _ = favoriteStateRevision
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.availableContentModes.count > 1 {
                        PlozziOSLibraryContentModeControl(viewModel: viewModel)
                    }
                    Group {
                        if viewModel.contentMode == .recommended {
                            recommendedContent.plozzDesktopMediaRailLayout()
                        } else {
                            browseContent(generation: generation)
                        }
                    }
                    .id(viewModel.contentMode)
                }
                .padding(.top, PlozzCustomization.isCustomBuild ? PlozziOSMediaRailLayout.posterGridTopPadding : 8)
                .padding(.bottom, 24)
                // Include the top padding so changing modes returns to the true
                // scroll edge instead of moving the header and navigation chrome.
                .id("library-top")
            }
            .accessibilityIdentifier("library-page")
            .onChange(of: viewModel.contentMode) { _, _ in
                proxy.scrollTo("library-top", anchor: .top)
            }
            .onChange(of: viewModel.alphabet.destination) { _, destination in
                if let destination { proxy.scrollTo(destination.index, anchor: .top) }
            }
        }
        // The personal build enters a library directly on its grid, so the
        // library's own name in a large title repeats the tab or the page that
        // pushed it. Combined pages (All Libraries, top-level Collections) keep
        // their titles because those names describe the page, not a server
        // library.
        .navigationTitle(showsNavigationTitle ? Text(title) : Text(verbatim: ""))
        .environment(\.plozzCardCaptionView, viewModel.browseScope.cardCaptionView(for: viewModel.contentMode))
        .environment(\.plozzArtworkArea, nil)
        .navigationBarTitleDisplayMode(
            PlozzCustomization.isCustomBuild && showsNavigationTitle ? .large : .inline
        )
        .navigationDestination(item: $selectedRecommendedItem) { route in
            PlozziOSItemDetailView(
                appModel: appModel,
                provider: provider,
                item: route.item,
                originSourceAccountID: route.item.sourceAccountID
            )
            .mediaArtworkZoomDestination(route.source)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.collectionScanIncomplete, viewModel.state.value != nil, viewModel.pageError == nil,
               viewModel.contentMode == .collections {
                LibraryCollectionLoadingView(progress: viewModel.collectionProgress) {
                    Task { await viewModel.loadFirstPage() }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            if viewModel.contentMode == .recommended, let error = viewModel.recommendationError,
               viewModel.recommendationState.value != nil {
                VStack(alignment: .leading, spacing: 12) {
                    InlineErrorMessage(Text(error.userMessage))
                    ContentFailureActions(report: viewModel.recommendationDiagnostic.map(PlaybackDiagnosticReport.library)) {
                        Task { await viewModel.loadRecommendations() }
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
            if viewModel.contentMode != .recommended, let error = viewModel.pageError {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.collectionScanIncomplete {
                        Text("Some collections haven't been checked yet. The list is incomplete.")
                    }
                    Text(viewModel.queryMessage ?? error.userMessage)
                        .plozzForeground(.secondary)
                    ContentFailureActions(report: viewModel.browseDiagnostic.map(PlaybackDiagnosticReport.library)) {
                        Task { await viewModel.retryFailedPages() }
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                queryControls.labelStyle(.iconOnly)
            }
            if let library = viewModel.fileBrowserLibrary {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(
                        value: PlozziOSLibraryRoute(
                            library: library,
                            accountID: library.sourceAccountID ?? provider.session.server.id
                        )
                    ) {
                        Label("Browse Files", systemImage: "folder")
                    }
                }
            }
        }
        .task { await viewModel.loadFirstPageIfNeeded() }
        .task(id: viewModel.availableContentModes) { await viewModel.reconcileContentMode() }
        .background {
            LibraryAlphabetFeedback(letter: viewModel.alphabet.jumpingTo, message: viewModel.alphabet.message)
        }
        .onDisappear { viewModel.cancelPendingQuery() }
        .plozziOSLibraryDestination(appModel: appModel)
        .background {
            if viewModel.isMediaShare {
                ShareCatalogRefreshObserver(
                    shareID: viewModel.sourceServerID,
                    status: scanStatus
                ) {
                    await viewModel.refreshAfterCatalogChange()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemDidMutate)) { note in
            if let mutation = MediaItemMutation.from(note) {
                viewModel.applyWatchedState(mutation)
            }
        }
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

    @ViewBuilder
    private var recommendedContent: some View {
        switch viewModel.recommendationState {
        case .idle, .loading:
            ProgressView("Loading recommendations…")
                .frame(maxWidth: .infinity, minHeight: 220)
        case .empty:
            PlozzStateView(
                icon: "sparkles",
                title: Text("No recommendations in this library")
            )
        case .loaded(let loaded):
            let sections = viewModel.visibleRecommendedRows(loaded)
            if sections.isEmpty {
                PlozzStateView(
                    icon: "rectangle.grid.1x2",
                    title: Text("No visible rows"),
                    message: Text("Show rows in Settings > Screens & Navigation > Customize Libraries.")
                )
            }
            VStack(alignment: .leading, spacing: PlozziOSMediaRailLayout.sectionGap(metrics: metrics)) {
                ForEach(sections) { section in
                    PlozziOSLibraryRecommendationRow(
                        section: section,
                        spoilerSettings: settings.spoilers.settings,
                        showsSeriesArtwork: section.id == "continueWatching"
                            && settings.homeVisibility.continueWatchingUsesSeriesArtwork,
                        continueWatchingLayout: settings.homeVisibility.continueWatchingLayout,
                        onSelect: { selectedRecommendedItem = .init(item: $0, source: $1) }
                    )
                    .environment(\.plozzArtworkArea, section.id == "continueWatching" ? .continueWatching : .recommended)
                }
            }
        case .failed(let error):
            ContentUnavailableView {
                Label("Unable to load recommendations", systemImage: "exclamationmark.triangle")
            } description: {
                ForEach(viewModel.errorServers, id: \.self) { server in
                    ServerIdentityChip(server: server)
                }
                Text(error.userMessage)
            } actions: {
                ContentFailureActions(report: viewModel.recommendationDiagnostic.map(PlaybackDiagnosticReport.library)) {
                    Task { await viewModel.loadRecommendations() }
                }
            }
        }
    }

    @ViewBuilder
    private func browseContent(generation: Int) -> some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                Group {
                    if PlozzCustomization.isCustomBuild {
                        VStack(alignment: .leading, spacing: 12) {
                            if let progress = viewModel.collectionProgress {
                                LibraryCollectionLoadingView(progress: progress) {
                                    Task { await viewModel.loadFirstPage() }
                                }
                                .frame(maxWidth: .infinity, minHeight: 120)
                                .padding(.horizontal)
                            } else if let progress = viewModel.queryProgress {
                                LibraryQueryPreparationView(progress: progress) { Task { await viewModel.cancelIndex() } }
                                    .frame(height: 220)
                            }
                            PlozzPosterGridSkeleton(
                                columns: gridColumns,
                                spacing: gridSpacing,
                                horizontalPadding: gridHorizontalPadding,
                                style: viewModel.gridStyle == .landscape ? .landscape : .poster
                            )
                        }
                    } else {
                        if let progress = viewModel.collectionProgress {
                            LibraryCollectionLoadingView(progress: progress) {
                                Task { await viewModel.loadFirstPage() }
                            }
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.horizontal)
                        } else if let progress = viewModel.queryProgress {
                            LibraryQueryPreparationView(progress: progress) { Task { await viewModel.cancelIndex() } }
                                .frame(height: 320)
                        } else {
                            ProgressView("Loading \(title)…")
                                .frame(maxWidth: .infinity, minHeight: 220)
                        }
                    }
                }
                .transition(.opacity)
            case .empty:
                PlozzStateView(
                    icon: "rectangle.stack",
                    title: viewModel.emptyMessage
                )
                .transition(.opacity)
            case let .loaded(total):
                Group {
                    if total == 0 {
                        PlozzStateView(
                            icon: "rectangle.stack",
                            title: viewModel.emptyMessage
                        )
                    } else {
                        scanBanner
                        LazyVGrid(
                            columns: gridColumns,
                            spacing: gridSpacing
                        ) {
                            ForEach(0..<total, id: \.self) { index in
                                let slot = viewModel.slot(at: index)
                                PlozziOSLibraryItemCell(
                                    slot: slot,
                                    index: index,
                                    generation: generation,
                                    style: viewModel.gridStyle == .landscape ? .landscape : .poster,
                                    provider: provider,
                                    isCombinedLibrary: isCombinedLibrary,
                                    favoriteStateRevision: favoriteStateRevision,
                                    playlistOrigin: { viewModel.playlistOrigin(at: index) },
                                    onAppear: { await viewModel.itemAppeared(at: index, generation: generation) },
                                    onDisappear: { viewModel.itemDisappeared(at: index, generation: generation) }
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal, gridHorizontalPadding)
                        .accessibilityIdentifier("library-grid")
                    }
                }
                .transition(.opacity)
            case let .failed(error):
                ContentUnavailableView {
                    Label("Unable to load \(title)", systemImage: "exclamationmark.triangle")
                } description: {
                    ForEach(viewModel.errorServers, id: \.self) { server in
                        ServerIdentityChip(server: server)
                    }
                    Text(viewModel.queryMessage ?? error.userMessage)
                } actions: {
                    ContentFailureActions(report: viewModel.browseDiagnostic.map(PlaybackDiagnosticReport.library)) {
                        Task { await viewModel.loadFirstPage() }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(
            reduceMotion || !PlozzCustomization.isCustomBuild
                ? nil : PageMotion.contentReveal,
            value: browsePhase
        )
    }

    private enum BrowsePhase: Equatable {
        case loading, empty, loaded, failed
    }

    private var browsePhase: BrowsePhase {
        switch viewModel.state {
        case .idle, .loading: .loading
        case .empty: .empty
        case .loaded: .loaded
        case .failed: .failed
        }
    }

    /// Favorites in the personal build are movies on the universal watchlist.
    /// The provider's library payload does not reliably carry that local
    /// membership, so the card asks the same handler the detail heart uses.
    static func showsFavoriteBadge(
        customBuild: Bool,
        item: MediaItem?,
        isWatchlisted: (MediaItem) -> Bool
    ) -> Bool {
        guard customBuild, let item, item.kind == .movie else { return false }
        return isWatchlisted(item)
    }

    /// The personal build's poster rating is Emby's own community score only.
    /// No IMDb/TMDB/Rotten Tomatoes score, and no star or source icon.
    static func displayedRating(
        customBuild: Bool,
        item: MediaItem?
    ) -> ExternalRating? {
        guard customBuild, let item, item.kind == .movie else { return nil }
        return item.ratings.first { $0.source == .community }
    }

    @ViewBuilder
    private var queryControls: some View {
        if viewModel.showsFilterMenu {
            LibraryFilterMenu(
                filters: viewModel.filters, capabilities: viewModel.queryCapabilities, facets: viewModel.queryFacets,
                isLoading: viewModel.facetsLoading, hasError: viewModel.facetsError != nil,
                onChange: { value in Task { await viewModel.setFilters(value) } },
                onLoadFacets: { await viewModel.loadQueryFacetsIfNeeded() },
                onRetry: { Task { await viewModel.loadQueryFacetsIfNeeded(retry: true) } }
            )
            .frame(minWidth: 44, minHeight: 44)
        }
        if !viewModel.availableSortFields.isEmpty {
            sortControl
        }
    }

    private var gridColumns: [GridItem] {
        if PlozzCustomization.isCustomBuild {
            return viewModel.gridStyle == .landscape
                ? PlozziOSPosterGridStyle.landscapeColumns(
                    density: settings.density.density,
                    horizontalSizeClass: horizontalSizeClass,
                    isRunningOnMac: metrics.usesDesktopSizing,
                    spacing: gridSpacing
                )
                : PlozziOSPosterGridStyle.columns(
                    density: settings.density.density,
                    horizontalSizeClass: horizontalSizeClass,
                    dynamicTypeSize: dynamicTypeSize,
                    isRunningOnMac: metrics.usesDesktopSizing,
                    spacing: gridSpacing
                )
        }
        guard dynamicTypeSize.isAccessibilitySize else {
            if viewModel.gridStyle == .landscape {
                return settings.density.density.iOSLandscapeGridColumns(
                    horizontalSizeClass: horizontalSizeClass, isRunningOnMac: metrics.usesDesktopSizing
                )
            }
            return settings.density.density.iOSPosterGridColumns(
                horizontalSizeClass: horizontalSizeClass, isRunningOnMac: metrics.usesDesktopSizing
            )
        }
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible(), spacing: 16)]
        }
        let minimum = accessiblePosterWidth * settings.density.density.scale
        let desktopMinimum = viewModel.gridStyle == .landscape ? metrics.landscapeWidth : metrics.posterWidth
        return [GridItem(.adaptive(minimum: metrics.usesDesktopSizing ? max(minimum, desktopMinimum) : minimum), spacing: 16)]
    }

    private var gridSpacing: CGFloat {
        PlozziOSPosterGridStyle.spacing(metrics: metrics, cardStyle: cardStyle)
    }

    private var gridHorizontalPadding: CGFloat {
        guard PlozzCustomization.isCustomBuild else {
            return horizontalInset - posterArtworkInset
        }
        return PlozziOSPosterGridStyle.gridPadding(
            horizontalSizeClass: horizontalSizeClass,
            usesDesktopSizing: metrics.usesDesktopSizing,
            metrics: metrics,
            cardStyle: cardStyle
        )
    }

    /// Live scan/enrich progress for the media share backing THIS library, above
    /// the grid so it explains a wall that's short or still growing. Renders
    /// nothing for a server-backed library or an idle share, and does its own
    /// status lookup so progress ticks never reach the grid.
    ///
    /// Horizontally it lines up with the poster ARTWORK below it, not the grid's
    /// column edges: a card insets its artwork inside its own surface, so matching
    /// only the grid padding leaves the banner overhanging every poster by that
    /// inset. Matches the tvOS treatment exactly.
    @ViewBuilder
    private var scanBanner: some View {
        if viewModel.isMediaShare {
            ShareScanProgressBanner(
                status: scanStatus,
                shareID: viewModel.sourceServerID
            )
            .padding(.horizontal, horizontalInset)
        }
    }

    /// How far a grid card insets its artwork inside its own footprint.
    private var posterArtworkInset: CGFloat {
        cardStyle == .framed ? metrics.cardInset : metrics.borderlessCardSideMargin
    }

    private var horizontalInset: CGFloat {
        PlozziOSPageLayout.horizontalInset(for: horizontalSizeClass)
    }

    private var sortControl: some View {
        BrowseSortMenu(sort: viewModel.sort, fields: viewModel.availableSortFields) { sort in
            Task { await viewModel.setSort(sort) }
        }
        .accessibilityIdentifier("library-sort")
    }

}

private struct PlozziOSLibraryContentModeControl: View {
    let viewModel: LibraryBrowseViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        PlozzContentTabs(
            options: viewModel.availableContentModes, id: \.self,
            selection: viewModel.contentMode,
            horizontalInset: PlozziOSPageLayout.horizontalInset(for: horizontalSizeClass),
            title: { Text($0.displayName) },
            tabIdentifier: { "library-mode-\($0.rawValue)" }
        ) { mode in
            Task { await viewModel.setContentMode(mode) }
        }
        .accessibilityLabel("Show")
        .accessibilityIdentifier("library-content-mode")
    }
}

struct PlozziOSLibraryRecommendationRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var accessiblePosterWidth: CGFloat = 116
    let section: LibrarySection
    let spoilerSettings: SpoilerSettings
    let showsSeriesArtwork: Bool
    var continueWatchingLayout: ContinueWatchingCardLayout = .landscape
    let onSelect: (MediaItem, MediaArtworkZoomSource) -> Void

    var body: some View {
        let inset = PlozziOSPageLayout.horizontalInset(
            for: horizontalSizeClass, usesDesktopSizing: metrics.usesDesktopSizing
        )
        let style: PosterCardView.Style = section.id == "continueWatching"
            ? continueWatchingLayout.cardStyle
            : (section.style == .poster ? .poster : .landscape)
        PlozziOSMediaSection(
            title: section.displayName,
            artworkInset: cardStyle == .framed ? metrics.cardInset : 0
        ) {
            ScrollView(.horizontal) {
                LazyHStack(
                    alignment: .top,
                    spacing: PlozziOSMediaRailLayout.stackSpacing(metrics: metrics, cardStyle: cardStyle)
                ) {
                    ForEach(MediaRowView.uniqued(section.items), id: \.stablePresentationID) { item in
                        MediaArtworkZoomButton(id: item.stablePresentationID) { source in
                            onSelect(item, source)
                        } label: {
                            PlozziOSPosterCard(
                                item: item, style: style,
                                showsSeriesArtwork: showsSeriesArtwork,
                                spoilerSettings: spoilerSettings,
                                showsResumeChip: section.id == "continueWatching"
                            )
                            .frame(width: cardWidth(style: style))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal,
                            PlozziOSMediaRailLayout.artworkAlignedInset(inset, metrics: metrics, cardStyle: cardStyle),
                            for: .scrollContent)
            .plozziOSMediaRailClearance()
        }
    }

    private func cardWidth(style: PosterCardView.Style) -> CGFloat {
        let width = metrics.cardSlotWidth(for: style, cardStyle: cardStyle, showsSeriesArtwork: showsSeriesArtwork)
        return style == .poster && dynamicTypeSize.isAccessibilitySize
            ? max(width, accessiblePosterWidth)
            : width
    }
}

private struct PlozziOSLibraryItemCell: View {
    @Environment(PlozziOSAppModel.self) private var appModel
    let slot: LibrarySlot?
    let index: Int
    let generation: Int
    var style: PosterCardView.Style = .poster
    let provider: any MediaProvider
    var isCombinedLibrary = false
    /// Passed from the grid so a watchlist change re-evaluates membership even
    /// while the provider payload for this slot is unchanged.
    var favoriteStateRevision = 0
    let playlistOrigin: () -> VideoPlaylistPlaybackOrigin?
    let onAppear: () async -> Void
    let onDisappear: () -> Void

    var body: some View {
        Group {
            if let item = slot?.item {
                if let route = CollectionBrowseRoute(
                    item: item, fallbackAccountID: provider.session.server.id
                ) {
                    MediaArtworkZoomValueLink(
                        id: item.stablePresentationID, value: PlozziOSLibraryRoute(collection: route)
                    ) {
                        card
                    }
                    .buttonStyle(.plain)
                } else if let library = MediaFolderNavigation.library(
                    for: item,
                    providerKind: provider.kind
                ) {
                    NavigationLink(
                        value: PlozziOSLibraryRoute(
                            library: library,
                            accountID: library.sourceAccountID ?? provider.session.server.id
                        )
                    ) {
                        card
                    }
                    .buttonStyle(.plain)
                } else if isCombinedLibrary {
                    MediaArtworkZoomLink(id: item.stablePresentationID) {
                        PlozziOSItemPage(appModel: appModel, item: item)
                    } label: {
                        card
                    }
                    .buttonStyle(.plain)
                } else {
                    MediaArtworkZoomLink(id: item.stablePresentationID) {
                        PlozziOSItemDetailView(
                            appModel: appModel,
                            provider: provider,
                            item: item,
                            originSourceAccountID: item.sourceAccountID,
                            playlistOrigin: playlistOrigin()
                        )
                    } label: {
                        card
                    }
                    .buttonStyle(.plain)
                }
            } else {
                card
            }
        }
        .task(id: generation) { await onAppear() }
        .onDisappear(perform: onDisappear)
    }

    private var isFavorite: Bool {
        _ = favoriteStateRevision
        return PlozziOSLibraryGridView.showsFavoriteBadge(
            customBuild: PlozzCustomization.isCustomBuild,
            item: slot?.item,
            isWatchlisted: {
                appModel.mediaItemActionHandler.isWatchlisted($0) || $0.isFavorite
            }
        )
    }

    private var displayedRating: ExternalRating? {
        PlozziOSLibraryGridView.displayedRating(
            customBuild: PlozzCustomization.isCustomBuild,
            item: slot?.item
        )
    }

    private var card: some View {
        Group {
            if let item = slot?.item, item.kind == .folder {
                MediaFolderCardLabel(item: item)
            } else {
                PlozziOSPosterCard(
                    item: slot?.item,
                    style: style,
                    reservesSubtitleSpace: true,
                    isFavorite: isFavorite,
                    rating: displayedRating
                )
            }
        }
    }
}
#endif
