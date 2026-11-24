#if os(iOS)
import CoreModels
import CoreUI
import SwiftUI

enum PlozziOSMediaLayout {
    static func metrics(
        density: UIDensity, dynamicTypeSize: DynamicTypeSize, isRunningOnMac: Bool
    ) -> PlozzMetrics {
        isRunningOnMac
            ? .desktop(density: density, dynamicTypeSize: dynamicTypeSize)
            : .touch(density: density, dynamicTypeSize: dynamicTypeSize)
    }

    static func episodeWidth(metrics: PlozzMetrics, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        metrics.usesDesktopSizing ? metrics.landscapeWidth : (sizeClass == .regular ? 360 : 300)
    }
}

/// One grid rhythm for every full-page poster wall in the personal build.
///
/// The custom iPad build uses five columns at regular width, an 18pt gutter on
/// both axes, and the same visible artwork edge Home and the library wall use.
/// Canonical builds keep their density-driven adaptive columns and their own
/// page-specific insets.
enum PlozziOSPosterGridStyle {
    /// Match the Home rails: the visible gap comes from the same card style and
    /// density, rather than a second fixed gutter just for grids.
    static func spacing(
        metrics: PlozzMetrics,
        cardStyle: CardStyle,
        customBuild: Bool = PlozzCustomization.isCustomBuild
    ) -> CGFloat {
        guard customBuild else {
            return PlozziOSMediaRailLayout.posterGridSpacing
        }
        return PlozziOSMediaRailLayout.stackSpacing(
            metrics: metrics,
            cardStyle: cardStyle
        )
    }

    static func columns(
        density: UIDensity,
        horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize,
        isRunningOnMac: Bool,
        spacing: CGFloat = PlozziOSMediaRailLayout.posterGridSpacing,
        customBuild: Bool = PlozzCustomization.isCustomBuild
    ) -> [GridItem] {
        guard customBuild else {
            return density.iOSPosterGridColumns(
                horizontalSizeClass: horizontalSizeClass, isRunningOnMac: isRunningOnMac
            )
        }
        if isRunningOnMac {
            let metrics = PlozzMetrics.desktop(density: density)
            return [GridItem(
                .adaptive(minimum: metrics.posterWidth, maximum: metrics.posterWidth * 1.18),
                spacing: spacing
            )]
        }
        guard horizontalSizeClass == .regular else {
            // Compact/split widths keep an adaptive wall; eight fixed columns
            // would be unreadable on a phone-width window.
            let minimum = max(86, CGFloat(116 * density.scale))
            return [GridItem(
                .adaptive(minimum: minimum, maximum: minimum * 1.55),
                spacing: spacing
            )]
        }
        // The Appearance card-size setting is the single source of truth for
        // how many columns a full-page poster wall gets. Standard density keeps
        // the library wall's roomier six-column default; every other setting
        // uses the same count as the provider Browse walls.
        let baseCount = density == .standard ? 6 : density.posterGridColumns
        let count = max(3, baseCount - (dynamicTypeSize.isAccessibilitySize ? 1 : 0))
        return Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
            count: count
        )
    }

    static func landscapeColumns(
        density: UIDensity,
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool,
        spacing: CGFloat = PlozziOSMediaRailLayout.posterGridSpacing,
        customBuild: Bool = PlozzCustomization.isCustomBuild
    ) -> [GridItem] {
        guard customBuild else {
            return density.iOSLandscapeGridColumns(
                horizontalSizeClass: horizontalSizeClass, isRunningOnMac: isRunningOnMac
            )
        }
        if isRunningOnMac {
            let metrics = PlozzMetrics.desktop(density: density)
            return [GridItem(
                .adaptive(minimum: metrics.landscapeWidth, maximum: metrics.landscapeWidth * 1.18),
                spacing: spacing
            )]
        }
        return [GridItem(
            .adaptive(minimum: horizontalSizeClass == .regular ? 240 : 160),
            spacing: spacing
        )]
    }

    static func pageInset(
        horizontalSizeClass: UserInterfaceSizeClass?,
        usesDesktopSizing: Bool
    ) -> CGFloat {
        PlozziOSMediaRailLayout.pageInset(
            for: horizontalSizeClass, usesDesktopSizing: usesDesktopSizing
        )
    }

    static func gridPadding(
        horizontalSizeClass: UserInterfaceSizeClass?,
        usesDesktopSizing: Bool,
        metrics: PlozzMetrics,
        cardStyle: CardStyle
    ) -> CGFloat {
        PlozziOSMediaRailLayout.artworkAlignedInset(
            pageInset(
                horizontalSizeClass: horizontalSizeClass,
                usesDesktopSizing: usesDesktopSizing
            ),
            metrics: metrics,
            cardStyle: cardStyle
        )
    }
}

