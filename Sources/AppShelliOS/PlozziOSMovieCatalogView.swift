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
    @Environment(\.themePalette) private var palette
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
                    case .loaded:
                        ContentUnavailableView(
                            "No titles to show",
                            systemImage: "film"
                        )
                    }
                } else {
                    grid
                    footer
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
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

    private func failure(_ error: AppError) -> some View {
        ContentUnavailableView {
            Label("Unable to load details", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.userMessage)
        } actions: {
            Button("Retry") { Task { await model.loadFirstPage() } }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(
                        minimum: metrics.posterWidth,
                        maximum: metrics.posterWidth * 1.18
                    ),
                    spacing: metrics.gridSpacing
                )],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(model.items, id: \.stablePresentationID) { item in
                    Button {
                        navigatedItem = item
                    } label: {
                        PlozziOSPosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        Task { await model.loadMoreIfNeeded(currentItem: item) }
                    }
                }
            }
            .padding(.horizontal, pageInset)
        }
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
