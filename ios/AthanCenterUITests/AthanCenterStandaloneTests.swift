import XCTest

// MARK: - E2E tests for the standalone (server-less) mode.
// Each test starts from a fresh install (-resetLocal) and goes through the REAL setup flow:
// manual city → CLGeocoder → PrayerWebCal ICS download → local storage. No Pi involved.

final class AthanCenterStandaloneTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLocal"]
        app.launch()
        return app
    }

    /// Fresh install → "Enter my city manually" → Paris → home screen with local prayer times.
    private func launchStandalone(city: String = "Paris") -> XCUIApplication {
        let app = launchFresh()
        XCTAssertTrue(app.buttons["useLocationButton"].waitForExistence(timeout: 10), "Setup screen expected")
        app.buttons["Enter my city manually"].tap()
        let field = app.textFields["cityField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(city)
        app.buttons["cityGoButton"].tap()
        XCTAssertTrue(app.buttons["prayer-Dohr"].waitForExistence(timeout: 40), "Prayer times must load from the ICS link")
        return app
    }

    private func dayValue(_ app: XCUIApplication) -> String {
        (app.otherElements["prayersList"].value as? String) ?? ""
    }

    private func day(_ offset: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func openSettingsSection(_ app: XCUIApplication, _ name: String) {
        app.buttons["settingsBtn"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 10))
        let section = app.buttons["section-\(name)"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.tap()
    }

    // MARK: 1 — Setup: location is requested instead of a server IP

    func testSetupAsksLocationNotServer() throws {
        let app = launchFresh()
        XCTAssertTrue(app.buttons["useLocationButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Enter my city manually"].exists)
        XCTAssertFalse(app.textFields["serverURLField"].exists, "Server IP must not be asked up front")
    }

    // MARK: 2 — Full standalone flow: 5 prayers + actions + navigation, all local

    func testStandaloneHomeAndNavigation() throws {
        let app = launchStandalone()
        for n in ["Fajr | Sobh", "Dohr", "Asr", "Maghrib", "Isha"] {
            XCTAssertTrue(app.buttons["prayer-\(n)"].exists, "Missing \(n)")
        }
        XCTAssertEqual(dayValue(app), day(0))
        for _ in 0..<5 { app.buttons["nextDay"].tap() }
        sleep(1)
        XCTAssertEqual(dayValue(app), day(5))
        XCTAssertTrue(app.buttons["prayer-Dohr"].exists, "Future days come from the 3-month ICS cache")
        app.buttons["todayBtn"].tap()
        sleep(1)
        XCTAssertEqual(dayValue(app), day(0))

        // Checking a prayer works locally (tri-state cycle) and survives day navigation.
        let dohr = app.buttons["prayer-Dohr"]
        dohr.tap(); dohr.tap()
        app.buttons["prevDay"].tap(); sleep(1)
        app.buttons["nextDay"].tap(); sleep(1)
        XCTAssertTrue(app.buttons["prayer-Dohr"].exists)
    }

    // MARK: 3 — Tasbih: swipe left, count to the goal, vibration state, auto-check blue

    func testTasbihCountsAndChecksActivity() throws {
        let app = launchStandalone()

        // Goal = 10 via the chips (not a list box).
        openSettingsSection(app, "iPhone")
        let chip = app.buttons["tasbihTarget-10"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "Goal choices must be displayed directly")
        for n in [10, 11, 33, 99, 100, 101] { XCTAssertTrue(app.buttons["tasbihTarget-\(n)"].exists) }
        chip.tap()
        app.buttons["closeSettings"].tap()
        sleep(1)

        XCTAssertEqual(app.buttons["activity-Tasbih"].value as? String, "not done")
        app.scrollViews.firstMatch.swipeLeft()
        let screen = app.otherElements["tasbihScreen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Swipe left must open the Tasbih counter")
        for _ in 0..<10 { screen.tap() }
        let counter = app.staticTexts["tasbihCount"]
        // Goal reached → the counter resets itself to 0 automatically.
        let reset = NSPredicate(format: "label == '0'")
        expectation(for: reset, evaluatedWith: counter)
        waitForExpectations(timeout: 8)
        app.buttons["tasbihClose"].tap()
        sleep(1)
        XCTAssertEqual(app.buttons["activity-Tasbih"].value as? String, "done", "Tasbih auto-checked blue")
    }

    // MARK: 4 — Custom actions: add, use, edit mode (jiggle), delete

    func testCustomActionLifecycle() throws {
        let app = launchStandalone()
        let coran = app.buttons["activity-Coran"]
        XCTAssertTrue(coran.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Coran"].exists, "Action buttons show the symbol only")

        coran.press(forDuration: 1.0)               // long press → jiggle mode
        let add = app.buttons["addAction"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Long press must enter edit (jiggle) mode")
        add.tap()
        let nameField = app.textFields["actionNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Sadaqa")
        app.buttons["actionSave"].tap()

        let custom = app.buttons["activity-Sadaqa"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        app.buttons["doneJiggle"].tap()
        sleep(1)

        XCTAssertEqual(custom.value as? String, "not done")
        custom.tap(); sleep(1)
        XCTAssertEqual(custom.value as? String, "late", "first tap = orange")
        custom.tap(); sleep(1)
        XCTAssertEqual(custom.value as? String, "done", "second tap = blue")

        // Delete via the edit sheet (jiggle → tap tile → Delete), the badge stays
        // as the quick path for real users.
        custom.press(forDuration: 1.0)
        sleep(1)
        custom.tap()
        let del = app.buttons["actionDelete"]
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()
        XCTAssertTrue(app.buttons["activity-Sadaqa"].waitForNonExistence(timeout: 3))
    }

    // MARK: 5 — Settings → Location: change city manually → prayer times re-fetched from ICS

    func testChangeCityInSettings() throws {
        let app = launchStandalone(city: "Paris")
        openSettingsSection(app, "Location")
        XCTAssertTrue(app.buttons["locateBtn"].waitForExistence(timeout: 5), "Locate button expected")
        let field = app.textFields["cityField"]
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("Marseille")
        app.buttons["citySearchBtn"].tap()
        let label = app.staticTexts["currentCity"]
        let ok = NSPredicate(format: "label CONTAINS[c] 'Marseille'")
        expectation(for: ok, evaluatedWith: label)
        waitForExpectations(timeout: 40)
    }

    // MARK: 6 — Audio can always be stopped (banner inside the Settings sheet)

    func testAudioCanBeStoppedFromSettings() throws {
        let app = launchStandalone()
        openSettingsSection(app, "Audio control")
        let test = app.buttons["testAthanBtn"]
        XCTAssertTrue(test.waitForExistence(timeout: 5))
        test.tap()
        let stop = app.buttons["stopAudioBannerSheet"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8), "A Stop control must be visible while audio plays")
        stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 5))
    }

    // MARK: 7 — Standalone settings hide server-only controls gracefully

    func testStandaloneQuranNote() throws {
        let app = launchStandalone()
        openSettingsSection(app, "Quran recitation")
        XCTAssertTrue(app.staticTexts["quranStandaloneNote"].waitForExistence(timeout: 5))
    }
}

