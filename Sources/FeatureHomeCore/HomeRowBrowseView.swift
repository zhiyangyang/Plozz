import CoreModels
import CoreUI
import SwiftUI

/// Both shells supply their normal cards and navigation; membership and controls
/// are shared so a Home shelf means the same thing on either platform.
public struct HomeRowBrowseView<Card: View>: View {
    @Bindable private var model: HomeRowBrowseModel
    private let columns: [GridItem]
    private let skeletonStyle: SkeletonCardView.Style
    private let card: (MediaItem) -> Card
    @Environment(\.locale) private var locale
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.plozzNavigationContentInset) private var navigationInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moreRequest = 0
    private struct LoadKey: Equatable {
        let query: HomeRowBrowseQuery
        let snapshot: [MediaItem]?
    }

    public init(
        model: HomeRowBrowseModel, columns: [GridItem],
        skeletonStyle: SkeletonCardView.Style = .poster,
        @ViewBuilder card: @escaping (MediaItem) -> Card
    ) {
        self.model = model
        self.columns = columns
        self.skeletonStyle = skeletonStyle
        self.card = card
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if model.query == model.appliedQuery {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                        ForEach(model.items, id: \.stablePresentationID) { item in
                            card(item)
                                .onAppear {
                                    if item.stablePresentationID == model.items.last?.stablePresentationID,
                                       model.hasMore, !model.isLoading, model.error == nil {
                                        moreRequest += 1
                                    }
                                }
                        }
                    }
                    .transition(.opacity)
                }
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error.userMessage)
                        Button("Retry") { moreRequest += 1 }
                    }
                } else if isGridLoading {
                    Group {
                        if PlozzCustomization.isCustomBuild {
                            PlozzPosterGridSkeleton(
                                columns: columns,
                                spacing: gridSpacing,
                                style: skeletonStyle
                            )
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .transition(.opacity)
                } else if model.hasMore {
                    Button("Load more") { moreRequest += 1 }
                        .onAppear { moreRequest += 1 }
                } else if model.items.isEmpty {
                    Text("No titles to show")
                        .plozzForeground(.secondary)
                }
            }
            .padding(.leading, gridHorizontalPadding + navigationInset)
            .padding(.trailing, gridHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, PlozziOSMediaRailLayout.posterGridBottomPadding)
            .animation(
                reduceMotion || !PlozzCustomization.isCustomBuild
                    ? nil : PageMotion.contentReveal,
                value: isGridLoading
            )
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("home-row-browser")
        .task(id: LoadKey(query: model.query, snapshot: model.liveSnapshot)) { await model.load() }
        .task(id: moreRequest) {
            guard moreRequest > 0, !model.isLoading else { return }
            await model.load()
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .mediaItemDidMutate) {
                if let mutation = MediaItemMutation.from(notification) { await model.applyMutation(mutation) }
            }
        }
        .onChange(of: model.scopeIsCurrent) { _, current in if !current { model.invalidate() } }
        #if os(iOS)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortControl.labelStyle(.iconOnly)
                filterControl.labelStyle(.iconOnly)
            }
        }
        #endif
    }


    private var horizontalPadding: CGFloat {
        20
    }

    /// The personal build aligns the See All wall's visible artwork with Home's
    /// page inset, using the same slot padding that subtracts the card's
    /// internal side margin.
    private var gridHorizontalPadding: CGFloat {
        #if os(iOS)
        guard PlozzCustomization.isCustomBuild else { return horizontalPadding }
        return PlozziOSMediaRailLayout.artworkAlignedInset(
            PlozziOSMediaRailLayout.pageInset(
                for: horizontalSizeClass,
                usesDesktopSizing: metrics.usesDesktopSizing
            ),
            metrics: metrics,
            cardStyle: cardStyle
        )
        #else
        return horizontalPadding
        #endif
    }

    private var isGridLoading: Bool {
        model.isLoading || model.query != model.appliedQuery
    }

    private var gridSpacing: CGFloat {
        #if os(iOS)
        PlozzCustomization.isCustomBuild
            ? PlozziOSMediaRailLayout.stackSpacing(metrics: metrics, cardStyle: cardStyle)
            : metrics.gridSpacing
        #else
        metrics.gridSpacing
        #endif
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        PlozzCustomization.isCustomBuild
            ? PlozziOSMediaRailLayout.posterGridTopPadding
            : 24
        #else
        24
        #endif
    }

    private var title: Text {
        if let localized = model.localizedTitle {
            if let suffix = model.titleSuffix { return Text(localized) + Text(verbatim: suffix) }
            return Text(localized)
        }
        return Text(verbatim: model.title)
    }

    private var heading: some View {
        title.font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("home-row-browser-title")
    }

    private var sortControl: some View {
        Menu {
            HomeContentSortOptions(query: $model.query)
        } label: {
            Label {
                Text(model.query.sortTitle)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .accessibilityLabel(Text("Sort: \(model.query.sortTitle)"))
        .accessibilityIdentifier("home-row-sort-menu")
    }

    private var filterControl: some View {
        BrowseFilterMenu(
            activeCount: model.query.activeFilterCount,
            summary: model.query.filterSummary(in: locale)
        ) {
            HomeContentFilterOptions(query: $model.query)
        }
        .accessibilityIdentifier("home-row-filter-menu")
    }

}
