#if canImport(SwiftUI)
@testable import FeatureSettings
import CoreUI
import CoreModels
import XCTest

@MainActor
final class SettingsWorkspaceNavigationTests: XCTestCase {
    func testHomeCustomizationShortcutReplacesStalePagesWithoutGrowingTheStack() {
        let navigation = SettingsNavigationModel()
        navigation.path = [.appearance, .artwork]
        for _ in 0..<3 {
            navigation.openHomeCustomization()
            XCTAssertEqual(navigation.section, .customizeHome)
            XCTAssertEqual(navigation.path, [.customizeHome])
            XCTAssertTrue(navigation.enteringDetail)
            XCTAssertFalse(navigation.restoringSidebar)
            navigation.path.append(.searchResult("home-row-arrangement"))
        }
        navigation.returnToSidebar()
        XCTAssertTrue(navigation.path.isEmpty)
    }

    func testAdvancedPlaybackKeepsExternalPlayerWithoutRetiredConversionControls() throws {
        let suite = "AdvancedPlaybackSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let external = ExternalPlayerSettingsModel(defaults: defaults)
        let rows = PlaybackAdvancedSettingsView.rows(model: external)
        let expectedIDs = ["external-player"]
        XCTAssertEqual(rows.map(\.id), expectedIDs)
        XCTAssertEqual(rows.first?.presentation, .page)
        XCTAssertEqual(external.settings.player, .builtIn)
    }

    func testExternalPlayerKeepsAboutAndCustomDetailsBehindNestedPages() throws {
        let suite = "ExternalPlayerSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ExternalPlayerSettingsModel(defaults: defaults)
        let advanced = ExternalPlayerSettingsRows.advanced(model: model)
        XCTAssertEqual(advanced.map(\.id), ["external-player"])
        XCTAssertEqual(advanced.first?.presentation, .page)
        let external = try XCTUnwrap(advanced.first?.childRows?())
        XCTAssertEqual(external.map(\.id), ["default-player", "external-player-help", "custom-player"])
        XCTAssertEqual(external[1].presentation, .page)
        XCTAssertEqual(external.last?.presentation, .page)
        XCTAssertEqual(model.settings.player, .builtIn)
        model.settings.player = .infuse
        XCTAssertEqual(ExternalPlayerSettingsModel(defaults: defaults).settings.player, .infuse)
        XCTAssertNil(defaults.object(forKey: "com.plozz.playbackSettings"))
    }


    func testPlaybackIsTheInitialSectionAndSidebarOwnsEntry() {
        let navigation = SettingsNavigationModel()
        XCTAssertEqual(navigation.section, .playback)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertTrue(navigation.restoringSidebar)
        XCTAssertFalse(navigation.focusInDetail)
        XCTAssertFalse(navigation.isCategoryOpen)
    }

    func testChangingSectionClearsItsChildrenButRefocusingItDoesNot() {
        let navigation = SettingsNavigationModel()
        navigation.select(.appearance)
        navigation.path = [.navigationLayout]
        navigation.select(.appearance)
        XCTAssertEqual(navigation.path, [.navigationLayout])
        navigation.select(.playback)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertEqual(navigation.section, .playback)
    }

    func testReturningToCategoriesKeepsSectionAndDiscardsChildren() {
        let navigation = SettingsNavigationModel()
        navigation.select(.appearance)
        navigation.path = [.artwork]
        navigation.enterDetail()
        XCTAssertTrue(navigation.enteringDetail)
        XCTAssertFalse(navigation.focusInDetail, "A request is not native focus arrival.")
        XCTAssertFalse(navigation.restoringSidebar)
        navigation.returnToSidebar()
        XCTAssertEqual(navigation.section, .appearance)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertFalse(navigation.isCategoryOpen)
        XCTAssertFalse(navigation.focusInDetail)
        XCTAssertTrue(navigation.restoringSidebar)
    }

