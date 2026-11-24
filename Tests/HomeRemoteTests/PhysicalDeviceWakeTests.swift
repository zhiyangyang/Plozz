import XCTest

/// Explicitly approved wake only. A completed call does not prove active rendering.
@MainActor
final class PhysicalDeviceWakeTests: XCTestCase {
    func testWakePhysicalAppleTVWithOneHomePress() throws {
        throw XCTSkip("Physical Apple TV wake only.")
    }

}
