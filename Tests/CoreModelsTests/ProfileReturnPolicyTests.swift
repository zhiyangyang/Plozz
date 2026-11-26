import XCTest
@testable import CoreModels

final class ProfileReturnPolicyTests: XCTestCase {
    func testOnlyAHouseholdOfSeveralProfilesReturnsToThePicker() {
        let first = Profile(id: "first", name: "First")
        let second = Profile(id: "second", name: "Second")
        XCTAssertNil(ProfileReturnPolicy.delay(for: [], automaticallySignIn: false))
        XCTAssertNil(ProfileReturnPolicy.delay(for: [first], automaticallySignIn: false))
        XCTAssertEqual(ProfileReturnPolicy.delay(for: [first, second], automaticallySignIn: false), 300)
    }

    func testAutomaticSignInBypassesReturnPrompt() {
        let first = Profile(id: "first", name: "First")
        let second = Profile(id: "second", name: "Second")
        for profiles in [[], [first], [first, second]] {
            XCTAssertNil(ProfileReturnPolicy.delay(for: profiles, automaticallySignIn: true))
        }
    }
}
