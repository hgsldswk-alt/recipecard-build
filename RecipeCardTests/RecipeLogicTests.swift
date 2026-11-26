import XCTest
@testable import RecipeCard

final class RecipeLogicTests: XCTestCase {
    func testThreeLanguagePasteAndUnrecognizedText() throws {
        let samples = [
            ("番茄炒蛋\r\n2 人份\r\n食材：鸡蛋 3 个\r\n做法\r\n1. 炒 2 分钟。\r\n备注\r\n私用", "鸡蛋 3 个", "炒 2 分钟。", "私用"),
            ("番茄炒蛋\n份數：2\n【材料】\n雞蛋 3 個\n作法：炒 2 分鐘。\n備註\n私用", "雞蛋 3 個", "炒 2 分鐘。", "私用"),
            ("Tomato & eggs\nServings: 2\n## Ingredients\n- 3 eggs\n## Directions\n1) Cook for 2 minutes.\nNotes:\nPrivate", "3 eggs", "Cook for 2 minutes.", "Private")
        ]
        for (text, ingredient, step, note) in samples {
            let parsed = try RecipeText.parse(text)
            XCTAssertNotNil(parsed.name)
            XCTAssertEqual(parsed.servings, 2)
            XCTAssertEqual(parsed.ingredients, [ingredient])
            XCTAssertEqual(parsed.steps, [step])
            XCTAssertEqual(parsed.notes, note)
            XCTAssertTrue(parsed.hadSections)
        }
        let source = "A family note\nA second line\nPlease do not lose this."
        let manual = try RecipeText.parse(source)
        XCTAssertEqual(manual.notes, source)
        XCTAssertFalse(manual.hadSections)
        let mixed = try RecipeText.parse("Soup\nunknown: keep this\nIngredients:\n1 carrot")
        XCTAssertEqual(mixed.notes, "unknown: keep this")
        let customHeading = try RecipeText.parse("Soup\nSteps\nStir\n## Serving notes\nKeep this text")
        XCTAssertEqual(customHeading.steps, ["Stir"])
        XCTAssertEqual(customHeading.notes, "## Serving notes\nKeep this text")
        XCTAssertThrowsError(try RecipeText.parse(" \r\n\t ")) { XCTAssertEqual($0 as? RecipeIssue, .emptyText) }
    }

    func testScalingRetainsOriginalAndAmbiguousQuantities() {
        let recipe = Recipe(name: "Tomato & eggs", servings: 2,
                            ingredients: ["鸡蛋 3 个", "1/2 tbsp oil", "0.5 cup stock", "盐适量", "2–3 cloves garlic",
                                          "姜 2 至 3 片", "半个左右", "1 1/2 cups milk", "1 tsp oil and 2 eggs",
                                          "盐 - 2 克", "to taste"],
                            steps: ["Cook for 2 min"], notes: "Use pan 2")
        let scaled = recipe.ingredientLines(for: 4)
        XCTAssertEqual(Array(scaled.prefix(3)), ["鸡蛋 6 个", "1 tbsp oil", "1 cup stock"])
        XCTAssertEqual(Array(scaled.dropFirst(3)), Array(recipe.ingredients.dropFirst(3)))
        XCTAssertEqual(recipe.parsedIngredients[0].name, "鸡蛋")
        XCTAssertEqual(recipe.parsedIngredients[0].unit, "个")
        XCTAssertEqual(recipe.parsedIngredients[1].name, "oil")
        XCTAssertEqual(recipe.parsedIngredients[1].unit, "tbsp")
        XCTAssertEqual(recipe.ingredientLines(for: 2), recipe.ingredients)
        XCTAssertEqual(recipe.steps, ["Cook for 2 min"])
        XCTAssertEqual(recipe.notes, "Use pan 2")
        var noServings = recipe
        noServings.servings = nil
        XCTAssertFalse(noServings.canScale)
        XCTAssertEqual(noServings.ingredientLines(for: 4), recipe.ingredients)
    }

    func testRoundingOnlyMarksInexactValues() {
        let number = NSDecimalNumber(string: "0.17").description(withLocale: Locale.current)
        XCTAssertEqual(Ingredient("1/3 cup flour").scaled(from: 2, to: 1),
                       L.f("portion.approximate", number as NSString) + " cup flour")
        let half = NSDecimalNumber(string: "0.5").description(withLocale: Locale.current)
        XCTAssertEqual(Ingredient("1/3 cup flour").scaled(from: 2, to: 3), half + " cup flour")
    }

