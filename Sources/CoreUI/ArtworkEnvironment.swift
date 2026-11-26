#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct ArtworkPresentationPolicy: Equatable, Sendable {
    public let area: ArtworkArea
    public let settings: ArtworkSettings
    public let placement: ArtworkPlacement?
    public let logoLanguage: String

    public init(
        area: ArtworkArea = .browse,
        settings: ArtworkSettings = .default,
        placement: ArtworkPlacement? = nil,
        logoLanguage: String = Locale.current.identifier
    ) {
        self.area = area
        self.settings = settings
        self.placement = placement
        self.logoLanguage = MetadataQuery.normalizedArtworkLanguage(logoLanguage)
    }

    public var prefersOnlineArtwork: Bool { settings.prefersOnlineArtwork(in: area, placement: placement) }
    public var prefersTextlessArtwork: Bool { settings.prefersTextlessArtwork(in: area) }

    public func references(for item: MediaItem, placement: ArtworkPlacement) -> [ArtworkReference] {
        settings.artworkReferences(for: item, placement: placement, in: area)
    }

    public var identity: String {
        "placement:\(placement?.rawValue ?? "_")"
            + "|preference:\(settings.preference(in: area).rawValue)"
            + "|artwork-language:\(logoLanguage)"
    }

    public func forArea(_ area: ArtworkArea) -> Self {
        Self(area: area, settings: settings, placement: placement, logoLanguage: logoLanguage)
    }

    public func forPlacement(_ placement: ArtworkPlacement?) -> Self {
        Self(area: area, settings: settings, placement: placement, logoLanguage: logoLanguage)
    }

    public var heroPolicy: Self {
        forArea(area == .recommended || area == .recommendedHero ? .recommendedHero : .home)
    }
}

private struct ArtworkSettingsKey: EnvironmentKey {
    static let defaultValue = ArtworkSettings.default
}

private struct ArtworkSourceReadyKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ArtworkAreaKey: EnvironmentKey {
    static let defaultValue: ArtworkArea? = nil
}

private struct LandscapeTitleLogoKey: EnvironmentKey {
    static let defaultValue = LandscapeTitleLogo.off
}

public extension EnvironmentValues {
    /// False while a detail's native/discovery source is still being established.
    /// Only artwork waits; navigation, text and playback retain their own readiness.
    var plozzArtworkSourceReady: Bool {
        get { self[ArtworkSourceReadyKey.self] }
        set { self[ArtworkSourceReadyKey.self] = newValue }
    }

    var plozzLandscapeTitleLogo: LandscapeTitleLogo {
        get { self[LandscapeTitleLogoKey.self] }
        set { self[LandscapeTitleLogoKey.self] = newValue }
    }

    var plozzArtworkSettings: ArtworkSettings {
        get { self[ArtworkSettingsKey.self] }
        set { self[ArtworkSettingsKey.self] = newValue }
    }

    var plozzArtworkArea: ArtworkArea? {
        get { self[ArtworkAreaKey.self] }
        set { self[ArtworkAreaKey.self] = newValue }
    }

    var plozzArtworkPolicy: ArtworkPresentationPolicy {
        let area: ArtworkArea
        if let explicit = plozzArtworkArea {
            area = explicit
        } else {
            switch plozzCardCaptionView {
            case .home, .homeLibraries: area = .homeRows
            case .recommended: area = .recommended
            case .search: area = .search
            case .watchlist: area = .watchlist
            case .related, .filmography, .extras: area = .details
            case .episodes: area = .episodes
            case .browse: area = .browse
            case .collections: area = .collections
            case .playlists: area = .playlists
            case .continueWatching: area = .continueWatching
            }
        }
        return ArtworkPresentationPolicy(
            area: area, settings: plozzArtworkSettings,
            logoLanguage: locale.identifier
        )
    }
}

struct ArtworkPolicyReader<Content: View>: View {
    let policy: ArtworkPresentationPolicy?
    @ViewBuilder var content: (ArtworkPresentationPolicy, Bool) -> Content
    @Environment(\.plozzArtworkPolicy) private var inheritedPolicy
    @Environment(\.plozzArtworkSourceReady) private var sourceReady

    var body: some View { content(policy ?? inheritedPolicy, sourceReady) }
}
#endif
