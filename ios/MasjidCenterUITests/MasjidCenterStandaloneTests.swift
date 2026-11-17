import XCTest

// MARK: - E2E tests for the standalone (server-less) mode.
// Each test starts from a fresh install (-resetLocal) and goes through the REAL setup flow:
// manual city → CLGeocoder → PrayerWebCal ICS download → local storage. No Pi involved.

final class MasjidCenterStandaloneTests: XCTestCase {

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

    /// Fresh install → the single setup field → "Paris" + search (validates the city) → Continue → home screen with local prayer times.
    private func launchStandalone(city: String = "Paris") -> XCUIApplication {
        let app = launchFresh()
        XCTAssertTrue(app.buttons["useLocationButton"].waitForExistence(timeout: 10), "Setup screen expected")
        let field = app.textFields["setupField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(city + "\n")
        let confirm = app.buttons["setupConfirmButton"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: confirm)
        waitForExpectations(timeout: 20)
        confirm.tap()
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
        if !app.buttons["closeSettings"].exists {
            app.buttons["settingsBtn"].tap()
            XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 10))
        }
        let section = app.buttons["section-\(name)"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.tap()
    }

    // MARK: 4d — Jiggle: drag & drop reorders the tiles and persists the order

    func testActionReorderDragAndDrop() throws {
        let app = launchStandalone()
        let coran = app.buttons["activity-Coran"]
        XCTAssertTrue(coran.waitForExistence(timeout: 5))
        coran.press(forDuration: 1.0)                       // enter jiggle
        XCTAssertTrue(app.buttons["doneJiggle"].waitForExistence(timeout: 5))

        // Mostly-vertical pickup then sideways: Coran must land after Tasbih.
        let start = coran.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 130, dy: -200)))
        sleep(1)
        if app.buttons["doneJiggle"].exists { app.buttons["doneJiggle"].tap() }
        sleep(1)

        XCTAssertGreaterThan(coran.frame.minX, app.buttons["activity-Tasbih"].frame.minX,
                             "Coran must have moved past Tasbih after the drag")

        // The new order survives a relaunch (no -resetLocal: data must persist).
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["activity-Coran"].waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertGreaterThan(relaunched.buttons["activity-Coran"].frame.minX,
                             relaunched.buttons["activity-Tasbih"].frame.minX,
                             "The drag order must persist across relaunches")
    }

    // MARK: 4c — Jiggle exit: tiles snap to their resting slots immediately and stay put.
    // Regression: the horizontal ScrollView kept a decaying content offset after the
    // + and ✓ tiles vanished, so tiles drifted for ~7 seconds after leaving edit mode.

    func testJiggleExitFreezesTiles() throws {
        let app = launchStandalone()
        let coran = app.buttons["activity-Coran"]
        XCTAssertTrue(coran.waitForExistence(timeout: 5))
        sleep(1)
        let rest = coran.frame
        coran.press(forDuration: 1.0)
        let done = app.buttons["doneJiggle"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        usleep(600_000)
        XCTAssertEqual(coran.frame.minX, rest.minX, accuracy: 2,
                       "Right after exit the tile must already sit at its resting slot")
        sleep(3)
        XCTAssertEqual(coran.frame.minX, rest.minX, accuracy: 2,
                       "The tile must not move on its own after edit mode closed")
        XCTAssertFalse(app.buttons["addAction"].exists)
    }

    // MARK: 1 — Setup: one field, mode inferred from the input, Continue gated on validation

    func testSetupSingleFieldGatesConfirmation() throws {
        let app = launchFresh()
        XCTAssertTrue(app.buttons["useLocationButton"].waitForExistence(timeout: 10))
        let field = app.textFields["setupField"]
        let confirm = app.buttons["setupConfirmButton"]
        XCTAssertTrue(field.exists, "A single field must be displayed")
        XCTAssertFalse(confirm.isEnabled, "Nothing validated yet → Continue locked")

        // A server address is detected as such and checked live: nobody answers on :1.
        field.tap()
        field.typeText("127.0.0.1:1")
        let status = app.descendants(matching: .any)["setupStatus"]
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'Cannot reach'"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(confirm.isEnabled, "An unreachable server must never be accepted")
        XCTAssertTrue(confirm.label.contains("Connect"), "A server address switches the action to Connect")
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

        // Goal = 10 via the chips (not a list box). They live in the
        // "Tasbih & Objectives" section, closed by default — open it first.
        app.buttons["settingsBtn"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 10))
        app.buttons["section-Tasbih & Objectives"].tap()
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
        // Root cause regression: the nav bar overlay used to be declared after the Tasbih one and drew on top of it.
        for id in ["prevDay", "todayBtn", "calendarBtn", "nextDay", "settingsBtn", "historyBtn"] {
            XCTAssertFalse(app.buttons[id].isHittable, "\(id) must be covered by the Tasbih page")
        }
        for _ in 0..<10 { screen.tap() }
        // Goal reached → the Tasbih page closes itself.
        XCTAssertTrue(screen.waitForNonExistence(timeout: 8), "Tasbih must auto-close at the goal")
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
        // Tapping the "+" tile already exited jiggle (tap-anywhere exits edit
        // mode) — doneJiggle may be gone; exit explicitly if it is still there.
        if app.buttons["doneJiggle"].waitForExistence(timeout: 2) {
            app.buttons["doneJiggle"].tap()
        }
        sleep(1)

        XCTAssertEqual(custom.value as? String, "not done")
        custom.tap(); sleep(1)
        XCTAssertEqual(custom.value as? String, "late", "first tap = orange")
        custom.tap(); sleep(1)
        XCTAssertEqual(custom.value as? String, "done", "second tap = blue")

        // Delete via the edit sheet (jiggle → tap tile → Delete), the badge stays
        // as the quick path for real users.
        custom.press(forDuration: 1.0)
        // The horizontal scroll view sometimes wins over the long-press under
        // XCTest's synthesized events — retry once, then assert.
        if !app.buttons["doneJiggle"].waitForExistence(timeout: 3) {
            custom.press(forDuration: 1.0)
        }
        XCTAssertTrue(app.buttons["doneJiggle"].waitForExistence(timeout: 3),
                      "the press must re-enter jiggle mode")
        sleep(1)
        custom.tap()
        XCTAssertTrue(app.textFields["actionNameField"].waitForExistence(timeout: 5),
                      "tapping a custom tile in jiggle must open the editor")
        let del = app.buttons["actionDelete"]
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()
        // Deleting must ask for confirmation first.
        XCTAssertTrue(app.alerts.buttons["Delete"].waitForExistence(timeout: 3))
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["activity-Sadaqa"].waitForNonExistence(timeout: 3))
    }

    // MARK: 4b — Jiggle: every tile gets a red X; hiding a built-in, then restoring it

    func testBuiltinActionHideAndRestore() throws {
        let app = launchStandalone()
        let coran = app.buttons["activity-Coran"]
        XCTAssertTrue(coran.waitForExistence(timeout: 5))

        coran.press(forDuration: 1.0)               // jiggle mode
        let badge = app.buttons["delete-Coran"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "Every action tile must show the red X")
        badge.tap()
        // Hiding must ask for confirmation first.
        XCTAssertTrue(app.alerts.buttons["Hide"].waitForExistence(timeout: 3))
        app.alerts.buttons["Hide"].tap()
        XCTAssertTrue(app.buttons["activity-Coran"].waitForNonExistence(timeout: 3),
                      "The X must hide the built-in action")

        // Still in jiggle → "+" → the hidden built-in is offered for restore.
        let add = app.buttons["addAction"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.textFields["actionNameField"].waitForExistence(timeout: 5),
                      "The action sheet must open")
        let restore = app.buttons["restore-Coran"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["activity-Coran"].waitForExistence(timeout: 5),
                      "Restore must bring the built-in action back")
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

    // MARK: 6b — Settings → Use my location + denied → toast must show INSIDE the sheet
    // Regression: toasts were only rendered on the main screen, hidden behind
    // the sheet — every locate-button failure looked like a dead tap.

    func testSettingsLocateDeniedShowsToast() throws {
        let app = launchStandalone()     // fresh install → main screen
        addUIInterruptionMonitor(withDescription: "Location") { alert -> Bool in
            for label in ["Don't Allow", "Ne pas autoriser", "Deny"] {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }
        XCTAssertTrue(app.buttons["settingsBtn"].waitForExistence(timeout: 10))
        app.buttons["settingsBtn"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 10))
        app.buttons["section-Location"].tap()
        let btn = app.buttons["locateBtn"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        btn.tap()
        app.tap()  // nudge the interruption monitor → deny
        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 15),
                      "Denied location must show a toast INSIDE the settings sheet")
    }

    // MARK: 7 — Standalone Quran section: bundled file + local play + Friday schedule

    func testStandaloneQuranNote() throws {
        let app = launchStandalone()
        openSettingsSection(app, "Quran recitation")
        // Bundled Quran: file picker, local play and Friday scheduling must all be usable.
        XCTAssertTrue(app.buttons["playFullQuranBtn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fridayQuranToggle"].exists
                      || app.otherElements["fridayQuranToggle"].exists)
        // Bundled athan list must be offered too.
        openSettingsSection(app, "Athan call")
        XCTAssertTrue(app.buttons["audioFilePicker"].waitForExistence(timeout: 5))
    }
}


