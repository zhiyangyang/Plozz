#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// The corner mark a card wears when the title behind it **isn't in your
/// library** — in search, discovery rows, a person's credits, or the in-player
/// cast panel.
///
/// Distinguishes absence, requestability, and an existing request:
///
/// - ``notInLibrary`` is purely informational. Most viewers will never run
///   Seerr, so for them an unowned title is simply not actionable, and the mark
///   only has to answer "why can't I play this?" before they select it.
/// - ``requestable`` is an affordance, shown only while Seerr is connected: the
///   title isn't yours *yet* and you can ask for it.
/// - ``requested`` indicates an existing pending or approved request, not another
///   invitation to submit the same title.
///
/// These sit in the artwork's **top-trailing** corner — the watch-status slot,
/// which is free here rather than contested: watch state cannot apply to a title
/// you don't have (you have neither watched it nor left it unwatched), so an
/// unowned card shows this instead of a check or an unwatched flag.
public enum MediaLibraryMark: Equatable, Sendable {
    /// Not in your library.
    case notInLibrary

    var systemImage: String {  // l10n:content — SF Symbol name, not copy
        "binoculars.fill"
    }

    public var accessibilityLabel: LocalizedStringResource {
        LocalizedStringResource(
            "libraryMark.notInLibrary",
            defaultValue: "Not in your library",
            comment: "Accessibility label for the corner mark on a poster whose title the viewer does not own."
        )
    }

    /// The mark for an item, or `nil` when it's an ordinary library title.
    ///
    /// A title you don't own remains worth flagging when Seerr is absent.
    /// While connected, existing requests take precedence over the plus.
    public static func mark(for item: MediaItem) -> MediaLibraryMark? {
        TitleClassifier.isNotOwnedForBadge(item) ? .notInLibrary : nil
    }
}

/// Paints a ``MediaLibraryMark`` on artwork.
///
/// A bare glyph — no chip, no ring, no material plate. Legibility comes from
/// ``MediaArtworkChromeScrim``, the same gradient Continue Watching cards already
/// put under their chrome, which the host card draws; anything else stacked on
/// top makes the mark read as a sticker sitting on the artwork rather than part
/// of the card. For the same reason it carries no drop shadow.
///
/// Rendered `.palette` rather than `.hierarchical`, with both layers named. The
/// symbols are white shapes on a white secondary layer (the plus's disc, the
/// binoculars' body), and hierarchical separates them only
/// by an alpha gap it picks itself — about half. Artwork bleeds through, and the
/// mark changes tone from poster to poster.
/// Naming that second layer as a **fixed grey** fixes both: the tone stays put
/// across artwork, and because the layer is now darker than the glyph rather than
/// the same white, it no longer competes with it.
public struct MediaLibraryMarkView: View {
    private let mark: MediaLibraryMark
    /// The rendered symbol's square slot, not its typographic point size.
    private let size: CGFloat

    /// Grey 50% at 70% opacity, chosen on-device from a 10-grey × 7-alpha matrix
    /// rendered at the in-player card's real size. Light enough to sit in the
    /// artwork, dark enough that the white glyph stays crisp on top of it.
    private static let secondaryLayer = Color(white: 0.5).opacity(0.7)

    public init(mark: MediaLibraryMark, size: CGFloat) {
        self.mark = mark
        self.size = size
    }

    public var body: some View {
        Image(systemName: mark.systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Self.secondaryLayer)
            .accessibilityLabel(Text(mark.accessibilityLabel))
    }

    /// One rule for the mark's size on any card: the watched badge's share of a
    /// standard poster (42 ÷ 280 = 15%) applied to the card's real width.
    ///
    /// A fixed point size can't work across both places this appears — the
    /// in-player cast poster is 167pt wide against the person page's 280 — so a
    /// mark comfortable on one would dominate the other. A ratio keeps its
    /// optical weight steady instead.
    public static func size(forCardWidth width: CGFloat) -> CGFloat {
        (width * (PlozzTheme.Metrics.watchedBadgeSize / PlozzTheme.Metrics.posterWidth)).rounded()
    }
}
#endif
