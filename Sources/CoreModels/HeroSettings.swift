import Foundation
import Observation

/// Per-profile configuration for the Home **hero** carousel (pure data model).
///
/// Everything about the hero is data, not hardcoded: whether it shows, which
/// sources feed it and in what order, how many items rotate, whether the
/// (phased-in) background trailer plays, and which libraries the Random source
/// draws from. This is what lets the default move with real feedback and lets a
/// user customise the hero later without a rewrite.
///
/// Decoding is deliberately lenient (`decodeIfPresent` with per-field
/// fallbacks) so that adding a new field in a later version reads back an older
/// persisted blob as "that field at its default" instead of failing the whole
/// decode and resetting every setting.
public struct HeroSettings: Codable, Equatable, Sendable {
    /// Enables the featured section where the selected style supports it.
    /// Disabling it does not change Classic versus Showcase rows.
    public var isEnabled: Bool

    /// The enabled sources, in carousel order. Empty means "nothing to show" —
    /// the hero hides itself even when `isEnabled`.
    public var sources: [HeroSourceKind]

    /// Maximum number of items the carousel rotates through (clamped to
    /// ``maxItemsRange``).
    public var maxItems: Int

    /// Whether the background trailer autoplay (phased-in) is allowed. The view
    /// exposes the slot regardless; this gates whether a trailer is resolved and
    /// played once that feature ships.
    public var trailersEnabled: Bool

    /// Whether previously completed movies, series, and episodes are excluded
    /// from every hero source.
    public var hideWatched: Bool

    /// Uses unseen/least-recently-shown picks instead of the established Watchlist order.
    /// Scores are optional Home chrome, independent of detail-page rating preferences.
    public var showsRatings: Bool
    public var ratingPreferences: DetailPageSettings

    /// The `AggregatedLibrary.key`s the Random source may draw from. **Empty
    /// means "all currently-visible libraries"** (the sensible default), so a
    /// fresh profile needs no configuration.
    public var randomLibraryKeys: Set<String>
    public var collections: [HeroCollectionSelection]

    /// Whether the carousel auto-advances on a timer.
    public var autoAdvance: Bool

    /// Seconds between auto-advances (clamped to ``autoAdvanceRange``).
    public var autoAdvanceSeconds: Int

    /// How Apple TV's Home is arranged. Other platforms always show the carousel.
    /// The persisted representation of independent Spotlight and row-style choices.
    /// Standalone Showcase has no featured section, even in legacy enabled blobs.
    public var style: HeroStyle

    /// Independent TV controls backed by the existing persisted layout values.
    public var spotlightEnabled: Bool {
        get { isEnabled && style != .followsFocus }
        set {
            guard newValue != spotlightEnabled else { return }
            let immersive = immersiveRows
            isEnabled = newValue
            style = immersive ? (newValue ? .heroShowcase : .followsFocus) : .carousel
        }
    }

    public var immersiveRows: Bool {
        get { style != .carousel }
        set {
            guard newValue != immersiveRows else { return }
            let spotlight = spotlightEnabled
            isEnabled = spotlight
            style = newValue ? (spotlight ? .heroShowcase : .followsFocus) : .carousel
        }
    }

    public var logoSize: HeroLogoSize
    public var showcaseLogoSize: HeroLogoSize
    public var textSize: HeroTextSize
    public var showcaseTextSize: HeroTextSize

    /// Legacy migration input. CardCaptionSettings now owns visual card labels.
    public var showsCardCaptions: Bool

    /// Fresh profiles use Spotlight + Showcase, library categories enabled, a
    /// modest rotation, and gentle auto-advance.
    public static let `default` = HeroSettings(
        isEnabled: true,
        sources: HeroSourceKind.allCases.filter { $0 != .collection },
        maxItems: 8,
        trailersEnabled: false,
        hideWatched: true,
        randomLibraryKeys: [],
        autoAdvance: true,
        autoAdvanceSeconds: 12,
        style: .heroShowcase
    )

    /// Allowed range for ``maxItems``.
    public static let maxItemsRange: ClosedRange<Int> = 1...20
    /// Allowed range for ``autoAdvanceSeconds``.
    public static let autoAdvanceRange: ClosedRange<Int> = 4...60

