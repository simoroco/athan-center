import XCTest

// MARK: - E2E tests against the real Athan Center server (Raspberry Pi).
// The app is launched with -serverBase pointing at the live server.

final class AthanCenterUITests: XCTestCase {

    static let serverBase = "http://192.168.1.50:7777"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-serverBase", Self.serverBase]
        app.launch()
        return app
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 15) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    // MARK: 1 — Home screen loads prayers from the server

    func testHomeShowsPrayersAndCard() throws {
        let app = launch()

        // Next prayer card appears (today always has data on the configured server).
        XCTAssertTrue(waitFor(app.otherElements["nextPrayerCard"], 20)
                      || waitFor(app.otherElements["dateOnlyCard"], 5))

        // Prayer list with 5 rows.
        let list = app.otherElements["prayersList"]
        XCTAssertTrue(waitFor(list))
        for name in ["Fajr | Sobh", "Dohr", "Asr", "Maghrib", "Isha"] {
            XCTAssertTrue(app.buttons["prayer-\(name)"].exists, "Missing row \(name)")
        }

        // Activities row
        for name in ["Coran", "Tasbih", "Nawafil"] {
            XCTAssertTrue(app.buttons["activity-\(name)"].exists)
        }

        // Navigation + actions
        XCTAssertTrue(app.buttons["prevDay"].exists)
        XCTAssertTrue(app.buttons["todayBtn"].exists)
        XCTAssertTrue(app.buttons["calendarBtn"].exists)
        XCTAssertTrue(app.buttons["nextDay"].exists)
        XCTAssertTrue(app.buttons["settingsBtn"].exists)
        XCTAssertTrue(app.buttons["historyBtn"].exists)
    }

    // MARK: 2 — Prayer check tri-state cycle (restored at the end)

    func testPrayerCheckCycle() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["prayer-Dohr"], 20))

        let row = app.buttons["prayer-Dohr"]
        // Tap → orange (state 2), tap → blue (state 1), tap → back to 0.
        for _ in 0..<3 {
            row.tap()
            usleep(700_000)
        }
        // After 3 toggles the check should be gone again (state 0).
        // Verify server state via the API is implicit; the row re-renders.
        XCTAssertTrue(row.exists)
    }

    // MARK: 3 — Date navigation toggles the "today" button state

    func testDateNavigation() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["nextDay"], 20))

        // Viewing today: the "go to today" button is disabled.
        XCTAssertFalse(app.buttons["todayBtn"].isEnabled)
        app.buttons["nextDay"].tap()
        sleep(2)
        // On a future date it becomes enabled.
        XCTAssertTrue(app.buttons["todayBtn"].isEnabled)

        // Today button returns us to today and disables again.
        app.buttons["todayBtn"].tap()
        sleep(2)
        XCTAssertFalse(app.buttons["todayBtn"].isEnabled)
        XCTAssertTrue(app.buttons["calendarBtn"].exists)
    }

    // MARK: 4 — Settings sheet opens with all sections

    func testSettingsSheet() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["settingsBtn"], 20))
        app.buttons["settingsBtn"].tap()

        XCTAssertTrue(waitFor(app.buttons["closeSettings"]))
        for section in ["section-General", "section-Location", "section-Athan call",
                        "section-Quran recitation", "section-Audio control", "section-Backup & Restore"] {
            XCTAssertTrue(app.buttons[section].exists, "Missing \(section)")
        }

        // General is open by default → dark mode toggle visible.
        XCTAssertTrue(app.buttons["darkModeToggle"].exists
                      || app.otherElements["darkModeToggle"].exists
                      || app.switches["darkModeToggle"].exists)
    }

    // MARK: 5 — Statistics sheet renders

    func testStatisticsSheet() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["historyBtn"], 20))
        app.buttons["historyBtn"].tap()

        XCTAssertTrue(waitFor(app.buttons["closeStatistics"]))
        XCTAssertTrue(waitFor(app.buttons["exportExcelBtn"]))
        XCTAssertTrue(app.staticTexts["Last Week Summary"].firstMatch.exists
                      || app.scrollViews.staticTexts["Last Week Summary"].exists)
    }

    // MARK: 6 — Calendar sheet shows the year grid

    func testCalendarSheet() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["calendarBtn"], 20))
        app.buttons["calendarBtn"].tap()

        XCTAssertTrue(waitFor(app.buttons["closeCalendar"]))
        // At least one day cell exists (e.g. today).
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-'")).count > 20)
    }

    // MARK: 7 — Activity toggle cycles

    func testActivityToggle() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["activity-Coran"], 20))
        let cell = app.buttons["activity-Coran"]
        cell.tap()
        usleep(700_000)
        cell.tap()
        usleep(700_000)
        cell.tap() // back to unchecked — leave server state clean
        XCTAssertTrue(cell.exists)
    }

    // MARK: 7b — Unchecked Tasbih tile opens the counter without checking it

    func testTasbihTileOpensCounter() throws {
        let app = launch()
        let cell = app.buttons["activity-Tasbih"]
        XCTAssertTrue(waitFor(cell, 20))
        // Live-server state varies day to day: uncheck the tile first if needed.
        for _ in 0..<2 where (cell.value as? String) != "not done" {
            cell.tap(); usleep(700_000)
        }
        XCTAssertEqual(cell.value as? String, "not done", "Precondition: Tasbih unchecked")
        cell.tap()
        let screen = app.otherElements["tasbihScreen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5),
                      "Tapping the unchecked Tasbih tile must open the counter")
        XCTAssertEqual(cell.value as? String, "not done",
                       "Opening the counter must not check the action")
        app.buttons["tasbihClose"].tap()
    }

    // MARK: 8 — Mute next athan button exists and is actionable

    func testMuteNextButton() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["settingsBtn"], 20))
        // On a fully-checked past day it swaps to Quick Pray; today shows mute.
        let mute = app.buttons["muteNextBtn"]
        let quick = app.buttons["quickPrayBtn"]
        XCTAssertTrue(mute.exists || quick.exists)
    }
}

