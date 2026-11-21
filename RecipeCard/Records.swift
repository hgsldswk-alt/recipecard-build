import Foundation
import SwiftData

@Model
final class StoredRecipe {
    @Attribute(.unique) var id: UUID
    var sourceID: UUID
    var name: String
    var servings: Int?
    var ingredients: [String]
    var structuredIngredients: Data?
    var steps: [String]
    var notes: String
    var bookID: UUID
    var photoPath: String?
    var createdAt: Date
    var modifiedAt: Date
    var openedAt: Date?

    init(_ recipe: Recipe) {
        id = recipe.id
        sourceID = recipe.sourceID
        name = recipe.name
        servings = recipe.servings
        ingredients = recipe.ingredients
        structuredIngredients = try? JSONEncoder().encode(recipe.parsedIngredients)
        steps = recipe.steps
        notes = recipe.notes
        bookID = recipe.bookID
        photoPath = recipe.photoPath
        createdAt = recipe.createdAt
        modifiedAt = recipe.modifiedAt
        openedAt = recipe.openedAt
    }

    var value: Recipe {
        Recipe(id: id, sourceID: sourceID, name: name, servings: servings, ingredients: ingredients,
               structuredIngredients: structuredIngredients.flatMap { try? JSONDecoder().decode([Ingredient].self, from: $0) },
               steps: steps,
               notes: notes, bookID: bookID, photoPath: photoPath, createdAt: createdAt,
               modifiedAt: modifiedAt, openedAt: openedAt)
    }

    func update(with recipe: Recipe) {
        name = recipe.name
        servings = recipe.servings
        ingredients = recipe.ingredients
        structuredIngredients = try? JSONEncoder().encode(recipe.parsedIngredients)
        steps = recipe.steps
        notes = recipe.notes
        bookID = recipe.bookID
        photoPath = recipe.photoPath
        modifiedAt = recipe.modifiedAt
        openedAt = recipe.openedAt
    }
}

@Model
final class StoredBook {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    init(_ book: Book) {
        id = book.id
        name = book.name
        createdAt = book.createdAt
    }

    var value: Book { Book(id: id, name: name, createdAt: createdAt) }
}

@Model
final class CookedRecipe {
    @Attribute(.unique) var recipeID: UUID
    var firstCompletedAt: Date

    init(recipeID: UUID, firstCompletedAt: Date = Date()) {
        self.recipeID = recipeID
        self.firstCompletedAt = firstCompletedAt
    }
}

@Model
final class CookingProgress {
    @Attribute(.unique) var recipeID: UUID
    var step: Int

    init(recipeID: UUID, step: Int) {
        self.recipeID = recipeID
        self.step = step
    }
}

@Model
final class StoredDraft {
    @Attribute(.unique) var slot: String
    @Attribute(.externalStorage) var payload: Data

    init(payload: Data) {
        slot = "current"
        self.payload = payload
    }
}