    public init(
        isEnabled: Bool,
        sources: [HeroSourceKind],
        maxItems: Int,
        trailersEnabled: Bool,
        hideWatched: Bool = true,
        showsRatings: Bool = false,
        ratingPreferences: DetailPageSettings = .default,
        randomLibraryKeys: Set<String>,
        autoAdvance: Bool,
        autoAdvanceSeconds: Int,
        style: HeroStyle = .carousel,
        logoSize: HeroLogoSize = .default,
        showcaseLogoSize: HeroLogoSize = .default,
        textSize: HeroTextSize = .default,
        showcaseTextSize: HeroTextSize = .default,
        showsCardCaptions: Bool = false,
        collections: [HeroCollectionSelection] = []
    ) {
        self.isEnabled = isEnabled
        // De-duplicate while preserving order so the picker can't persist a
        // source twice.
        var seen = Set<HeroSourceKind>()
        self.sources = sources.filter { seen.insert($0).inserted }
        self.maxItems = maxItems.clamped(to: HeroSettings.maxItemsRange)
        self.trailersEnabled = trailersEnabled
        self.hideWatched = hideWatched
        self.showsRatings = showsRatings
        self.ratingPreferences = ratingPreferences
        self.randomLibraryKeys = randomLibraryKeys
        self.collections = HeroCollectionSelection.normalized(collections)
        self.autoAdvance = autoAdvance
        self.autoAdvanceSeconds = autoAdvanceSeconds.clamped(to: HeroSettings.autoAdvanceRange)
        self.style = style
        self.logoSize = logoSize
        self.showcaseLogoSize = showcaseLogoSize
        self.textSize = textSize
        self.showcaseTextSize = showcaseTextSize
        self.showsCardCaptions = showsCardCaptions
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, sources, maxItems, trailersEnabled, hideWatched, showsRatings
        case ratingPreferences
        case randomLibraryKeys, autoAdvance, autoAdvanceSeconds
        case style, showsCardCaptions
        case logoSize, showcaseLogoSize
        case textSize, showcaseTextSize
        case offeredSourcesVersion
        case collections, collection
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HeroSettings.default
        // Flattens `decodeIfPresent`'s `T?` (and any thrown error) down to a
        // concrete value, falling back to the default when the key is absent,
        // null, or fails to decode — so a newly-added field reads as its default
        // from an older blob instead of failing the whole decode.
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(type, forKey: key)) ?? nil) ?? fallback
        }
        self.init(
            isEnabled: value(Bool.self, .isEnabled, d.isEnabled),
            sources: HeroSettings.adoptingNewSources(
                value([HeroSourceKind].self, .sources, d.sources),
                offeredVersion: value(Int.self, .offeredSourcesVersion, 0)
            ),
            maxItems: value(Int.self, .maxItems, d.maxItems),
            trailersEnabled: value(Bool.self, .trailersEnabled, d.trailersEnabled),
            hideWatched: value(Bool.self, .hideWatched, d.hideWatched),
            showsRatings: value(Bool.self, .showsRatings, d.showsRatings),
            ratingPreferences: value(DetailPageSettings.self, .ratingPreferences, d.ratingPreferences),
            randomLibraryKeys: value(Set<String>.self, .randomLibraryKeys, d.randomLibraryKeys),
            autoAdvance: value(Bool.self, .autoAdvance, d.autoAdvance),
            autoAdvanceSeconds: value(Int.self, .autoAdvanceSeconds, d.autoAdvanceSeconds),
            // Blobs predating layout selection used the carousel, not the fresh-profile default.
            style: value(HeroStyle.self, .style, .carousel),
            logoSize: value(HeroLogoSize.self, .logoSize, d.logoSize),
            showcaseLogoSize: value(HeroLogoSize.self, .showcaseLogoSize, d.showcaseLogoSize),
            textSize: value(HeroTextSize.self, .textSize, d.textSize),
            showcaseTextSize: value(HeroTextSize.self, .showcaseTextSize, d.showcaseTextSize),
            showsCardCaptions: value(Bool.self, .showsCardCaptions, d.showsCardCaptions),
            collections: c.contains(.collections)
                ? value([HeroCollectionSelection].self, .collections, [])
                : value(HeroCollectionSelection?.self, .collection, nil).map { [$0] } ?? []
        )
    }

    /// The generation of ``HeroSourceKind`` a stored selection was last offered.
    /// Bump when adding a case that existing profiles should pick up.
    static let currentOfferedSourcesVersion = 1

    /// Sources introduced since `offeredVersion` was written, appended to a stored
    /// selection.
    ///
    /// Settings persist the exact list the user chose, so a source added later would
    /// stay invisible forever to everyone who already has settings — the people most
    /// likely to want it. A case they were never shown can't be one they declined.
    ///
    /// The version is what makes this a **one-time** adoption, and it is load-
    /// bearing rather than bookkeeping: without it, "not in the stored list" reads
    /// identically whether the source is new or the user switched it off, so turning
    /// Recently Added off would silently switch it back on at the next load.
    ///
    /// Deliberately skipped when the stored list is empty: that means "hero off by
    /// source", and quietly repopulating it would switch the hero back on.
    static func adoptingNewSources(
        _ stored: [HeroSourceKind],
        offeredVersion: Int
    ) -> [HeroSourceKind] {
        guard !stored.isEmpty, offeredVersion < currentOfferedSourcesVersion else { return stored }
        let known = Set(stored)
        return stored + HeroSourceKind.allCases.filter {
            !known.contains($0) && introducedSinceInitialRelease.contains($0)
        }
    }

    /// Sources added after the original four. Only these are adopted into an
    /// existing selection — the first four predate any stored settings, so their
    /// absence is always a deliberate choice.
    static let introducedSinceInitialRelease: Set<HeroSourceKind> = [.recentlyAdded]

    /// Written alongside the values so a saved blob records which generation of
    /// ``HeroSourceKind`` its owner has been shown. Saving means the current source
    /// list was on screen, so anything absent from it was declined rather than
    /// unseen — which is what stops a switched-off source coming back.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(sources, forKey: .sources)
        try c.encode(maxItems, forKey: .maxItems)
        try c.encode(trailersEnabled, forKey: .trailersEnabled)
        try c.encode(hideWatched, forKey: .hideWatched)
        try c.encode(showsRatings, forKey: .showsRatings)
        try c.encode(ratingPreferences, forKey: .ratingPreferences)
        try c.encode(randomLibraryKeys, forKey: .randomLibraryKeys)
        try c.encode(HeroCollectionSelection.normalized(collections), forKey: .collections)
        try c.encode(autoAdvance, forKey: .autoAdvance)
        try c.encode(autoAdvanceSeconds, forKey: .autoAdvanceSeconds)
        try c.encode(style, forKey: .style)
        try c.encode(logoSize, forKey: .logoSize)
        try c.encode(showcaseLogoSize, forKey: .showcaseLogoSize)
        try c.encode(textSize, forKey: .textSize)
        try c.encode(showcaseTextSize, forKey: .showcaseTextSize)
        try c.encode(showsCardCaptions, forKey: .showsCardCaptions)
        try c.encode(Self.currentOfferedSourcesVersion, forKey: .offeredSourcesVersion)
    }

    /// Whether the given source is currently enabled.
    public func isEnabled(_ source: HeroSourceKind) -> Bool {
        sources.contains(source)
    }

    public mutating func setEnabled(_ source: HeroSourceKind, enabled: Bool) {
        var selected = Set(sources)
        if enabled { selected.insert(source) } else { selected.remove(source) }
        sources = HeroSourceKind.allCases.filter(selected.contains)
    }

    /// Whether the hero should actually render: switched on **and** has at least
    /// one enabled source.
    public var isActive: Bool {
        isEnabled && !sources.isEmpty
    }

    /// Whether Apple TV's rows use Showcase, independently of the featured hero.
    public var followsFocus: Bool {
        style == .followsFocus || style == .heroShowcase
    }

    public var hasFeaturedHero: Bool { style != .followsFocus && isActive }

    public func shouldShowRatings(for item: MediaItem, spoilerSettings: SpoilerSettings) -> Bool {
        showsRatings && !spoilerSettings.shouldHideRatings(for: item)
    }

    /// Whether honoring Hide Watched requires live external watch history beyond
    /// the already-resolved Continue Watching / Watchlist sources. Random-from-
    /// library and collections can surface titles whose current watch state is
    /// not already known, so this gates the extra provider watch-state fetch and
    /// the hero's `externalRefreshRevision` bump.
    public var requiresExternalWatchHistory: Bool {
        isActive && hideWatched
            && (isEnabled(.randomFromLibrary) || isEnabled(.collection))
    }
}

