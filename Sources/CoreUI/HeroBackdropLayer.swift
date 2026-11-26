#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreNetworking


public extension View {
    @ViewBuilder
    func preloadDetailBackdropOnFocus(for item: MediaItem?, isFocused: Bool) -> some View {
        self
    }
}

/// The shared, full-bleed hero **backdrop** treatment: a wide landscape image
/// with a mode-appropriate legibility scrim and a bottom dissolve that melts the
/// artwork into the app background. Detail pages share Home's fixed legibility
/// shading while retaining their own dissolve geometry.
///
/// It is deliberately *purely visual and layout-neutral*: it renders as the host
/// view's `.background`, ignores the tvOS overscan safe area, and never reports a
/// size that would inflate its parent's layout width — matching how the detail
/// hero hosts its backdrop.
///
public struct HeroBackdropLayer: View {
    @Environment(\.plozzArtworkPolicy) private var artworkPolicy
    /// Ordered candidate backdrop URLs (first that loads and is wide enough wins).
    private let references: [ArtworkReference]
    /// Last-resort async art lookup (e.g. TMDb fanart) when none of `urls` load.
    private let asyncFallbackURL: (@Sendable () async -> URL?)?
    /// The backdrop's rendered height (the caller scales this by any hero-height
    /// fraction / bottom extension before passing it in).
    private let height: CGFloat
    /// Legibility scrim tone — dark in dark mode (for light content), light in
    /// light mode (for dark content). Geometry is identical; only the tone flips.
    private let scrimTone: Color
    /// Layout-neutral vertical translation used by a receding hero. Applied before
    /// overscan breakout so the full artwork layer moves as one screen-pinned image.
    private let verticalOffset: CGFloat
    /// Fraction of the height at which the bottom dissolve *begins* (the image is
    /// fully opaque above it and fades to transparent by the bottom edge). The
    /// item **detail** hero melts into the page early (`0.33`) because content
    /// scrolls up over it; the **Home** hero fills the screen, so it keeps the
    /// artwork opaque far lower and only feathers the very bottom into the
    /// Continue Watching panel.
    private let dissolveStart: CGFloat
    /// Whether this layer breaks out of the tvOS overscan safe area itself. `true`
    /// (the detail hero + the single-image case) makes it span the physical screen
    /// edge to edge. `false` is used when the caller lays several backdrops side by
    /// side (the Home hero filmstrip): each cell must stay at its exact frame width
    /// so the strip tiles correctly, and the *container* applies the overscan
    /// breakout once for the whole strip.
    private let ignoresOverscan: Bool
    private let pinIdentity: String?
    private let lookupIdentity: String?
    /// Overrides the platform default for embedding and controlled comparisons.
    /// Unsupported tones/directions still retain the original analytic shading.
    private let prefersCachedScrim: Bool?
    public init(
        urls: [URL],
        asyncFallbackURL: (@Sendable () async -> URL?)? = nil,
        height: CGFloat,
        scrimTone: Color,
        verticalOffset: CGFloat = 0,
        dissolveStart: CGFloat = 0.33,
        ignoresOverscan: Bool = true,
        pinIdentity: String? = nil,
        lookupIdentity: String? = nil,
        prefersCachedScrim: Bool? = nil,
    ) {
        self.references = urls.map(ArtworkReference.remote)
        self.asyncFallbackURL = asyncFallbackURL
        self.height = height
        self.scrimTone = scrimTone
        self.verticalOffset = verticalOffset
        self.dissolveStart = dissolveStart
        self.ignoresOverscan = ignoresOverscan
        self.pinIdentity = pinIdentity
        self.lookupIdentity = lookupIdentity
        self.prefersCachedScrim = prefersCachedScrim
    }

    public init(
        references: [ArtworkReference],
        asyncFallbackURL: (@Sendable () async -> URL?)? = nil,
        height: CGFloat,
        scrimTone: Color,
        verticalOffset: CGFloat = 0,
        dissolveStart: CGFloat = 0.33,
        ignoresOverscan: Bool = true,
        pinIdentity: String? = nil,
        lookupIdentity: String? = nil,
        prefersCachedScrim: Bool? = nil,
    ) {
        self.references = references
        self.asyncFallbackURL = asyncFallbackURL
        self.height = height
        self.scrimTone = scrimTone
        self.verticalOffset = verticalOffset
        self.dissolveStart = dissolveStart
        self.ignoresOverscan = ignoresOverscan
        self.pinIdentity = pinIdentity
        self.lookupIdentity = lookupIdentity
        self.prefersCachedScrim = prefersCachedScrim
    }

    public var body: some View {
        FallbackAsyncImage(
            references: references,
            prefersLandscape: true,
            maxAspectRatio: 3.0,
            variant: .heroBackdrop,
            // Put a real image up while the 2000px pass decodes. Home's hero has
            // always done this; the detail hero opened onto a scrim instead.
            previewVariant: .heroPreview,
            artworkPolicy: artworkPolicy.forArea(.details).forPlacement(.detailBackdrop),
            asyncFallbackURL: asyncFallbackURL,
            pinIdentity: pinIdentity,
            lookupIdentity: lookupIdentity,
            content: ArtworkFillImage.init,
            placeholder: { ambientPlaceholder }
        )
        .reportingHeroArtwork(id: pinIdentity)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(scrim)
        .mask(dissolveMask)
        .offset(y: verticalOffset)
        // Break out of the tvOS overscan safe area so the backdrop spans the full
        // screen edge to edge — across the top too, otherwise the top overscan
        // inset shows through as a black bar above the artwork. Skipped when the
        // caller tiles several cells (the Home hero filmstrip) and applies the
        // breakout once at the container instead.
        .modifier(OverscanBreakout(enabled: ignoresOverscan))
    }

    /// Details have no rail: retain the softer upper corner for every navigation
    /// style, and reveal the shading before the foreground without moving it.
    private var scrim: some View {
        scrimContent
    }


    @ViewBuilder
    private var scrimContent: some View {
        if usesCachedScrim {
            HeroLegibilityTexture(tone: scrimTone)
        } else {
            analyticScrim
        }
    }

    private var usesCachedScrim: Bool {
        if let prefersCachedScrim { return prefersCachedScrim }
        return false
    }

    private var analyticScrim: some View {
        HeroLegibilityScrim(
            tone: scrimTone,
            edgePeak: 0.55,
            edges: [.leading, .bottom],
            sideDarkeningStart: 0.34
        )
    }

    /// Dissolves the backdrop's own alpha to transparent over the lower portion
    /// (top third stays a clean image) so the real app background shows straight
    /// through — a perfectly seamless transition with no second colour to mismatch.
    private var dissolveMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: dissolveStart),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Never put the outgoing thumbnail back under the incoming detail artwork.
    private var ambientPlaceholder: some View {
        LinearGradient(
            colors: [
                scrimTone.opacity(0.28),
                scrimTone.opacity(0.10)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Applies the tvOS overscan breakout only when `enabled`, so the same backdrop
/// view can either span the physical screen (detail hero / single image) or stay
/// within its given frame (a cell in the Home hero filmstrip).
private struct OverscanBreakout: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(edges: [.top, .horizontal])
        } else {
            content
        }
    }
}

#endif
