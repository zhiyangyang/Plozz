#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI

/// The server's native "More Like This" rail on a movie detail page.
///
/// The row is intentionally silent until the server answers; an empty response
/// hides it rather than leaving a heading with no posters.
struct PlozziOSMoreLikeThisSection: View {
    @Environment(\.plozzCardStyle) private var cardStyle
    @State private var model: SimilarMoviesViewModel

    let inset: CGFloat
    let onSelect: (MediaItem, MediaArtworkZoomSource) -> Void

    init(
        item: MediaItem,
        provider: any MediaProvider,
        accountID: String?,
        inset: CGFloat,
        onSelect: @escaping (MediaItem, MediaArtworkZoomSource) -> Void
    ) {
        _model = State(initialValue: SimilarMoviesViewModel(
            seed: item, provider: provider, accountID: accountID
        ))
        self.inset = inset
        self.onSelect = onSelect
    }

    var body: some View {
        PlozziOSHomeRailLayout { metrics in
            if !model.items.isEmpty {
                PlozziOSMediaSection(
                    title: Text("More Like This"),
                    horizontalInset: inset,
                    artworkInset: cardStyle == .framed ? metrics.cardInset : 0
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(
                            alignment: .top,
                            spacing: PlozziOSMediaRailLayout.stackSpacing(
                                metrics: metrics, cardStyle: cardStyle
                            )
                        ) {
                            ForEach(model.items, id: \.stablePresentationID) { item in
                                card(
                                    item,
                                    width: metrics.cardSlotWidth(for: .poster, cardStyle: cardStyle)
                                )
                            }
                        }
                    }
                    .contentMargins(
                        .horizontal,
                        PlozziOSMediaRailLayout.artworkAlignedInset(
                            inset, metrics: metrics, cardStyle: cardStyle
                        ),
                        for: .scrollContent
                    )
                    .plozziOSMediaRailClearance()
                }
                .environment(\.plozzCardCaptionView, .related)
                .accessibilityIdentifier("detail-more-like-this")
            }
        }
        .task { await model.load() }
    }

    private func card(_ item: MediaItem, width: CGFloat) -> some View {
        MediaArtworkZoomButton(id: item.stablePresentationID) { source in
            onSelect(item, source)
        } label: {
            PlozziOSPosterCard(item: item)
                .frame(width: width)
        }
        .buttonStyle(.plain)
    }
}
#endif