/// How the Home hero chooses what it shows.
public enum HeroStyle: String, Codable, CaseIterable, Sendable {
    /// A rotating spotlight of curated titles, with its own actions, above the rows.
    case carousel
    /// Whatever title is focused in the rows fills the screen; rows hold one position.
    case followsFocus
    /// A featured carousel above the focus-driven Showcase rows.
    case heroShowcase
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Persistence

/// Persists ``HeroSettings`` per profile, mirroring `UIDensitySettingsStore` /
/// `HomeLayoutStore`: the primary profile keeps an un-suffixed key so upgrading
/// installs inherit cleanly, and additional profiles pass their `Profile.id`.
public protocol HeroSettingsStoring: Sendable {
    func load() -> HeroSettings
    func save(_ settings: HeroSettings)
}

public final class HeroSettingsStore: HeroSettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, namespace: String? = nil) {
        self.defaults = defaults
        self.key = SettingsKey.scoped("com.plozz.heroSettings", namespace: namespace)
    }

    public func load() -> HeroSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(HeroSettings.self, from: data)
        else { return .default }
        return decoded
    }

    public func save(_ settings: HeroSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory store for tests and previews.
public final class InMemoryHeroSettingsStore: HeroSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: HeroSettings

    public init(_ initial: HeroSettings = .default) {
        self.settings = initial
    }

    public func load() -> HeroSettings {
        lock.lock(); defer { lock.unlock() }
        return settings
    }

    public func save(_ settings: HeroSettings) {
        lock.lock(); defer { lock.unlock() }
        self.settings = settings
    }
}

/// Observable wrapper so SwiftUI settings screens can two-way bind and have the
/// change persisted + broadcast. Mirrors `UIDensitySettingsModel`.
@MainActor
@Observable
public final class HeroSettingsModel {
    public var settings: HeroSettings {
        didSet { store.save(settings) }
    }

    private let store: HeroSettingsStoring

    public init(store: HeroSettingsStoring = HeroSettingsStore()) {
        self.store = store
        self.settings = store.load()
    }
}
