import XCTest

/// Walks every screen in demo mode (-uiTour: sample words, no saving) and attaches screenshots.
final class UITour: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-uiTour"]
        app.launch()
    }

    /// Asks the CI host to take the screenshot with `simctl io screenshot` (in-test screenshots time out on CI).
    /// The simulator shares the host file system, so a request file is enough.
    private func shot(_ name: String) {
        let dir = (ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()) + "/tour"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let req = dir + "/request"
        try? name.write(toFile: req, atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(20)
        while FileManager.default.fileExists(atPath: req), Date() < deadline { usleep(200_000) }
        print("TOUR-SHOT \(name)")
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name].firstMatch
        if b.waitForExistence(timeout: 5) { b.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testTour() {
        XCTAssertTrue(app.buttons["startQuiz"].waitForExistence(timeout: 15))
        sleep(2); shot("01-home")

        app.buttons["startQuiz"].tap()
        XCTAssertTrue(any("quizAnswer").waitForExistence(timeout: 5))
        sleep(1)
        app.typeText("neces"); sleep(1); shot("02-quiz")
        app.typeText("ary\n")
        XCTAssertTrue(app.buttons["nextButton"].waitForExistence(timeout: 5))
        sleep(4); shot("03-feedback")
        app.buttons["nextButton"].tap()

        for w in ["rhythm", "separate", "necessary"] {
            sleep(1)
            app.typeText(w + "\n")
            if app.buttons["nextButton"].waitForExistence(timeout: 5) { app.buttons["nextButton"].tap() }
        }
        XCTAssertTrue(any("score").waitForExistence(timeout: 5))
        sleep(2); shot("04-result")
        app.buttons["doneButton"].tap()

        tab("Слово дня"); sleep(5); shot("05-word-of-day")
        tab("Наборы"); sleep(2); shot("06-sets")
        tab("Уроки")
        _ = app.buttons["episode0"].waitForExistence(timeout: 15)
        sleep(1); shot("07-lessons")
        if app.buttons["episode0"].exists { app.buttons["episode0"].tap(); sleep(3); shot("08-lessons-player") }

        tab("Ещё"); sleep(2); shot("09-more")
        any("theme1").tap(); sleep(2); shot("10-more-light")
        tab("Главная"); sleep(2); shot("11-home-light")
        tab("Ещё"); any("myWords").tap(); sleep(2); shot("12-my-words")
        app.buttons["addWords"].tap(); sleep(2); shot("13-add-words")
    }
}