    func testCodeAndFileRoundTripAcrossLanguagesAndPrivacy() throws {
        for name in ["番茄炒蛋", "紅燒豆腐", "Braised tofu 🍲"] {
            let recipe = Recipe(name: name, servings: 2, ingredients: ["3 eggs"], steps: ["Cook"], notes: "private")
            let code = try RecipeTransfer.makeCode(recipe)
            let decoded = try RecipeTransfer.decodeCode(code)
            XCTAssertEqual(decoded.name, name)
            XCTAssertEqual(decoded.sourceID, recipe.sourceID)
            XCTAssertNil(decoded.notes)
            XCTAssertNil(decoded.photo)
            let freeExport = try RecipeTransfer.decodeCard(RecipeTransfer.encodeCard(RecipePayload(recipe: recipe)))
            XCTAssertEqual(freeExport.notes, "private")
            let forFamily = RecipePayload(recipe: recipe, includingNotes: false, photo: Data([1, 2, 3]))
            let received = try RecipeTransfer.decodeCard(RecipeTransfer.encodeCard(forFamily))
            XCTAssertNil(received.notes)
            XCTAssertEqual(received.photo, forFamily.photo)
            XCTAssertNotEqual(received.makeRecipe(in: Book.defaultID).id, recipe.id)
        }
    }

    func testLimitsCorruptionAndVersions() throws {
        let recipe = Recipe(name: "Long", steps: [String(repeating: "a", count: 14_000)])
        XCTAssertThrowsError(try RecipeTransfer.makeCode(recipe)) { XCTAssertEqual($0 as? RecipeIssue, .longCode) }
        XCTAssertThrowsError(try RecipeTransfer.decodeCode("RECIPECARD1:?")) {
            XCTAssertEqual($0 as? RecipeIssue, .invalidCode)
        }
        XCTAssertThrowsError(try RecipeTransfer.decodeCard(Data("not JSON".utf8))) {
            XCTAssertEqual($0 as? RecipeIssue, .fileFormat)
        }
        XCTAssertThrowsError(try RecipeTransfer.decodeCard(Data(#"{"schemaVersion":9}"#.utf8))) {
            XCTAssertEqual($0 as? RecipeIssue, .fileVersion)
        }
        XCTAssertThrowsError(try RecipeTransfer.decodeCard(Data(#"{"schemaVersion":1,"recipe":[]}"#.utf8))) {
            XCTAssertEqual($0 as? RecipeIssue, .fileFormat)
        }
    }

    func testTrialUpgradeBoundaryReceiptAndOfflinePurchase() throws {
        let oldInstall = Date(timeIntervalSince1970: 1_600_000_000)
        let paidInstall = oldInstall.addingTimeInterval(100 * 86_400)
        var value = Entitlement(firstOpen: oldInstall)
        value.observe(oldInstall, free: true)
        XCTAssertNil(value.proStartedAt)
        XCTAssertTrue(value.hasPro(at: paidInstall, free: true))
        value.observe(paidInstall, free: false)
        XCTAssertEqual(value.trialStart, paidInstall)
        XCTAssertTrue(value.hasPro(at: value.trialEnd.addingTimeInterval(-1), free: false))
        XCTAssertFalse(value.hasPro(at: value.trialEnd, free: false))
        value.reconcile(purchased: nil, receiptDate: paidInstall.addingTimeInterval(5 * 86_400))
        XCTAssertEqual(value.trialStart, paidInstall)
        value.observe(value.trialEnd, free: false)
        XCTAssertFalse(value.hasPro(at: paidInstall, free: false))
        value.reconcile(purchased: true, receiptDate: nil)
        let offline = try JSONDecoder().decode(Entitlement.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(offline.hasPro(at: value.trialEnd, free: false))
        value.reconcile(purchased: false, receiptDate: nil)
        XCTAssertFalse(value.hasPro(at: value.trialEnd, free: false))

        var restored = Entitlement(firstOpen: paidInstall)
        restored.observe(paidInstall, free: false)
        restored.reconcile(purchased: nil, receiptDate: oldInstall)
        XCTAssertEqual(restored.trialStart, oldInstall)
        XCTAssertFalse(restored.hasPro(at: paidInstall, free: false))
    }

    func testReviewNeedsThreeDaysDistinctRecipesAndQuietMoment() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        var policy = ReviewPolicy()
        policy.pendingAfterCook = true
        for day in 0..<3 { policy.recordUse(today.addingTimeInterval(Double(day) * 86_400)) }
        XCTAssertFalse(policy.canRequest(at: today, distinctCooked: 2, isQuiet: true))
        XCTAssertFalse(policy.canRequest(at: today, distinctCooked: 3, isQuiet: false))
        XCTAssertTrue(policy.canRequest(at: today, distinctCooked: 3, isQuiet: true))
        policy.lastRequest = today
        XCTAssertFalse(policy.canRequest(at: today.addingTimeInterval(119 * 86_400), distinctCooked: 3, isQuiet: true))
        XCTAssertTrue(policy.canRequest(at: today.addingTimeInterval(120 * 86_400), distinctCooked: 3, isQuiet: true))
    }
}
