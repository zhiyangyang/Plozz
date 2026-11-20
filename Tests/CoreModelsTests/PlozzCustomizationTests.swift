import XCTest
@testable import CoreModels

final class PlozzCustomizationTests: XCTestCase {
    func testCustomBundleIdentityMatchesExactAndSuffixedBuilds() {
        XCTAssertTrue(PlozzCustomization.isCustom(bundleIdentifier: "dev.zhiyangyang.plozz"))
        XCTAssertTrue(PlozzCustomization.isCustom(bundleIdentifier: "dev.zhiyangyang.plozz.branded"))
        XCTAssertFalse(PlozzCustomization.isCustom(bundleIdentifier: "com.thatcube.Plozz"))
        XCTAssertFalse(PlozzCustomization.isCustom(bundleIdentifier: nil))
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
