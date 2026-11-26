import Foundation

struct Recipe: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var sourceID = UUID()
    var name = ""
    var servings: Int?
    var ingredients: [String] = []
    var structuredIngredients: [Ingredient]?
    var steps: [String] = []
    var notes = ""
    var bookID: UUID = Book.defaultID
    var photoPath: String?
    var createdAt = Date()
    var modifiedAt = Date()
    var openedAt: Date?

    var canScale: Bool {
        servings != nil && parsedIngredients.contains { $0.amount != nil }
    }

    var parsedIngredients: [Ingredient] {
        if let structuredIngredients, structuredIngredients.map(\.raw) == ingredients {
            return structuredIngredients
        }
        return ingredients.map(Ingredient.init)
    }

    func ingredientLines(for target: Int?) -> [String] {
        guard let target, let servings, target != servings else { return ingredients }
        return parsedIngredients.map { $0.scaled(from: servings, to: target) }
    }
}

struct Book: Codable, Equatable, Identifiable, Sendable {
    static let defaultID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    var id = UUID()
    var name: String
    var createdAt = Date()
}

struct Library: Equatable, Sendable {
    var recipes: [Recipe] = []
    var books: [Book] = []
    var cooked: Set<UUID> = []

    func visible(book: UUID?, query: String) -> [Recipe] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return recipes.filter { recipe in
            (book == nil || recipe.bookID == book) &&
            (query.isEmpty || recipe.name.localizedStandardContains(query) ||
             recipe.ingredients.contains { $0.localizedStandardContains(query) })
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

struct RecipeDraft: Codable, Equatable, Sendable {
    var recipe: Recipe
    var isNew: Bool
    var portions = ""
    var ingredients = ""
    var steps = ""
    var pendingPhoto: Data?
    var removePhoto = false

    init(recipe: Recipe, isNew: Bool) {
        self.recipe = recipe
        self.isNew = isNew
        portions = recipe.servings.map { String($0) } ?? ""
        ingredients = recipe.ingredients.joined(separator: "\n")
        steps = recipe.steps.joined(separator: "\n")
    }

    func materialize() throws -> Recipe {
        var result = recipe
        result.name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = portions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            guard let value = Int(input), (1...24).contains(value) else { throw RecipeIssue.servings }
            result.servings = value
        } else {
            result.servings = nil
        }
        result.ingredients = RecipeText.lines(ingredients)
        result.structuredIngredients = result.ingredients.map(Ingredient.init)
        result.steps = RecipeText.lines(steps)
        try RecipePayload(recipe: result).validate()
        return result
    }
}

enum RecipeIssue: String, LocalizedError {
    case name, servings, invalidCode, longCode, emptyText, fileFormat, fileVersion, filePhoto,
         fileRead, noPhoto, localStorage, duplicateBook, missingBook, missingRecipe, fileTooLarge, share, webRecipe
    var errorDescription: String? { L.t("error." + rawValue) }
}
