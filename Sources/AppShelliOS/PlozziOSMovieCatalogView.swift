#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI

/// One studio's or tag's movies in the current library.
///
/// Presented from a detail-page chip in its own navigation stack. A poster tap
/// pushes the normal detail page; the catalog stays behind it.
struct PlozziOSMovieCatalogView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: MovieCatalogViewModel
    @State private var navigatedItem: MediaItem?

    private let appModel: PlozziOSAppModel
    private let provider: any MediaProvider

    init(
        appModel: PlozziOSAppModel,
        provider: any MediaProvider,
        libraryID: String?,
        term: MovieCatalogTerm
    ) {
        self.appModel = appModel
        self.provider = provider
        _model = State(initialValue: MovieCatalogViewModel(
            term: term, provider: provider, libraryID: libraryID
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.items.isEmpty {
                    switch model.state {
                    case .idle, .loading:
                        loading
                    case .failed(let error):
                        failure(error)
                            .transition(.opacity)
                    case .loaded:
                        PlozzStateView(
                            icon: "film",
                            title: Text("No titles to show")
                        )
                        .transition(.opacity)
                    }
                } else {
                    Group {
                        grid
                        footer
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, PlozzCustomization.isCustomBuild
                ? PlozziOSMediaRailLayout.posterGridTopPadding
                : 8)
            .padding(.bottom, 24)
            .animation(
                reduceMotion || !PlozzCustomization.isCustomBuild
                    ? nil : PageMotion.contentReveal,
                value: model.items.isEmpty
            )
        }
        .background(AppBackground(palette: palette))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadFirstPage() }
        .navigationDestination(item: $navigatedItem) { item in
            PlozziOSItemDetailView(appModel: appModel, provider: provider, item: item)
        }
        .accessibilityIdentifier("movie-catalog-page")
    }

    private var pageInset: CGFloat {
        PlozziOSPageLayout.horizontalInset(
            for: horizontalSizeClass, usesDesktopSizing: metrics.usesDesktopSizing
        )
    }

    private var loading: some View {
        Group {
            if PlozzCustomization.isCustomBuild {
                VStack(alignment: .leading, spacing: 10) {
                    PlozzPosterGridSkeleton(
                        columns: gridColumns,
                        spacing: gridSpacing,
                        horizontalPadding: gridHorizontalPadding
                    )
                    if model.totalCount > 0 {
                        Text("\(model.scannedCount) / \(model.totalCount)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(palette.secondaryText)
                            .padding(.horizontal, pageInset)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView("Loading…")
                    if model.totalCount > 0 {
                        Text("\(model.scannedCount) / \(model.totalCount)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(.horizontal, pageInset)
            }
        }
        .transition(.opacity)
    }

    private func failure(_ error: AppError) -> some View {
        PlozzStateView(
            icon: "exclamationmark.triangle",
            title: Text("Unable to load details"),
            message: Text(error.userMessage)
        ) {
            Button("Retry") { Task { await model.loadFirstPage() } }
                .plozzActionButton()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: gridColumns,
                alignment: .leading,
                spacing: gridSpacing
            ) {
                ForEach(model.items, id: \.stablePresentationID) { item in
                    Button {
                        navigatedItem = item
                    } label: {
                        PlozziOSPosterCard(
                            item: item,
                            reservesSubtitleSpace: PlozzCustomization.isCustomBuild
                        )
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        Task { await model.loadMoreIfNeeded(currentItem: item) }
                    }
                }
            }
            .padding(.horizontal, gridHorizontalPadding)
        }
    }

    private var gridColumns: [GridItem] {
        if PlozzCustomization.isCustomBuild {
            return PlozziOSPosterGridStyle.columns(
                density: appModel.settings.density.density,
                horizontalSizeClass: horizontalSizeClass,
                dynamicTypeSize: dynamicTypeSize,
                isRunningOnMac: metrics.usesDesktopSizing,
                spacing: gridSpacing
            )
        }
        return [GridItem(
            .adaptive(
                minimum: metrics.posterWidth,
                maximum: metrics.posterWidth * 1.18
            ),
            spacing: metrics.gridSpacing
        )]
    }

    private var gridSpacing: CGFloat {
        PlozziOSPosterGridStyle.spacing(metrics: metrics, cardStyle: cardStyle)
    }

    private var gridHorizontalPadding: CGFloat {
        guard PlozzCustomization.isCustomBuild else { return pageInset }
        return PlozziOSPosterGridStyle.gridPadding(
            horizontalSizeClass: horizontalSizeClass,
            usesDesktopSizing: metrics.usesDesktopSizing,
            metrics: metrics,
            cardStyle: cardStyle
        )
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if let error = model.loadMoreError {
            VStack(spacing: 8) {
                Text(error.userMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await model.loadMore() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, pageInset)
        }
    }
}
#endif
