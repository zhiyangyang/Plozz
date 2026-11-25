import Foundation

/// Build-specific switches for the personal iPad customization.
///
/// These are keyed to the app's bundle identifier rather than a compile-time
/// constant so package tests and the canonical app keep their normal behaviour.
/// The custom app keeps the remaining optional feature modules linked but never
/// exposes or activates them at runtime.
public enum PlozzCustomization {
    /// The identity used by the personalized iPad build. A suffix (for example
    /// `--branded` builds) still counts as the custom app.
    public static let customBundleID = "dev.zhiyangyang.plozz"

    public static func isCustom(bundleIdentifier: String?) -> Bool {
        (bundleIdentifier ?? "").hasPrefix(customBundleID)
    }

    public static let isCustomBuild = isCustom(bundleIdentifier: Bundle.main.bundleIdentifier)

    public static var supportsTrackers: Bool { !isCustomBuild }

    /// The personal build opens a library directly on its Browse grid. Library
    /// mode tabs and the Recommended/Playlists/Collections pages stay upstream
    /// code, but are not exposed here.
    public static func showsLibraryRecommendations(customBuild: Bool = isCustomBuild) -> Bool {
        !customBuild
    }

    public static func showsLibraryPlaylists(customBuild: Bool = isCustomBuild) -> Bool {
        !customBuild
    }

    public static func showsLibraryCollections(customBuild: Bool = isCustomBuild) -> Bool {
        !customBuild
    }

    public static func showsLibraryModeTabs(customBuild: Bool = isCustomBuild) -> Bool {
        !customBuild
    }

    public static func libraryStartsOnBrowse(customBuild: Bool = isCustomBuild) -> Bool {
        customBuild
    }

    /// Collections move to a top-level destination in the personal build.
    public static func showsTopLevelCollections(customBuild: Bool = isCustomBuild) -> Bool {
        customBuild
    }

    /// The personal build defaults to exposing its Favorites entry, even when
    /// empty. The viewer can still hide it in Settings like any destination.
    public static func showsFavoritesTab(customBuild: Bool = isCustomBuild) -> Bool {
        customBuild
    }

    /// Favorites in the personal build are the server's favorite movies only.
    public static func favoritesOnlyMovies(customBuild: Bool = isCustomBuild) -> Bool {
        customBuild
    }

    /// Settings entries that only describe a page removed in the personal build.
    public static func isSettingsSearchEntryVisible(
        _ id: String,
        customBuild: Bool = isCustomBuild
    ) -> Bool {
        guard customBuild else { return true }
        switch id {
        case "library-tab-layout", "recommended-logo-size", "recommended-text-size",
             "recommended-row-layout", "recommended-row-covers":
            return false
        default:
            return true
        }
    }

    /// The personal movie detail page uses the server's native similar list and
    /// exposes tappable studio/tag chips. The old metadata-driven Related row is
    /// replaced by the native row.
    public static var showsEmbySimilar: Bool { isCustomBuild }
    public static var showsDetailTerms: Bool { isCustomBuild }
    public static var showsTagsInDetailHero: Bool { isCustomBuild }
    public static var showsDetailCredits: Bool { !isCustomBuild }

    /// The personal detail page keeps the hero, cast rail, extras and related
    /// titles, but drops the About, Ratings, Details, Crew and Playback blocks
    /// from the information band below the page.
    public static func showsDetailAbout(
        customBuild: Bool = PlozzCustomization.isCustomBuild
    ) -> Bool {
        !customBuild
    }

    public static func showsDetailRatings(
        customBuild: Bool = PlozzCustomization.isCustomBuild
    ) -> Bool {
        !customBuild
    }

    public static func showsDetailInformationGroup(
        id: String,
        customBuild: Bool = PlozzCustomization.isCustomBuild
    ) -> Bool {
        guard customBuild else { return true }
        switch id {
        case "details", "crew", "playback":
            return false
        default:
            return true
        }
    }

    /// Pages that only expose a disabled capability stay out of Settings search.
    public static func isSettingsSearchPageVisible(_ page: SettingsSearchPage) -> Bool {
        switch page {
        case .trackers:
            return supportsTrackers
        default:
            return true
        }
    }
}