struct PlozziOSPosterCard: View {
    let item: MediaItem?
    var style: PosterCardView.Style = .poster
    var artworkPolicy: CardArtworkPolicy = .standard
    /// Identify the card by its show — artwork plus logo — instead of by the
    /// item's own thumbnail. Continue Watching opts in.
    var showsSeriesArtwork: Bool = false
    /// Spoiler protection for the card's artwork and text. Defaulted so the many
    /// callers that show already-watched or non-episode content stay unchanged;
    /// surfaces that can show unwatched episodes pass the profile's real settings.
    var spoilerSettings: SpoilerSettings = .default
    /// Keeps grid rows aligned when neighboring cards have no metadata subtitle.
    var reservesSubtitleSpace: Bool = false
    /// Draws the resume chip (play glyph + progress + time remaining) over the
    /// artwork, with an optional download badge — the same treatment tvOS uses.
    var showsResumeChip: Bool = false
    /// Keeps the card's resume geometry while hiding unconfirmed cached progress.
    var showsResumeChipContent: Bool = true
    var downloadState: MediaDownloadBadgeState?
    /// Whether this card should wear the red favorite marker. The caller owns
    /// the membership source; library grids supply the universal watchlist
    /// answer so the card and its detail page cannot disagree.
    var isFavorite: Bool = false
    /// Emby's community score, shown as a compact number in the bottom-right.
    /// The caller filters to that source; no star or brand icon is drawn.
    var rating: ExternalRating?
    /// Visible "…" menu. Touch cards need it: press-and-hold is undiscoverable.
    var showsActionsMenu: Bool = false
    /// Caller-owned context cue drawn on the artwork (e.g. "Continues" on a
    /// Related entry that continues the story you're looking at).
    var statusCue: LocalizedStringResource?
    var isPendingRemoval: Bool = false
    var captionHorizontalInset: CGFloat?

    var body: some View {
        PosterCardView(
            item: item ?? placeholderItem,
            style: style,
            artworkPolicy: artworkPolicy,
            spoilerSettings: spoilerSettings,
            showsSeriesArtwork: showsSeriesArtwork,
            reservesSubtitleSpace: reservesSubtitleSpace,
            statusCue: statusCue.map { Text($0) },
            showsResumeChip: showsResumeChip,
            showsResumeChipContent: showsResumeChipContent,
            downloadState: downloadState,
            showsFavoriteBadge: isFavorite,
            rating: rating,
            showsActionsMenu: showsActionsMenu,
            isPendingRemoval: isPendingRemoval,
            captionHorizontalInset: captionHorizontalInset,
            action: {}
        )
        .redacted(reason: item == nil ? .placeholder : [])
        .allowsHitTesting(item != nil)
    }

    private var placeholderItem: MediaItem {
        MediaItem(
            id: "placeholder",
            title: "Loading…",
            kind: .folder
        )
    }
}

extension UIDensity {
    var iOSPosterMinimumWidth: CGFloat {
        max(86, CGFloat(116 * scale))
    }

    func iOSPosterGridColumns(
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool = false
    ) -> [GridItem] {
        if isRunningOnMac {
            let metrics = PlozzMetrics.desktop(density: self)
            return [GridItem(
                .adaptive(minimum: metrics.posterWidth, maximum: metrics.posterWidth * 1.18),
                spacing: metrics.gridSpacing
            )]
        }
        let minimumWidth = if horizontalSizeClass == .regular {
            max(108, CGFloat(144 * scale))
        } else {
            iOSPosterMinimumWidth
        }
        let spacing: CGFloat = horizontalSizeClass == .regular ? 16 : 12
        return [
            GridItem(
                .adaptive(
                    minimum: minimumWidth,
                    maximum: minimumWidth * 1.55
                ),
                spacing: spacing
            )
        ]
    }

    func iOSLandscapeGridColumns(
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool = false
    ) -> [GridItem] {
        if isRunningOnMac {
            let metrics = PlozzMetrics.desktop(density: self)
            return [GridItem(
                .adaptive(minimum: metrics.landscapeWidth, maximum: metrics.landscapeWidth * 1.18),
                spacing: metrics.gridSpacing
            )]
        }
        return [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 240 : 160), spacing: 12)]
    }

    func iOSHomeLibraryWidth(
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool = false
    ) -> CGFloat {
        isRunningOnMac
            ? PlozzMetrics.desktop(density: self).landscapeWidth
            : max(164, CGFloat((horizontalSizeClass == .regular ? 260 : 220) * scale))
    }
}
#endif
