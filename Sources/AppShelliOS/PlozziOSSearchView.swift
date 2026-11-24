#if os(iOS)
import CoreModels
import FeatureSearchCore
import SwiftUI
import CoreUI

struct PlozziOSSearchView: View {
    private var navigationTitles = NavigationTitles()
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.plozziOSUsesVerticalToolbar) private var usesVerticalToolbar
    @Environment(\.plozziOSIsOverflowDestination) private var isOverflowDestination
    @Environment(\.hasVisibleSettingsNavigationEntry) private var hasVisibleSettingsNavigationEntry
    @FocusState private var isSearchFocused: Bool
    @State private var viewModel: SearchViewModel
    private let appModel: PlozziOSAppModel
    private let onShowSettings: () -> Void
    private let keepsNavigationBar: Bool

    init(
        appModel: PlozziOSAppModel,
        onShowSettings: @escaping () -> Void,
        keepsNavigationBar: Bool = false
    ) {
        self.appModel = appModel
        self.onShowSettings = onShowSettings
        self.keepsNavigationBar = keepsNavigationBar
        _viewModel = State(
            initialValue: SearchViewModel(
                accounts: appModel.accountsProviders.homeAccounts,
                identitySources: appModel.identityIndex.identitySourcesProvider,
                disabledLibraryKeys: { [weak appModel] in
                    appModel?.settings.homeVisibility.visibility.disabledKeys
                        ?? []
                },
                seerSearch: { [seer = appModel.seerService] query in
                    guard !OfflineMode.shared.isEnabled else { return [] }
                    return (try? await seer.search(query)) ?? []
                },
                seerRequestAvailability: { [seer = appModel.seerService] item in
                    guard !OfflineMode.shared.isEnabled else { return nil }
                    return await seer.requestAvailability(for: item)
                }
            )
        )
    }

    private var hidesNavigationBar: Bool {
        horizontalSizeClass == .compact && !keepsNavigationBar && !usesVerticalToolbar
    }

    var body: some View {
        VStack(spacing: 0) {
            PlozziOSSearchHeader(
                query: $viewModel.query,
                isFocused: $isSearchFocused,
                showsInlineSettingsAvatar: PlozzCustomization.isCustomBuild && hidesNavigationBar,
                onShowSettings: onShowSettings
            )
            .zIndex(1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
        }
        // Compact tabs do not need a second bar above the explicit Search header.
        // Regular-width iPad keeps the bar so the system sidebar toggle remains
        // reachable when the adaptable tab sidebar is collapsed.
        .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if PlozzCustomization.isCustomBuild {
                if usesVerticalToolbar
                    || (!hidesNavigationBar && !hasVisibleSettingsNavigationEntry && !isOverflowDestination) {
                    PlozziOSSettingsToolbarItem(action: onShowSettings)
                }
            } else if usesVerticalToolbar || isOverflowDestination {
                PlozziOSSettingsToolbarItem(action: onShowSettings)
            }
        }
        .navigationTitle(
            PlozzCustomization.isCustomBuild
                ? Text(verbatim: "")
                : (isOverflowDestination
                    ? navigationTitles(NavigationLibraryLayout.searchKey, default: Text("Search"))
                    : Text(verbatim: ""))
        )
        .toolbarTitleDisplayMode(.inline)
        .environment(\.plozzCardCaptionView, .search)
        .task(id: viewModel.query) {
            await viewModel.search()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemDidMutate)) { note in
            if let mutation = MediaItemMutation.from(note) {
                viewModel.applyWatchedState(mutation)
            } else {
                Task { await viewModel.search() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .identityIndexDidUpdate)) { _ in
            guard !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            Task { await viewModel.search() }
        }
    }

    private var resultsPageInset: CGFloat {
        PlozzCustomization.isCustomBuild
            ? PlozziOSPosterGridStyle.pageInset(
                horizontalSizeClass: horizontalSizeClass,
                usesDesktopSizing: metrics.usesDesktopSizing
            )
            : PlozziOSPageHeaderLayout.horizontalInset
    }

    private var resultsGridPadding: CGFloat {
        PlozzCustomization.isCustomBuild
            ? PlozziOSPosterGridStyle.gridPadding(
                horizontalSizeClass: horizontalSizeClass,
                usesDesktopSizing: metrics.usesDesktopSizing,
                metrics: metrics,
                cardStyle: cardStyle
            )
            : PlozziOSMediaRailLayout.artworkAlignedInset(
                PlozziOSPageHeaderLayout.horizontalInset, metrics: metrics, cardStyle: cardStyle
            )
    }

    private var resultsGridSpacing: CGFloat {
        PlozziOSPosterGridStyle.spacing(metrics: metrics, cardStyle: cardStyle)
    }

    private var resultsGridColumns: [GridItem] {
        PlozziOSPosterGridStyle.columns(
            density: appModel.settings.density.density,
            horizontalSizeClass: horizontalSizeClass,
            dynamicTypeSize: dynamicTypeSize,
            isRunningOnMac: metrics.usesDesktopSizing,
            spacing: resultsGridSpacing
        )
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch viewModel.state {
            case .idle:
                PlozzStateView(
                    icon: "magnifyingglass",
                    title: "Search your libraries",
                    message: "Find movies, TV shows, and episodes across your servers."
                )
                .transition(.opacity)
            case .loading:
                Group {
                    if PlozzCustomization.isCustomBuild {
                        ScrollView {
                            PlozzPosterGridSkeleton(
                                columns: resultsGridColumns,
                                spacing: resultsGridSpacing,
                                horizontalPadding: resultsGridPadding
                            )
                            .padding(.top, PlozziOSMediaRailLayout.posterGridTopPadding)
                            .padding(.bottom, PlozziOSMediaRailLayout.posterGridBottomPadding)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollClipDisabled()
                    } else {
                        ProgressView("Searching…")
                    }
                }
                .transition(.opacity)
            case .empty:
                ContentUnavailableView.search(text: viewModel.query)
                    .transition(.opacity)
            case let .failed(error):
                PlozzStateView(
                    icon: "exclamationmark.triangle",
                    title: Text("Search unavailable"),
                    message: Text(error.userMessage)
                ) {
                    Button("Try Again") {
                        Task { await viewModel.search() }
                    }
                    .plozzActionButton()
                }
                .transition(.opacity)
            case let .loaded(sections):
                results(sections)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion || !PlozzCustomization.isCustomBuild
                ? nil : PageMotion.contentReveal,
            value: searchPhase
        )
    }

    private enum SearchPhase: Equatable {
        case idle, loading, empty, failed, loaded
    }

    private var searchPhase: SearchPhase {
        switch viewModel.state {
        case .idle: .idle
        case .loading: .loading
        case .empty: .empty
        case .failed: .failed
        case .loaded: .loaded
        }
    }

    private func results(_ sections: [SearchSection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PlozziOSMediaRailLayout.sectionGap(metrics: metrics)) {
                ForEach(sections) { section in
                    PlozziOSMediaSection(
                        title: Text(section.title), horizontalInset: resultsPageInset,
                        onHeadingTap: { isSearchFocused = false }
                    ) {
                        LazyVGrid(
                            columns: resultsGridColumns,
                            spacing: resultsGridSpacing
                        ) {
                            ForEach(section.items) { item in
                                PlozziOSSearchResultCard(
                                    item: item,
                                    provider: provider(for: item)
                                )
                            }
                        }
                        .padding(.horizontal, resultsGridPadding)
                    }
                }
            }
            .padding(.top, PlozzCustomization.isCustomBuild
                ? PlozziOSMediaRailLayout.posterGridTopPadding
                : 16)
            .padding(.bottom, PlozzCustomization.isCustomBuild
                ? PlozziOSMediaRailLayout.posterGridBottomPadding
                : 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollClipDisabled()
    }

    private func provider(for item: MediaItem) -> (any MediaProvider)? {
        if let accountID = item.sourceAccountID {
            return appModel.accountsProviders.provider(forAccountID: accountID)
        }
        return appModel.accountsProviders.primaryProvider
    }
}

/// Keep a local Settings entry only when native navigation does not expose it.
private struct PlozziOSSearchHeader: View {
    private var navigationTitles = NavigationTitles()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hasVisibleSettingsNavigationEntry) private var hasVisibleSettingsNavigationEntry
    @Environment(\.plozziOSUsesVerticalToolbar) private var usesVerticalToolbar
    @Environment(\.plozziOSIsOverflowDestination) private var isOverflowDestination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.plozzMetrics) private var metrics
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    let showsInlineSettingsAvatar: Bool
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlozziOSPageHeader(
                PlozzCustomization.isCustomBuild
                    ? Text(verbatim: "")
                    : navigationTitles(NavigationLibraryLayout.searchKey, default: Text("Search"))
            ) {
                if !PlozzCustomization.isCustomBuild,
                   !hasVisibleSettingsNavigationEntry,
                   !usesVerticalToolbar,
                   !isOverflowDestination {
                    PlozziOSSettingsAvatarButton(action: onShowSettings)
                        .accessibilityIdentifier("search-settings-avatar")
                }
            }
            .padding(.bottom, hidesTitle ? 0 : 12)
            .frame(height: hidesTitle ? 0 : nil, alignment: .top)
            .opacity(hidesTitle ? 0 : 1)
            .allowsHitTesting(!hidesTitle)
            .accessibilityHidden(hidesTitle)

            HStack(spacing: PlozziOSPageHeaderLayout.actionSpacing) {
                searchField
                if isActive {
                    cancelButton
                        .transition(.opacity)
                }
                if showsInlineSettingsAvatar,
                   !hasVisibleSettingsNavigationEntry,
                   !usesVerticalToolbar,
                   !isOverflowDestination {
                    PlozziOSSettingsAvatarButton(action: onShowSettings)
                        .accessibilityIdentifier("search-settings-avatar")
                }
            }
            .padding(.horizontal, horizontalInset)
        }
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: isActive)
    }

    private var horizontalInset: CGFloat {
        guard PlozzCustomization.isCustomBuild else {
            return PlozziOSPageHeaderLayout.horizontalInset
        }
        return PlozziOSPosterGridStyle.pageInset(
            horizontalSizeClass: horizontalSizeClass,
            usesDesktopSizing: metrics.usesDesktopSizing
        )
    }

    private var searchField: some View {
        PlozzSearchField(
            text: $query,
            prompt: "Movies, shows, and episodes",
            focus: $isFocused,
            accessibilityLabel: "Search your libraries"
        )
        .frame(maxWidth: .infinity)
    }

    private var hidesTitle: Bool {
        PlozzCustomization.isCustomBuild || isActive || isOverflowDestination
    }

    private var isActive: Bool {
        isFocused || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cancelButton: some View {
        Button("Cancel search", systemImage: "xmark") {
            query = ""
            isFocused = false
        }
        .plozziOSPageAction()
    }

}

private struct PlozziOSSearchResultCard: View {
    @Environment(PlozziOSAppModel.self) private var appModel
    @ScaledMetric(relativeTo: .caption2) private var cueHeight: CGFloat = 16
    let item: MediaItem
    let provider: (any MediaProvider)?

    var body: some View {
        Group {
            if let provider {
                NavigationLink {
                    PlozziOSItemDetailView(
                        appModel: appModel,
                        provider: provider,
                        item: item,
                        seerService: appModel.seerService
                    )
                } label: {
                    card
                }
                .buttonStyle(.plain)
            } else {
                card
            }
        }
    }

    private var card: some View {
        let cue = SearchSection.availabilityCue(for: item)
        return VStack(alignment: .leading, spacing: 6) {
            PlozziOSPosterCard(
                item: item,
                reservesSubtitleSpace: PlozzCustomization.isCustomBuild,
                captionHorizontalInset: 0
            )
            if PlozzCustomization.isCustomBuild {
                Group {
                    if let cue {
                        Label(cue, systemImage: "rectangle.stack.badge.plus")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    } else {
                        Color.clear
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: cueHeight, alignment: .leading)
            } else if let cue {
                Label(cue, systemImage: "rectangle.stack.badge.plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }
}
#endif
