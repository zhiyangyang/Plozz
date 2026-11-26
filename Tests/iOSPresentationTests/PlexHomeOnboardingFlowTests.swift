#if os(iOS)
import CoreModels
import CoreUI
import FeatureAuth
import XCTest
@testable import AppRuntime
@testable import AppShelliOS

@MainActor
final class PlexHomeOnboardingFlowTests: XCTestCase {
    func testPlexUserSelectionContinuesThroughLibrariesAndAppearance() async throws {
        try await verifyOnboardingSelection(selectedIndex: 0)
        try await verifyOnboardingSelection(selectedIndex: 1)
    }

    private func verifyOnboardingSelection(selectedIndex: Int) async throws {
        let suite = "PlexHomeOnboardingFlow.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = PlozziOSAppModel(
            accountStore: AccountStore(secureStore: InMemorySecureStore()),
            profileStore: ProfileStore(defaults: defaults)
        )
        let users = [
            PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true, isAdmin: true),
            PlexHomeUser(id: "child", name: "Child", requiresPIN: false, isRestricted: true)
        ]
        app.plexHomeUsers.plexHomeUsersFetch = { _, _ in users }
        let authentication = AuthenticationGate()
        app.plexHomeUsers.plexHomeUserSwitch = { user, pin, _, _ in
            XCTAssertEqual(user, users[selectedIndex].id)
            XCTAssertEqual(pin, selectedIndex == 0 ? "2468" : nil)
            return await authentication.token()
        }
        app.plexHomeUsers.plexServerTokenResolve = { _, _, _ in "fixture-server" }
        let sessions = ["a", "b"].map {
            UserSession(
                server: MediaServer(
                    id: $0, name: $0, baseURL: URL(string: "https://\($0).example.invalid")!, provider: .plex
                ), userID: "owner", userName: "Owner", deviceID: "fixture", accessToken: "fixture-\($0)"
            )
        }
        XCTAssertTrue(app.persist(sessions))
        for _ in 0..<200 {
            if app.plexHomeUsers.pendingPlexUserSelection != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(app.plexHomeUsers.pendingPlexUserSelection)
        XCTAssertEqual(app.profiles.profiles.count, 1)
        authentication.permits = true
        app.selectPlexUserDuringOnboarding(users[selectedIndex])
        XCTAssertEqual(app.profiles.activeProfile.name, "Parent")
        for _ in 0..<200 {
            if app.pendingLibrarySelection != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(app.pendingLibrarySelection)
        XCTAssertNil(app.plexPINRequestForAppPresentation, "The library-selection surface owns its PIN prompt.")
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        if selectedIndex == 0 {
            XCTAssertEqual(app.plexHomeUsers.plexPINEntryAvailability, .available)
            XCTAssertEqual(authentication.calls, 0)
            XCTAssertTrue(app.accountsProviders.resolvedAccounts(withIDs: sessions.map(Account.stableID(for:))).isEmpty)
            app.completeLibrarySelection()
            XCTAssertNotNil(app.pendingLibrarySelection, "A pending PIN cannot be bypassed by completing the picker.")
            app.plexHomeUsers.submitPlexPIN("2468")
        }
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        XCTAssertNil(app.plexHomeUsers.pendingPlexPINRequest)
        XCTAssertEqual(app.accountsProviders.resolvedAccounts(withIDs: sessions.map(Account.stableID(for:))).count, 2)
        XCTAssertGreaterThan(authentication.calls, 0, "Authenticate the selected viewer before choosing libraries.")
        let callsBeforeAppearance = authentication.calls
        XCTAssertEqual(app.profiles.profiles.count, 1)
        XCTAssertFalse(app.profiles.firstRunProfileSetupComplete)
        app.completeLibrarySelection()
        XCTAssertEqual(app.pendingFirstRunStep, .theme)
        app.finishFirstRunThemeSelection()
        XCTAssertNil(app.pendingFirstRunStep)
        XCTAssertTrue(app.profiles.firstRunProfileSetupComplete)
        XCTAssertFalse(app.profiles.activeProfile.needsSetup)
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        XCTAssertNil(app.plexHomeUsers.pendingPlexPINRequest)
        XCTAssertEqual(authentication.calls, callsBeforeAppearance)
    }
}

@MainActor
private final class AuthenticationGate {
    var permits = false
    var calls = 0
    func token() -> String {
        XCTAssertTrue(permits, "Only the chosen viewer authenticates before library selection.")
        calls += 1
        return "fixture-cloud"
    }
}
#endif