    func testSubtitlesOwnTheirStyleDestinationAndResetWithTheProfile() {
        let navigation = SettingsNavigationModel()
        navigation.select(.subtitles)
        XCTAssertFalse(navigation.isCategoryOpen)
        navigation.path = [.subtitleStyle]
        XCTAssertTrue(navigation.isCategoryOpen)
        navigation.select(.subtitles)
        XCTAssertEqual(navigation.path, [.subtitleStyle])
        navigation.select(.playback)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertFalse(navigation.isCategoryOpen)
        navigation.select(.subtitles)
        navigation.path = [.subtitleStyle]
        navigation.resetForProfile()
        XCTAssertEqual(navigation.section, .playback)
        XCTAssertFalse(navigation.isCategoryOpen)
        XCTAssertEqual(SettingsRoute.subtitles.access(
            activeProfileID: "child", isKids: true, isParentalSealed: true
        ), .allowed)
    }

    func testProfileOrAuthorizationResetDiscardsPriorDestinations() {
        let navigation = SettingsNavigationModel()
        navigation.select(.servers)
        navigation.path = [.server(key: "previous-profile-server")]
        navigation.appearanceRowID = "artwork"
        navigation.enterDetail()
        navigation.resetForProfile()
        XCTAssertEqual(navigation.section, .playback)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertNil(navigation.appearanceRowID)
        XCTAssertTrue(navigation.restoringSidebar)
        XCTAssertFalse(navigation.focusInDetail)
    }

    func testEveryCategoryIsTheFirstPageUntilExplicitReturn() {
        let navigation = SettingsNavigationModel()
        for route: SettingsRoute in [.playback, .myLibraries, .appearance, .screensNavigation, .subtitles, .metadata, .topShelf, .about] {
            navigation.select(route)
            navigation.enterDetail()
            XCTAssertEqual(navigation.path, [route])
            XCTAssertTrue(navigation.isCategoryOpen)
            navigation.focusInDetail = false
            navigation.enteringDetail = false
            XCTAssertTrue(navigation.isCategoryOpen, "Transient native focus loss must not reopen categories.")
            navigation.path.append(.about)
            XCTAssertTrue(navigation.isCategoryOpen)
            navigation.path.removeLast()
            XCTAssertEqual(navigation.path, [route])
            XCTAssertTrue(navigation.isCategoryOpen)
            navigation.returnToSidebar()
            XCTAssertFalse(navigation.isCategoryOpen)
            XCTAssertEqual(navigation.section, route)
        }
        navigation.path = [.artwork, .navigationLayout]
        XCTAssertTrue(navigation.isCategoryOpen)
    }

    func testHouseholdRoutesRemainUnavailableToKidsEvenAfterUnlock() {
        let routes: [SettingsRoute] = [
            .servers, .server(key: "server"), .profile, .parentalPIN, .topShelf,
            .metadata, .metadataDiagnostics,
            .profileSettings(profileID: "adult"),
            .profileAppearance(profileID: "adult"), .profileLockSetup(profileID: "adult")
        ]
        for route in routes {
            for sealed in [true, false] {
                XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: sealed),
                               .adultProfile, "\(route)")
            }
            XCTAssertEqual(route.access(activeProfileID: "adult", isKids: false, isParentalSealed: false),
                           .allowed, "\(route)")
        }
    }

    func testScreensKeepTheirNestedDestinationsAndProfileScope() {
        let navigation = SettingsNavigationModel()
        navigation.select(.screensNavigation)
        navigation.enterDetail()
        for route: SettingsRoute in [.customizeHome, .navigationLayout, .detailPage] {
            navigation.path.append(route)
            XCTAssertEqual(navigation.section, .screensNavigation)
            XCTAssertEqual(navigation.path, [.screensNavigation, route])
            XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: true), .allowed)
            navigation.path.removeLast()
        }
        navigation.resetForProfile()
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertEqual(navigation.section, .playback)
        XCTAssertEqual(SettingsRoute.language.access(
            activeProfileID: "child", isKids: true, isParentalSealed: true
        ), .allowed)
    }

    func testOnlySealedKidsRequirePINForTheirOwnRestrictedSettings() {
        for route: SettingsRoute in [
            .myLibraries, .plexUser(accountID: "account"), .serverUser(serverKey: "server"), .parentalPINSetup,
            .profileSettings(profileID: "child"), .profileLockSetup(profileID: "child")
        ] {
            XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: true),
                           .parentalPIN, "\(route)")
            XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: false),
                           .allowed, "\(route)")
        }
        XCTAssertEqual(SettingsRoute.profileAppearance(profileID: "child")
            .access(activeProfileID: "child", isKids: true, isParentalSealed: true), .allowed)
    }
}
#endif