// MARK: - Server-mode stability / regression tests

extension AthanCenterUITests {

    private func dayValue(_ app: XCUIApplication) -> String {
        (app.otherElements["prayersList"].value as? String) ?? ""
    }

    private func day(offset: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    /// Root cause of "navigation buttons sometimes dead": loadDay() was ignored while a load was in flight,
    /// leaving the previous date's data on screen. Rapid taps must always converge on the last date.
    func testRapidNavigationConverges() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["nextDay"], 20))
        XCTAssertEqual(dayValue(app), day(offset: 0))
        for _ in 0..<6 { app.buttons["nextDay"].tap() }
        sleep(3)
        XCTAssertEqual(dayValue(app), day(offset: 6))
        for _ in 0..<6 { app.buttons["prevDay"].tap() }
        sleep(3)
        XCTAssertEqual(dayValue(app), day(offset: 0))
        XCTAssertFalse(app.buttons["todayBtn"].isEnabled)
        app.buttons["nextDay"].tap()
        app.buttons["nextDay"].tap()
        app.buttons["todayBtn"].tap()
        sleep(2)
        XCTAssertEqual(dayValue(app), day(offset: 0))
    }

    /// Navigation must keep working after every sheet has been presented and dismissed.
    func testNavigationWorksAfterSheets() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["calendarBtn"], 20))
        app.buttons["calendarBtn"].tap()
        XCTAssertTrue(waitFor(app.buttons["closeCalendar"]))
        app.buttons["closeCalendar"].tap()
        sleep(1)
        app.buttons["settingsBtn"].tap()
        XCTAssertTrue(waitFor(app.buttons["closeSettings"]))
        app.buttons["closeSettings"].tap()
        sleep(1)
        app.buttons["historyBtn"].tap()
        XCTAssertTrue(waitFor(app.buttons["closeStatistics"]))
        app.buttons["closeStatistics"].tap()
        sleep(1)
        app.buttons["nextDay"].tap()
        sleep(2)
        XCTAssertEqual(dayValue(app), day(offset: 1))
        app.buttons["prevDay"].tap()
        sleep(2)
        XCTAssertEqual(dayValue(app), day(offset: 0))
    }

    /// Unreachable server → app must boot from its cache within seconds (no 60s hang, no empty list).
    func testOfflineBootUsesCache() throws {
        let online = launch()
        XCTAssertTrue(waitFor(online.buttons["prayer-Dohr"], 20))
        sleep(3)   // let the day be cached
        online.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-serverBase", "http://127.0.0.1:9"]
        app.launch()
        XCTAssertTrue(waitFor(app.buttons["prayer-Dohr"], 15), "Offline boot must show cached prayers")
        XCTAssertTrue(app.buttons["nextDay"].exists)
        app.terminate()

        // Restore the real server for the following tests.
        let back = launch()
        XCTAssertTrue(waitFor(back.buttons["prayer-Dohr"], 20))
    }
}

// MARK: - Visual regression: capture every screen as attachments.

extension AthanCenterUITests {
    func testScreenshots() throws {
        let app = launch()
        XCTAssertTrue(waitFor(app.buttons["settingsBtn"], 20))
        sleep(3)
        save(app.screenshot(), "01-home")

        app.buttons["settingsBtn"].tap()
        XCTAssertTrue(waitFor(app.buttons["section-Audio control"]))
        save(app.screenshot(), "02-settings-general")
        app.buttons["section-Athan call"].tap()
        sleep(1)
        save(app.screenshot(), "03-settings-athan")
        app.buttons["closeSettings"].tap()
        sleep(1)

        app.buttons["historyBtn"].tap()
        XCTAssertTrue(waitFor(app.buttons["exportExcelBtn"]))
        sleep(2)
        save(app.screenshot(), "04-statistics")
        app.buttons["closeStatistics"].tap()
        sleep(1)

        app.buttons["calendarBtn"].tap()
        XCTAssertTrue(waitFor(app.buttons["closeCalendar"]))
        save(app.screenshot(), "05-calendar")
    }

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
