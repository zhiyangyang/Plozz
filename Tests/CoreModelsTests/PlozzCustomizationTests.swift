import XCTest
@testable import CoreModels

final class PlozzCustomizationTests: XCTestCase {
    func testCustomBundleIdentityMatchesExactAndSuffixedBuilds() {
        XCTAssertTrue(PlozzCustomization.isCustom(bundleIdentifier: "dev.zhiyangyang.plozz"))
        XCTAssertTrue(PlozzCustomization.isCustom(bundleIdentifier: "dev.zhiyangyang.plozz.branded"))
        XCTAssertFalse(PlozzCustomization.isCustom(bundleIdentifier: "com.thatcube.Plozz"))
        XCTAssertFalse(PlozzCustomization.isCustom(bundleIdentifier: nil))
    }

    func testCustomDetailPageOmitsOnlyRequestedInformationBlocks() {
        XCTAssertFalse(PlozzCustomization.showsDetailAbout(customBuild: true))
        XCTAssertFalse(PlozzCustomization.showsDetailRatings(customBuild: true))
        for id in ["details", "crew", "playback"] {
            XCTAssertFalse(
                PlozzCustomization.showsDetailInformationGroup(id: id, customBuild: true),
                "\(id) should be hidden on the custom detail page"
            )
        }
        XCTAssertTrue(
            PlozzCustomization.showsDetailInformationGroup(id: "availability", customBuild: true),
            "Release & Availability stays visible"
        )
    }

    func testCanonicalDetailPageKeepsEveryInformationBlock() {
        XCTAssertTrue(PlozzCustomization.showsDetailAbout(customBuild: false))
        XCTAssertTrue(PlozzCustomization.showsDetailRatings(customBuild: false))
        for id in ["availability", "details", "crew", "playback"] {
            XCTAssertTrue(
                PlozzCustomization.showsDetailInformationGroup(id: id, customBuild: false),
                "\(id) must stay visible for the canonical app"
            )
        }
    }

    func testCustomLibraryNavigationKeepsOnlyBrowseAndExposesTopLevelEntries() {
        XCTAssertFalse(PlozzCustomization.showsLibraryRecommendations(customBuild: true))
        XCTAssertFalse(PlozzCustomization.showsLibraryPlaylists(customBuild: true))
        XCTAssertFalse(PlozzCustomization.showsLibraryCollections(customBuild: true))
        XCTAssertFalse(PlozzCustomization.showsLibraryModeTabs(customBuild: true))
        XCTAssertTrue(PlozzCustomization.libraryStartsOnBrowse(customBuild: true))
        XCTAssertTrue(PlozzCustomization.showsTopLevelCollections(customBuild: true))
        XCTAssertTrue(PlozzCustomization.showsFavoritesTab(customBuild: true))
        XCTAssertTrue(PlozzCustomization.favoritesOnlyMovies(customBuild: true))
        XCTAssertFalse(PlozzCustomization.isSettingsSearchEntryVisible(
            "recommended-row-layout", customBuild: true
        ))
        XCTAssertTrue(PlozzCustomization.isSettingsSearchEntryVisible(
            "library-covers", customBuild: true
        ))
    }

    func testCanonicalLibraryNavigationRetainsUpstreamModes() {
        XCTAssertTrue(PlozzCustomization.showsLibraryRecommendations(customBuild: false))
        XCTAssertTrue(PlozzCustomization.showsLibraryPlaylists(customBuild: false))
        XCTAssertTrue(PlozzCustomization.showsLibraryCollections(customBuild: false))
        XCTAssertTrue(PlozzCustomization.showsLibraryModeTabs(customBuild: false))
        XCTAssertFalse(PlozzCustomization.libraryStartsOnBrowse(customBuild: false))
        XCTAssertFalse(PlozzCustomization.showsTopLevelCollections(customBuild: false))
        XCTAssertFalse(PlozzCustomization.showsFavoritesTab(customBuild: false))
        XCTAssertFalse(PlozzCustomization.favoritesOnlyMovies(customBuild: false))
    }

    func testDisableCloudFeaturesClearsEveryGate() throws {
        let suite = "PlozzCustomization.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let flag = SyncSetupFeatureFlag(defaults: defaults)
        flag.prepareForLaunch(hasExistingInstallation: false)
        XCTAssertTrue(flag.needsOnboardingChoice)

        flag.disableCloudFeatures()

        XCTAssertFalse(flag.needsOnboardingChoice)
        XCTAssertFalse(flag.needsLaunchPreparation)
        XCTAssertFalse(flag.isEnabled)
        XCTAssertFalse(flag.isInitialRestorationPending)
        XCTAssertFalse(flag.isManualSetupPending)
    }
}
