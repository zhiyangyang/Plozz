import Foundation
import XCTest
@testable import CoreModels

final class AppAdmissionPolicyTests: XCTestCase {
    func testFreshInstallRequiresAccountOrExplicitChoice() {
        XCTAssertFalse(AppAdmissionContext(hasMediaAccounts: false).canEnterApp)
        XCTAssertTrue(AppAdmissionContext(hasMediaAccounts: true).canEnterApp)
        XCTAssertTrue(AppAdmissionContext(
            hasMediaAccounts: false,
            explicitStandaloneChoice: true
        ).canEnterApp)
        XCTAssertTrue(AppAdmissionContext(
            hasMediaAccounts: true,
            explicitStandaloneChoice: true
        ).canEnterApp)
    }
}

@MainActor
final class AppAdmissionStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "AppAdmissionStoreTests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        return UserDefaults(suiteName: suite)!
    }

    func testMissingAndExplicitFalseRemainServerOnly() {
        let defaults = makeDefaults()
        let store = AppAdmissionStore(defaults: defaults)
        XCTAssertFalse(store.loadStandaloneChoice())
        defaults.set(false, forKey: AppAdmissionStore.standaloneChoiceKey)
        XCTAssertFalse(store.loadStandaloneChoice())
    }

    func testMalformedAndCoercibleFlagsNeverOptIn() {
        let defaults = makeDefaults()
        let store = AppAdmissionStore(defaults: defaults)
        let malformed: [Any] = [
            "true", "YES", "1", 1, 1.0, -1,
            ["enabled": true], [true], Data([1])
        ]
        for value in malformed {
            defaults.set(value, forKey: AppAdmissionStore.standaloneChoiceKey)
            XCTAssertFalse(store.loadStandaloneChoice(), "Must reject \(value)")
        }
    }

    func testChoicePersistsAcrossModelAndStoreRecreation() {
        let defaults = makeDefaults()
        let first = AppAdmissionModel(store: AppAdmissionStore(defaults: defaults))
        XCTAssertTrue(first.recordStandaloneChoice(isAvailable: true))

        let relaunched = AppAdmissionModel(store: AppAdmissionStore(defaults: defaults))
        XCTAssertTrue(relaunched.explicitStandaloneChoice)
        XCTAssertTrue(relaunched.context(
            hasMediaAccounts: false,
            standalonePlaybackAvailable: true
        ).canEnterApp)
    }

    func testUnavailableFeatureCannotPersistOrHonorStandaloneChoice() {
        let defaults = makeDefaults()
        let store = AppAdmissionStore(defaults: defaults)
        let model = AppAdmissionModel(store: store)
        XCTAssertFalse(model.recordStandaloneChoice(isAvailable: false))
        XCTAssertFalse(store.loadStandaloneChoice())

        XCTAssertTrue(model.recordStandaloneChoice(isAvailable: true))
        XCTAssertFalse(model.context(
            hasMediaAccounts: false,
            standalonePlaybackAvailable: false
        ).canEnterApp)
        XCTAssertTrue(model.context(
            hasMediaAccounts: true,
            standalonePlaybackAvailable: false
        ).canEnterApp)
    }

    func testSuccessfulSetupRecordsAdmission() {
        let defaults = makeDefaults()
        let store = AppAdmissionStore(defaults: defaults)
        let model = AppAdmissionModel(store: store)
        XCTAssertTrue(model.recordStandaloneChoice(isAvailable: true))
        XCTAssertTrue(model.explicitStandaloneChoice)
        XCTAssertTrue(store.loadStandaloneChoice())
        XCTAssertTrue(AppAdmissionModel(store: store).explicitStandaloneChoice)
    }

    func testRecordingSetupDoesNotOverrideAvailability() {
        let model = AppAdmissionModel(store: AppAdmissionStore(defaults: makeDefaults()))
        XCTAssertFalse(model.recordStandaloneChoice(isAvailable: false))
        XCTAssertFalse(model.explicitStandaloneChoice)
        XCTAssertTrue(model.recordStandaloneChoice(isAvailable: true))
        XCTAssertTrue(model.explicitStandaloneChoice)
    }

    func testProfileSetupDoesNotImplicitlyAdmitAnEmptyInstall() {
        let defaults = makeDefaults()
        let profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
        let model = AppAdmissionModel(store: AppAdmissionStore(defaults: defaults))
        XCTAssertEqual(profiles.activeProfile.name, "Me")
        profiles.markFirstRunProfileSetupComplete()
        XCTAssertFalse(model.context(
            hasMediaAccounts: false,
            standalonePlaybackAvailable: true
        ).canEnterApp)
    }

    func testExplicitDiagnosticResetRestoresFreshAdmissionAndNavigation() {
        let defaults = makeDefaults()
        let store = AppAdmissionStore(defaults: defaults)
        let model = AppAdmissionModel(store: store)
        model.recordStandaloneChoice(isAvailable: true)
        model.resetForDebugging()
        XCTAssertFalse(model.explicitStandaloneChoice)
        XCTAssertFalse(store.loadStandaloneChoice())
        XCTAssertTrue(model.recordStandaloneChoice(isAvailable: true))
        XCTAssertTrue(model.explicitStandaloneChoice)
    }

    func testStandaloneChoiceNeitherChangesProfilesNorFollowsTheirNamespace() throws {
        let defaults = makeDefaults()
        let profileStore = ProfileStore(defaults: defaults)
        let profiles = ProfilesModel(store: profileStore)
        var second = profiles.add(name: "Second")
        second.replaceLock(with: try XCTUnwrap(ProfileLock.make(pin: "1234", iterations: 64)))
        profiles.update(second)
        let originalProfiles = profiles.profiles
        let originalID = profiles.activeProfileID
        let originalRemembered = profiles.hasRememberedSelection
        let originalSetupComplete = profiles.firstRunProfileSetupComplete
        // Multiple profiles imply completed household setup without writing the
        // local first-run flag. Admission must preserve both distinct values.
        XCTAssertTrue(originalSetupComplete)
        XCTAssertFalse(profileStore.firstRunProfileSetupComplete())
        let model = AppAdmissionModel(store: AppAdmissionStore(defaults: defaults))

        XCTAssertTrue(model.recordStandaloneChoice(isAvailable: true))
        XCTAssertEqual(profiles.profiles, originalProfiles)
        XCTAssertEqual(profiles.activeProfileID, originalID)
        XCTAssertEqual(profiles.hasRememberedSelection, originalRemembered)
        XCTAssertEqual(profiles.firstRunProfileSetupComplete, originalSetupComplete)
        XCTAssertFalse(profileStore.firstRunProfileSetupComplete())

        profiles.select(second.id)
        XCTAssertEqual(profiles.activeNamespace, second.id)
        XCTAssertTrue(profiles.activeProfile.isLocked)
        XCTAssertTrue(model.context(
            hasMediaAccounts: false,
            standalonePlaybackAvailable: true
        ).canEnterApp)
        XCTAssertTrue(AppAdmissionStore(defaults: defaults).loadStandaloneChoice())
        XCTAssertNil(defaults.object(
            forKey: "\(AppAdmissionStore.standaloneChoiceKey).\(second.id)"
        ))
    }

    func testStandaloneChoiceLeavesSingleProfileConfirmationIncomplete() {
        let defaults = makeDefaults()
        let profileStore = ProfileStore(defaults: defaults)
        let profiles = ProfilesModel(store: profileStore)
        let model = AppAdmissionModel(store: AppAdmissionStore(defaults: defaults))
        XCTAssertEqual(profiles.profiles.count, 1)
        XCTAssertFalse(profiles.firstRunProfileSetupComplete)

        XCTAssertTrue(model.recordStandaloneChoice(isAvailable: true))

        XCTAssertTrue(model.context(
            hasMediaAccounts: false,
            standalonePlaybackAvailable: true
        ).canEnterApp)
        XCTAssertFalse(profiles.firstRunProfileSetupComplete)
        XCTAssertFalse(profileStore.firstRunProfileSetupComplete())
        XCTAssertEqual(profiles.activeProfile.name, "Me")
    }
}
