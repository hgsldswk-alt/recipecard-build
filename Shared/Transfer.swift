import Foundation

struct RecipePayload: Codable, Equatable, Sendable {
    var sourceID: UUID
    var name: String
    var servings: Int?
    var ingredients: [String]
    var steps: [String]
    var notes: String?
    var bookID: UUID?
    var photo: Data?
    var backupID: UUID?

    init(recipe: Recipe, includingNotes: Bool = true, bookID: UUID? = nil, photo: Data? = nil,
         backupID: UUID? = nil) {
        sourceID = recipe.sourceID
        name = recipe.name
        servings = recipe.servings
        ingredients = recipe.ingredients
        steps = recipe.steps
        notes = includingNotes ? recipe.notes : nil
        self.bookID = bookID
        self.photo = photo
        self.backupID = backupID
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeIssue.name }
        if let servings, !(1...24).contains(servings) { throw RecipeIssue.servings }
        guard name.utf8.count <= 1_024,
              ingredients.count <= 2_000, steps.count <= 2_000,
              ingredients.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 16_384 }),
              steps.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 16_384 }),
              (notes?.utf8.count ?? 0) <= 512_000,
              (ingredients + steps).reduce(0, { $0 + $1.utf8.count }) <= 512_000 else { throw RecipeIssue.fileTooLarge }
        if let photo, photo.isEmpty || photo.count > RecipeTransfer.maxPhotoBytes { throw RecipeIssue.filePhoto }
    }

    func matchesText(_ recipe: Recipe) -> Bool {
        sourceID == recipe.sourceID && name == recipe.name && servings == recipe.servings &&
        ingredients == recipe.ingredients && steps == recipe.steps && (notes ?? "") == recipe.notes
    }

    func makeRecipe(in book: UUID, now: Date = Date()) -> Recipe {
        Recipe(sourceID: sourceID, name: name, servings: servings, ingredients: ingredients, steps: steps,
               notes: notes ?? "", bookID: book, createdAt: now, modifiedAt: now)
    }
}

enum ImportResolution: Equatable {
    case skip, insert, copy

    static func decide(_ incoming: RecipePayload, candidates: [Recipe], photoMatches: (Recipe) -> Bool) -> Self {
        let existing = candidates.filter { $0.sourceID == incoming.sourceID }
        if existing.contains(where: { incoming.matchesText($0) && photoMatches($0) }) { return .skip }
        return existing.isEmpty ? .insert : .copy
    }
}

enum RecipeTransfer {
    static let prefix = "RECIPECARD1:"
    static let maxCodeBytes = 16_384
    static let maxPhotoBytes = 8_000_000
    static let maxFileLineBytes = 12_500_000

    struct Card: Codable {
        var schemaVersion = 1
        var recipe: RecipePayload
    }

    struct Header: Codable {
        var schemaVersion = 1
        var kind = "recipebackup"
        let bookCount: Int?
        let recipeCount: Int?
        let cookedCount: Int?
    }

    struct Line: Codable {
        var kind: String
        var book: Book?
        var recipe: RecipePayload?
        var cooked: UUID?
    }

    static func makeCode(_ recipe: Recipe) throws -> String {
        let bytes = try encodeCard(RecipePayload(recipe: recipe, includingNotes: false))
        let encoded = bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard encoded.utf8.count + prefix.count <= maxCodeBytes else { throw RecipeIssue.longCode }
        return L.t("code.instructions") + "\n" + prefix + encoded
    }

    static func decodeCode(_ text: String) throws -> RecipePayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.range(of: prefix) else { throw RecipeIssue.invalidCode }
        let token = trimmed[start.upperBound...].prefix { !$0.isWhitespace }
        guard !token.isEmpty else { throw RecipeIssue.invalidCode }
        guard token.utf8.count + prefix.count <= maxCodeBytes else { throw RecipeIssue.longCode }
        guard token.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw RecipeIssue.invalidCode }
        var base64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw RecipeIssue.invalidCode }
        do {
            var recipe = try decodeCard(data)
            recipe.notes = nil
            recipe.bookID = nil
            recipe.photo = nil
            recipe.backupID = nil
            return recipe
        } catch RecipeIssue.fileVersion {
            throw RecipeIssue.fileVersion
        } catch {
            throw RecipeIssue.invalidCode
        }
    }

    static func encodeCard(_ recipe: RecipePayload) throws -> Data {
        try recipe.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(Card(recipe: recipe))
        guard data.count <= maxFileLineBytes else { throw RecipeIssue.fileTooLarge }
        return data
    }

    static func decodeCard(_ data: Data) throws -> RecipePayload {
        guard data.count <= maxFileLineBytes else { throw RecipeIssue.fileTooLarge }
        let card: Card = try decode(Card.self, from: data, versioned: true)
        try card.recipe.validate()
        return card.recipe
    }

    static func decodeHeader(_ data: Data) throws -> Header {
        let header: Header = try decode(Header.self, from: data, versioned: true)
        guard header.kind == "recipebackup",
              (header.bookCount ?? 1) > 0, (header.recipeCount ?? 0) >= 0,
              (header.cookedCount ?? 0) >= 0 else { throw RecipeIssue.fileFormat }
        return header
    }

    static func decodeLine(_ data: Data) throws -> Line {
        let line: Line = try decode(Line.self, from: data)
        switch line.kind {
        case "book":
            guard let book = line.book, line.recipe == nil, line.cooked == nil,
                  ((book.id == Book.defaultID && book.name.isEmpty) ||
                   !book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                  book.name.utf8.count <= 256 else { throw RecipeIssue.fileFormat }
        case "recipe":
            guard let recipe = line.recipe, recipe.bookID != nil, line.book == nil, line.cooked == nil else {
                throw RecipeIssue.fileFormat
            }
            try recipe.validate()
        case "cooked":
            guard line.cooked != nil, line.recipe == nil, line.book == nil else { throw RecipeIssue.fileFormat }
        default:
            throw RecipeIssue.fileFormat
        }
        return line
    }

    private struct Version: Decodable { let schemaVersion: Int }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, versioned: Bool = false) throws -> T {
        do {
            let decoder = JSONDecoder()
            if versioned {
                guard try decoder.decode(Version.self, from: data).schemaVersion == 1 else {
                    throw RecipeIssue.fileVersion
                }
            }
            return try decoder.decode(type, from: data)
        } catch let issue as RecipeIssue {
            throw issue
        } catch {
            throw RecipeIssue.fileFormat
        }
    }
}

struct BackupReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var ended = false

    init(url: URL) throws {
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw RecipeIssue.fileRead }
    }

    mutating func next() throws -> Data? {
        var scanned = 0
        while true {
            let start = buffer.index(buffer.startIndex, offsetBy: scanned)
            if let newline = buffer[start...].firstIndex(of: 10) {
                guard buffer.distance(from: buffer.startIndex, to: newline) <= RecipeTransfer.maxFileLineBytes else {
                    throw RecipeIssue.fileTooLarge
                }
                let result = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return result
            }
            guard buffer.count <= RecipeTransfer.maxFileLineBytes else { throw RecipeIssue.fileTooLarge }
            if ended {
                let result = buffer.isEmpty ? nil : buffer
                buffer.removeAll()
                return result
            }
            scanned = buffer.count
            let data: Data
            do { data = try handle.read(upToCount: 64 * 1_024) ?? Data() }
            catch { throw RecipeIssue.fileRead }
            ended = data.isEmpty
            buffer.append(data)
        }
    }

    func close() { try? handle.close() }
}
