import XCTest

@MainActor
final class PlexHomeOnboardingInteractionTests: XCTestCase {
    func testLongImportedListStartsWithVisibleFocusAndScrollsToTheLastUser() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture", "--plex-home-long-list"]
        app.launch()
        defer { app.terminate() }
        assertPreviewCount(16, in: app)
        capture(app, name: "All Plex Home profiles before import")
        activate(app.buttons["plex-home-add-all"])
        let parent = app.buttons["plex-home-user-parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.contains(parent.frame), "Initial focus must be fully inside the viewport.")
        XCTAssertTrue(parent.isHittable)
        capture(app, name: "Long Plex Home list entry")
        let last = app.buttons["plex-home-user-viewer-13"]
        for _ in 0..<10 {
            if last.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(app.frame.contains(last.frame))
        capture(app, name: "Long Plex Home list last user")
        last.tap()
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "viewer-13:all")
    }

    private var app: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
    }

    func testAddAllTransitionsToUsersAndKeepsTheImportChoice() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture"]
        app.launch()
        defer { app.terminate() }
        assertPreviewCount(3, in: app)
        let addAll = app.buttons["plex-home-add-all"]
        XCTAssertTrue(addAll.waitForExistence(timeout: 10))
        capture(app, name: "Plex Home import choice")
        activate(addAll)
        let parent = app.buttons["plex-home-user-parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["plex-home-result"].exists)
        let name = parent.staticTexts["server-user-name"]
        let owner = parent.staticTexts["Account owner"]
        let pin = parent.staticTexts["PIN required"]
        XCTAssertTrue(name.exists)
        XCTAssertTrue(owner.exists)
        XCTAssertTrue(pin.exists)
        XCTAssertGreaterThanOrEqual(owner.frame.minY, name.frame.maxY)
        XCTAssertGreaterThanOrEqual(pin.frame.minY, name.frame.maxY)
        XCTAssertTrue(parent.frame.contains(name.frame))
        XCTAssertTrue(parent.frame.contains(owner.frame))
        XCTAssertTrue(parent.frame.contains(pin.frame))
        let shortName = app.buttons["plex-home-user-guest"].staticTexts["server-user-name"]
        XCTAssertEqual(name.frame.height, shortName.frame.height, accuracy: 1,
                       "Owner and PIN metadata must not force this name onto another line.")
        capture(app, name: "Plex Home viewer choice")
        activate(parent)
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "parent:all")
    }

    func testBackChangesImportChoiceWithoutCompletingSetup() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture"]
        app.launch()
        defer { app.terminate() }
        activate(app.buttons["plex-home-just-me"])
        let parent = app.buttons["plex-home-user-parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        let back = app.buttons["plex-home-back"]
        if !back.waitForExistence(timeout: 2) { app.scrollViews.firstMatch.swipeUp() }
        activate(back)
        activate(app.buttons["plex-home-add-all"])
        activate(app.buttons["plex-home-user-parent"])
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "parent:all")
    }

    func testReducedMotionRetainsChoicesAndUserSelection() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture", "--plex-home-reduce-motion"]
        app.launch()
        defer { app.terminate() }
        activate(app.buttons["plex-home-just-me"])
        activate(app.buttons["plex-home-user-child"])
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "child:one")
    }

    private func activate(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    private func assertPreviewCount(_ count: Int, in app: XCUIApplication) {
        let avatars = app.images.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "plex-home-preview-"
        ))
        XCTAssertTrue(avatars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(avatars.count, count)
        for avatar in avatars.allElementsBoundByIndex {
            XCTAssertTrue(app.frame.contains(avatar.frame), "Every profile preview should fit on screen.")
        }
    }


    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
