import Foundation

/// Build-specific switches for the personal iPad customization.
///
/// These are keyed to the app's bundle identifier rather than a compile-time
/// constant so package tests and the canonical app keep their normal behaviour.
/// The custom app keeps the feature modules linked (which keeps upstream merges
/// small) but never exposes or activates these features at runtime.
public enum PlozzCustomization {
    /// The identity used by the personalized iPad build. A suffix (for example
    /// `--branded` builds) still counts as the custom app.
    public static let customBundleID = "dev.zhiyangyang.plozz"

    public static func isCustom(bundleIdentifier: String?) -> Bool {
        (bundleIdentifier ?? "").hasPrefix(customBundleID)
    }

    public static let isCustomBuild = isCustom(bundleIdentifier: Bundle.main.bundleIdentifier)

    public static var supportsCloudSync: Bool { !isCustomBuild }
    public static var supportsSyncSetup: Bool { !isCustomBuild }
    public static var supportsSeerr: Bool { !isCustomBuild }
    public static var supportsTrackers: Bool { !isCustomBuild }
    public static var supportsDiscover: Bool { !isCustomBuild }

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
        case .seerr:
            return supportsSeerr
        case .trackers:
            return supportsTrackers
        case .sync:
            return supportsSyncSetup
        default:
            return true
        }
    }

    /// Writes the cloud-off defaults before the app constructs its models, so
    /// first launch cannot present an iCloud prompt or start initial restoration.
    public static func applyLaunchDefaultsIfNeeded() {
        guard isCustomBuild else { return }
        SyncSetupFeatureFlag().disableCloudFeatures()
    }
}
