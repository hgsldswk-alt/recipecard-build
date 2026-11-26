import XCTest
@testable import RecipeCard

final class WebRecipeTests: XCTestCase {
    func testCookpadSingleRecipeWithFullWidthYield() throws {
        let html = ##"<html><head><script type="application/ld+json">{"@context": "https://schema.org", "@type": "Recipe", "name": "簡単♪おうちでお店みたいな☆回鍋肉", "recipeYield": "たっぷり２人分", "recipeIngredient": ["豚肉（バラスライスやこまぎれ等） 150g", "きゃべつ １／６位", "長ネギ １／３位"], "recipeInstructions": [{"@type": "HowToStep", "text": "調味料は合わせておく。"}, {"@type": "HowToStep", "text": "材料は食べやすく切る。（キャベツ、ピーマンはざく切り、ネギは斜め薄切り）"}]}</script></head><body></body></html>"##
        let r = try XCTUnwrap(WebRecipe.parse(html: html))
        XCTAssertEqual(r.name, "簡単♪おうちでお店みたいな☆回鍋肉")
        XCTAssertEqual(r.servings, 2)
        XCTAssertEqual(r.ingredients.first, "豚肉（バラスライスやこまぎれ等） 150g")
        XCTAssertEqual(r.ingredients.count, 3)
        XCTAssertEqual(r.steps.first, "調味料は合わせておく。")
        XCTAssertEqual(r.steps.count, 2)
    }

    func testGraphWithHowToSection() throws {
        let html = ##"<html><head><script type="application/ld+json">{"@context": "https://schema.org", "@graph": [{"@type": "WebPage", "name": "x"}, {"@type": "Recipe", "@id": "https://www.recipetineats.com/chicken-chasseur/#recipe", "name": "JB's Chicken Chasseur", "recipeYield": ["4"], "recipeIngredient": ["4  chicken thighs, bone-in, skin on ((~250g/8oz each) (Note 1))", "4  chicken drumsticks ((Note 1))", "3/4 tsp cooking salt / kosher salt"], "recipeInstructions": [{"@type": "HowToSection", "name": "Abbreviated Recipe", "itemListElement": [{"@type": "HowToStep", "text": "Season and flour the chicken, then brown in oil and butter. Remove. Sauté mushrooms and onion, add garlic briefly, then pour in brandy and wine to reduce. Stir in tomato paste for 1 minute, then stock, salt, and pepper. Return chicken, simmer covered 10 minutes then uncovered for 20 minutes until tender. Finish with cold butter and fresh tarragon.", "name": "Season and flour the chicken, then brown in oil and butter. Remove. Sauté mushrooms and onion, add garlic briefly, then pour in brandy and wine to reduce. Stir in tomato paste for 1 minute, then stock, salt, and pepper. Return chicken, simmer covered 10 minutes then uncovered for 20 minutes until tender. Finish with cold butter and fresh tarragon."}]}, {"@type": "HowToSection", "name": "Chicken", "itemListElement": [{"@type": "HowToStep", "text": "Season the chicken - Pat the chicken dry thoroughly with paper towels. This removes surface moisture, allowing the skin to brown properly and avoiding splatter. Season with salt and pepper on all sides. Coat in flour, shaking off excess. This helps develop a golden crust and also thickens the sauce later.", "name": "Season the chicken - Pat the chicken dry thoroughly with paper towels. This removes surface moisture, allowing the skin to brown properly and avoiding splatter. Season with salt and pepper on all sides. Coat in flour, shaking off excess. This helps develop a golden crust and also thickens the sauce later."}, {"@type": "HowToStep", "text": "Brown the Chicken - Heat vegetable oil in a large (30cm/12&quot;) skillet (with lid) over medium-high heat. Add butter, once melted and foaming, place thighs skin-side down. Sear for 5 minutes until golden and crispy. Flip and cook the other side for 1 minute. Transfer to a plate. Add the drumsticks and brown them on 3 sides, about 2 minutes per side. Don’t rush this step – browning adds depth of flavour. Transfer drumsticks to the plate with the thighs. ⚠️ Be mindful when searing skin-on chicken pieces, the skin can pop and hot oil may splash.", "name": "Brown the Chicken - Heat vegetable oil in a large (30cm/12&quot;) skillet (with lid) over medium-high heat. Add butter, once melted and foaming, place thighs skin-side down. Sear for 5 minutes until golden and crispy. Flip and cook the other side for 1 minute. Transfer to a plate. Add the drumsticks and brown them on 3 sides, about 2 minutes per side. Don’t rush this step – browning adds depth of flavour. Transfer drumsticks to the plate with the thighs. ⚠️ Be mindful when searing skin-on chicken pieces, the skin can pop and hot oil may splash."}]}]}]}</script></head><body></body></html>"##
        let r = try XCTUnwrap(WebRecipe.parse(html: html))
        XCTAssertEqual(r.name, "JB's Chicken Chasseur")
        XCTAssertEqual(r.servings, 4)
        XCTAssertEqual(r.ingredients.first, "4 chicken thighs, bone-in, skin on ((~250g/8oz each) (Note 1))")
        XCTAssertFalse(r.steps.isEmpty)
        XCTAssertTrue(r.steps[0].hasPrefix("Season and flour the chicken"))
    }

    func testArrayWithTypeListAndCookieYield() throws {
        let html = ##"<html><head><script type="application/ld+json">[{"@context": "http://schema.org", "@type": ["Recipe", "NewsArticle"], "name": "Best Chocolate Chip Cookies", "recipeYield": ["48", "4 dozen cookies"], "recipeIngredient": ["1 cup butter, softened", "1 cup white sugar", "1 cup packed brown sugar"], "recipeInstructions": [{"@type": "HowToStep", "text": "Gather your ingredients, making sure your butter is softened, and your eggs are room temperature."}, {"@type": "HowToStep", "text": "Preheat the oven to 350 degrees F (175 degrees C). Beat butter, white sugar, and brown sugar together in a large bowl with an electric mixer until light and creamy, about 4 minutes."}]}]</script></head><body></body></html>"##
        let r = try XCTUnwrap(WebRecipe.parse(html: html))
        XCTAssertEqual(r.name, "Best Chocolate Chip Cookies")
        XCTAssertNil(r.servings)
        XCTAssertEqual(r.ingredients, ["1 cup butter, softened", "1 cup white sugar", "1 cup packed brown sugar"])
        XCTAssertEqual(r.steps.count, 2)
    }

    func testPagesWithoutRecipeAndLinkDetection() {
        XCTAssertNil(WebRecipe.parse(html: ##"<script type="application/ld+json">{"@type":"WebSite","name":"x"}</script>"##))
        XCTAssertNil(WebRecipe.parse(html: "<html>no data</html>"))
        XCTAssertEqual(WebRecipe.url(from: "  https://cookpad.com/jp/recipes/17662797 \n")?.absoluteString, "https://cookpad.com/jp/recipes/17662797")
        XCTAssertEqual(WebRecipe.url(from: "http://example.com/r/1")?.scheme, "https")
        XCTAssertNil(WebRecipe.url(from: "番茄炒蛋\n食材：鸡蛋 3 个\n做法：炒 2 分钟。参考 https://example.com"))
        XCTAssertNil(WebRecipe.url(from: "Tomato & eggs"))
        XCTAssertEqual(WebRecipe.clean("Salt &amp; <b>pepper</b>  "), "Salt & pepper")
    }
}
