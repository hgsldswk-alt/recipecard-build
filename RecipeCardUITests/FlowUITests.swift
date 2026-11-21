import Foundation
import XCTest

final class FlowUITests: XCTestCase {
    enum Language: String, CaseIterable {
        case simplified = "zh-Hans"
        case traditional = "zh-Hant"
        case english = "en"

        var locale: String {
            switch self {
            case .simplified: return "zh_CN"
            case .traditional: return "zh_TW"
            case .english: return "en_US"
            }
        }

        var pasteFixture: String {
            switch self {
            case .simplified:
                return "下班后的炒蛋\n2 人份\n食材\n鸡蛋 3 个\n盐适量\n做法\n1. 热油倒入蛋液。\n2. 炒至凝固。"
            case .traditional:
                return "下班後的炒蛋\n2 人份\n材料\n雞蛋 3 個\n鹽適量\n作法\n1. 熱油倒入蛋液。\n2. 炒至凝固。"
            case .english:
                return "Eggs after work\nServings: 2\nIngredients\n3 eggs\nSalt to taste\nSteps\n1. Pour the eggs into hot oil.\n2. Cook until set."
            }
        }

        var sampleEggs: String {
            switch self {
            case .simplified: return "鸡蛋 6 个"
            case .traditional: return "雞蛋 6 個"
            case .english: return "6 eggs"
            }
        }
    }

    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ args: [String] = [], language: Language = .english, reset: Bool = true,
                        environment: [String: String] = [:], readyID: String = "home-new") {
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))",
                               "-AppleLocale", language.locale] + (reset ? ["-reset"] : []) + args
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(button(readyID).waitForExistence(timeout: 15))
    }

    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func node(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 9), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func disappear(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed, file: file, line: line)
    }

    private func popMenu(_ text: String) {
        let item = app.buttons.matching(NSPredicate(format: "label == %@", text)).firstMatch
        tap(item)
    }

    private func labeledButton(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func dismissActivity() {
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "完成", "Close", "关闭", "關閉"])).firstMatch
        if done.waitForExistence(timeout: 4) && done.isHittable { done.tap() } else { app.swipeDown(velocity: .fast) }
        let back = button("detail-more")
        for _ in 0..<3 {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline && !(back.exists && back.isHittable) { usleep(300_000) }
            if !back.exists || back.isHittable { return }
            app.swipeDown(velocity: .fast)
        }
    }

    private func hittableLabeledButton(_ text: String) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text))
        _ = query.firstMatch.waitForExistence(timeout: 9)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let hit = query.allElementsBoundByIndex.last(where: { $0.isHittable }) { return hit }
            usleep(300_000)
        }
        return query.firstMatch
    }

    private func clear(_ field: XCUIElement) {
        if let old = field.value as? String, old != field.placeholderValue, !old.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
    }

    func testEmptyManualSaveSearchAndDraftRecovery() {
        launch()
        XCTAssertTrue(app.staticTexts["Save your first recipe"].exists)
        tap(button("home-new"))
        let name = app.textFields["edit-name"]
        tap(name)
        name.typeText("Wednesday soup")
        tap(button("editor-save"))
        disappear(button("editor-save"))
        tap(app.textFields["home-search"])
        app.textFields["home-search"].typeText("Wednesday")
        tap(labeledButton("Wednesday soup"))
        XCTAssertTrue(node("detail-title").waitForExistence(timeout: 5))
        tap(button("detail-edit"))
        tap(name)
        if let old = name.value as? String { name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        name.typeText("Draft soup")
        tap(button("editor-cancel"))
        let keep = app.buttons.matching(NSPredicate(format: "label == %@", "Keep editing")).firstMatch
        if keep.waitForExistence(timeout: 3) && keep.isHittable { keep.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        XCTAssertTrue(name.exists)
        XCUIDevice.shared.press(.home)
        app.terminate()
        launch(reset: false, readyID: "editor-save")
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertEqual(name.value as? String, "Draft soup")
        tap(button("editor-save"))
        disappear(button("editor-save"))
        XCTAssertTrue(app.staticTexts["Draft soup"].waitForExistence(timeout: 8) ||
                      labeledButton("Draft soup").exists)
    }

    func testPasteCookResumeShareAndCodeRoundTrip() {
        launch(environment: ["RECIPE_PASTE_TEXT": Language.english.pasteFixture])
        tap(button("home-new"))
        tap(button("editor-paste"))
        XCTAssertEqual(app.textFields["edit-name"].value as? String, "Eggs after work")
        tap(button("editor-save"))
        disappear(button("editor-save"))
        tap(labeledButton("Eggs after work"))
        tap(button("cook-start"))
        tap(button("cook-next"))
        XCTAssertTrue(button("cook-finish").exists)
        tap(button("cook-back"))
        tap(button("cook-start"))
        XCTAssertTrue(button("cook-finish").waitForExistence(timeout: 8))
        tap(button("cook-finish"))
        tap(button("recent-recipe"))
        tap(button("detail-share"))
        dismissActivity()
        tap(button("detail-more"))
        popMenu("Copy recipe code")
        tap(button("detail-back"))
        tap(button("home-import"))
        tap(button("import-paste"))
        XCTAssertTrue(node("import-recipe-title").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Identical recipes to skip: 1"].exists)
        tap(button("import-confirm"))
        disappear(button("import-confirm"))
    }

    func testInvalidCodeAndCorruptFileKeepRecipeLibrary() {
        launch(["-seed", "-fixture-file"], environment: ["RECIPE_IMPORT_CODE": "invalid", "RECIPE_FILE_FIXTURE": "corrupt"])
        tap(button("home-import"))
        tap(button("import-paste"))
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        tap(alert.buttons["OK"])
        tap(button("import-file"))
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        tap(alert.buttons["OK"])
        tap(button("import-close"))
        XCTAssertTrue(button("recent-recipe").waitForExistence(timeout: 5))
    }

    func testFileImportAndPhotoPickerCancellation() {
        launch(["-fixture-file"])
        tap(button("home-import"))
        tap(button("import-file"))
        XCTAssertTrue(app.staticTexts["Steamed eggs from file"].waitForExistence(timeout: 8))
        tap(button("import-confirm"))
        disappear(button("import-confirm"))
        tap(labeledButton("Steamed eggs from file"))
        tap(button("detail-edit"))
        let add = button("photo-add")
        for _ in 0..<6 where !add.isHittable { app.swipeUp() }
        tap(add)
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Cancel", "editor-cancel")).firstMatch
        if cancel.waitForExistence(timeout: 4) { cancel.tap() }
        else { app.swipeDown() }
        XCTAssertEqual(app.textFields["edit-name"].value as? String, "Steamed eggs from file")
        tap(button("editor-save"))
        disappear(button("editor-save"))
        XCTAssertTrue(node("detail-title").exists)
    }

    func testExpiredKeepsOldCookbookRenameFullExportAndBackupRestore() {
        launch(["-seed", "-expired", "-fixture-file"], environment: ["RECIPE_FILE_FIXTURE": "backup"])
        tap(button("expiry-banner-dismiss"))
        tap(button("home-more"))
        tap(button("manage-books"))
        let oldBook = hittableLabeledButton("Family favorites")
        tap(oldBook)
        let alert = app.alerts.firstMatch
        let field = alert.textFields.firstMatch
        tap(field)
        clear(field)
        field.typeText("Renamed cookbook")
        tap(alert.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Renamed cookbook"].waitForExistence(timeout: 8))
        tap(button("books-back"))
        tap(button("settings-close"))
        let filter = app.buttons.matching(NSPredicate(format: "label == %@", "Renamed cookbook")).firstMatch
        tap(filter)
        tap(button("recipe-00000000-0000-0000-0000-000000000102"))
        tap(button("detail-edit"))
        tap(button("editor-save"))
        disappear(button("editor-save"))
        tap(button("detail-more"))
        popMenu("Export full recipe")
        dismissActivity()
        tap(button("servings-button"))
        XCTAssertTrue(button("paywall-buy").waitForExistence(timeout: 9))
        tap(button("paywall-close"))
        tap(button("detail-back"))
        tap(button("home-import"))
        tap(button("import-file"))
        XCTAssertTrue(node("restore-summary").waitForExistence(timeout: 8))
        tap(button("import-confirm"))
        disappear(button("import-confirm"))
    }

    func testTenDistinctMealsTriggerOneMilestone() {
        launch(["-seed", "-seed-ten"])
        tap(button("recent-recipe"))
        completeCurrentRecipe()
        tap(button("recent-recipe"))
        completeCurrentRecipe()
        XCTAssertFalse(button("milestone-banner-action").exists)
        for recipe in 102...110 {
            let item = button(String(format: "recipe-00000000-0000-0000-0000-%012d", recipe))
            let scroll = node("home-scroll")
            for _ in 0..<8 where !item.isHittable { scroll.swipeUp() }
            tap(item)
            completeCurrentRecipe()
        }
        tap(button("milestone-banner-dismiss"))
        XCTAssertFalse(button("milestone-banner-action").exists)
    }

    private func completeCurrentRecipe() {
        tap(button("cook-start"))
        let next = button("cook-next")
        for _ in 0..<4 where next.exists { tap(next) }
        tap(button("cook-finish"))
        XCTAssertTrue(button("home-new").waitForExistence(timeout: 8))
    }

    func testFreeLaunchHidesPurchaseActions() {
        launch(["-free-mode"])
        tap(button("home-more"))
        XCTAssertTrue(button("settings-close").waitForExistence(timeout: 7))
        XCTAssertFalse(button("settings-pro").exists)
        XCTAssertFalse(button("settings-restore").exists)
    }

    func testStoreSimplified() { captureStore(.simplified) }
    func testStoreTraditional() { captureStore(.traditional) }
    func testStoreEnglish() { captureStore(.english) }

    private func captureStore(_ language: Language) {
        let prefix = "store-" + language.rawValue + "-"
        launch(["-seed", "-store-shots"], language: language, environment: [
            "RECIPE_PASTE_TEXT": language.pasteFixture, "RECIPE_TEST_QR": "https://example.invalid/recipecard-screenshot"
        ])
        XCTAssertTrue(button("recent-recipe").waitForExistence(timeout: 8))
        shot(prefix + "01-home")
        tap(button("home-new"))
        tap(button("editor-paste"))
        XCTAssertFalse((app.textFields["edit-name"].value as? String ?? "").isEmpty)
        shot(prefix + "02-paste")
        tap(button("editor-cancel"))
        let discard = app.buttons.matching(NSPredicate(format: "label IN %@", [
            "Discard changes", "放弃修改", "放棄修改"
        ])).firstMatch
        tap(discard)
        disappear(button("editor-save"))
        tap(button("recent-recipe"))
        tap(button("cook-start"))
        tap(button("cook-next"))
        XCTAssertTrue(button("cook-step-2").exists)
        shot(prefix + "03-cooking")
        tap(button("cook-back"))
        tap(button("servings-button"))
        tap(button("portion-4"))
        XCTAssertTrue(app.staticTexts[language.sampleEggs].waitForExistence(timeout: 7))
        shot(prefix + "04-portions")
        tap(button("detail-share"))
        XCTAssertTrue(node("share-preview-image").waitForExistence(timeout: 12))
        shot(prefix + "05-share")
    }

    func testPaidScreenshot() {
        launch(["-paywall", "-paid-mode"], language: .simplified, readyID: "paywall-buy")
        XCTAssertTrue(button("paywall-buy").waitForExistence(timeout: 8))
        shot("paid-01-paywall")
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name + ".png")
            try? screenshot.pngRepresentation.write(to: url, options: .atomic)
        }
    }
}
