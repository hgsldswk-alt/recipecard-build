import Foundation
import SwiftData
import CryptoKit

struct ImportPreview: Identifiable, Equatable, Sendable {
    var id = UUID()
    var isBackup: Bool
    var books: Int
    var recipes: Int
    var skipped: Int
    var copies: Int
    var single: RecipePayload?
}

actor RecipeStore {
    private struct ImportPlan {
        var preview: ImportPreview
        var revision: Int
        var folder: URL
        var books: [Book] = []
        var updatedDefault: Book?
        var recipes: [Recipe] = []
        var cooked: Set<UUID> = []
    }

    private let folder: URL
    private var container: ModelContainer?
    private var revision = 0
    private var draftVersion = 0
    private var plans: [UUID: ImportPlan] = [:]

    init(folder: URL) { self.folder = folder }

    static func location(testing: Bool) -> URL {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent(testing ? "RecipeCardUITests" : "RecipeCard", isDirectory: true)
    }

    private var photos: URL { folder.appendingPathComponent("Photos", isDirectory: true) }
    private var staging: URL { folder.appendingPathComponent("Staging", isDirectory: true) }

    func start(reset: Bool) throws -> Library {
        if reset, container == nil, FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        let context = try context()
        if try context.fetchCount(FetchDescriptor<StoredBook>()) == 0 {
            context.insert(StoredBook(Book(id: Book.defaultID, name: "")))
            try context.save()
        }
        let library = try snapshot(context)
        let references = Set(library.recipes.compactMap(\.photoPath))
        let fm = FileManager.default
        if let paths = try? fm.contentsOfDirectory(at: photos, includingPropertiesForKeys: nil) {
            for path in paths where path.pathExtension == "jpg" && !references.contains(path.lastPathComponent) {
                try? fm.removeItem(at: path)
            }
        }
        return library
    }

    func library() throws -> Library { try snapshot(context()) }

    private func context() throws -> ModelContext {
        if container == nil {
            let fm = FileManager.default
            try fm.createDirectory(at: photos, withIntermediateDirectories: true)
            var localFolder = folder
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            try? localFolder.setResourceValues(attributes)
            if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let schema = Schema([StoredRecipe.self, StoredBook.self, CookedRecipe.self,
                                 CookingProgress.self, StoredDraft.self])
            let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("RecipeCard.store"),
                                            cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [config])
        }
        guard let container else { throw RecipeIssue.localStorage }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func snapshot(_ context: ModelContext) throws -> Library {
        let recipes = try context.fetch(FetchDescriptor<StoredRecipe>()).map(\.value)
        let books = try context.fetch(FetchDescriptor<StoredBook>(sortBy: [SortDescriptor(\.createdAt)])).map(\.value)
        let cooked = try context.fetch(FetchDescriptor<CookedRecipe>()).map(\.recipeID)
        return Library(recipes: recipes, books: books, cooked: Set(cooked))
    }

    private func record(_ id: UUID, in context: ModelContext) throws -> StoredRecipe? {
        var fetch = FetchDescriptor<StoredRecipe>(predicate: #Predicate { $0.id == id })
        fetch.fetchLimit = 1
        return try context.fetch(fetch).first
    }

    private func draftRecord(in context: ModelContext) throws -> StoredDraft? {
        try context.fetch(FetchDescriptor<StoredDraft>()).first
    }

    func loadDraft() throws -> RecipeDraft? {
        guard let stored = try draftRecord(in: context()) else { return nil }
        return try JSONDecoder().decode(RecipeDraft.self, from: stored.payload)
    }

    func saveDraft(_ draft: RecipeDraft?, version: Int) throws {
        guard version >= draftVersion else { return }
        let context = try context()
        let existing = try draftRecord(in: context)
        if let draft {
            let data = try JSONEncoder().encode(draft)
            if let existing { existing.payload = data }
            else { context.insert(StoredDraft(payload: data)) }
        } else if let existing {
            context.delete(existing)
        }
        try context.save()
        draftVersion = version
    }

    func save(_ draft: RecipeDraft, canUsePro: Bool, version: Int) throws -> Library {
        let context = try context()
        var result = try snapshot(context)
        var recipe = try draft.materialize()
        let original = try record(recipe.id, in: context)
        if original == nil && !draft.isNew { throw RecipeIssue.missingRecipe }
        if draft.isNew && !canUsePro { recipe.bookID = Book.defaultID }
        guard try context.fetch(FetchDescriptor<StoredBook>()).contains(where: { $0.id == recipe.bookID }) else {
            throw RecipeIssue.missingBook
        }
        recipe.modifiedAt = Date()
        recipe.openedAt = original?.openedAt
        let oldPath = original?.photoPath
        recipe.photoPath = oldPath
        var newPath: URL?
        do {
            if let data = draft.pendingPhoto {
                let path = photos.appendingPathComponent(UUID().uuidString + ".jpg")
                try data.write(to: path, options: .atomic)
                recipe.photoPath = path.lastPathComponent
                newPath = path
            } else if draft.removePhoto {
                recipe.photoPath = nil
            }
            if let original { original.update(with: recipe) }
            else { context.insert(StoredRecipe(recipe)) }
            if let draft = try draftRecord(in: context) { context.delete(draft) }
            try context.save()
        } catch {
            context.rollback()
            if let newPath { try? FileManager.default.removeItem(at: newPath) }
            throw error
        }
        draftVersion = max(version, draftVersion)
        revision += 1
        if let index = result.recipes.firstIndex(where: { $0.id == recipe.id }) {
            result.recipes[index] = recipe
        } else {
            result.recipes.append(recipe)
        }
        if let oldPath, oldPath != recipe.photoPath, let url = photoURL(oldPath) {
            try? FileManager.default.removeItem(at: url)
        }
        return result
    }

    func open(_ id: UUID) throws -> Recipe {
        let context = try context()
        guard let record = try record(id, in: context) else { throw RecipeIssue.missingRecipe }
        record.openedAt = Date()
        try context.save()
        return record.value
    }

    func step(for id: UUID) throws -> Int? {
        try progress(for: id, in: context())?.step
    }

    func setStep(_ step: Int, for id: UUID) throws {
        let context = try context()
        let previous = try progress(for: id, in: context)
        if let previous { previous.step = step }
        else { context.insert(CookingProgress(recipeID: id, step: step)) }
        try context.save()
    }

    func finish(_ id: UUID) throws -> Set<UUID> {
        let context = try context()
        let records = try context.fetch(FetchDescriptor<CookedRecipe>())
        if !records.contains(where: { $0.recipeID == id }) { context.insert(CookedRecipe(recipeID: id)) }
        if let progress = try progress(for: id, in: context) { context.delete(progress) }
        try context.save()
        return Set(records.map(\.recipeID)).union([id])
    }

    private func progress(for id: UUID, in context: ModelContext) throws -> CookingProgress? {
        try context.fetch(FetchDescriptor<CookingProgress>(predicate: #Predicate { $0.recipeID == id })).first
    }

    func saveBook(id: UUID?, name: String) throws -> Library {
        let context = try context()
        var result = try snapshot(context)
        let books = try context.fetch(FetchDescriptor<StoredBook>())
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeIssue.name }
        guard trimmed.utf8.count <= 256 else { throw RecipeIssue.fileTooLarge }
        guard !books.contains(where: {
            $0.id != id && displayName($0.value).caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { throw RecipeIssue.duplicateBook }
        if let id {
            guard let existing = books.first(where: { $0.id == id }),
                  let index = result.books.firstIndex(where: { $0.id == id }) else { throw RecipeIssue.missingBook }
            existing.name = trimmed
            result.books[index].name = trimmed
        } else {
            let book = Book(name: trimmed)
            context.insert(StoredBook(book))
            result.books.append(book)
        }
        try context.save()
        revision += 1
        return result
    }

    func photoData(_ path: String?) throws -> Data? {
        guard let path else { return nil }
        guard let url = photoURL(path) else { throw RecipeIssue.filePhoto }
        if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        throw RecipeIssue.filePhoto
    }

    private func photoURL(_ path: String) -> URL? {
        guard path.hasSuffix(".jpg"), UUID(uuidString: String(path.dropLast(4))) != nil else { return nil }
        return photos.appendingPathComponent(path)
    }

    private func newExport(ext: String) throws -> URL {
        let fm = FileManager.default
        let root = folder.appendingPathComponent("Exports", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-86_400)
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for item in items {
                if let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   date < cutoff {
                    try? fm.removeItem(at: item)
                }
            }
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(L.t("export.filename")).appendingPathExtension(ext)
    }

    func export(_ recipe: Recipe, includingNotes: Bool) throws -> URL {
        let url = try newExport(ext: "recipecard")
        let payload = RecipePayload(recipe: recipe, includingNotes: includingNotes, photo: try photoData(recipe.photoPath))
        try RecipeTransfer.encodeCard(payload).write(to: url, options: .atomic)
        return url
    }

    func makeCorruptFixture() throws -> URL {
        let url = try newExport(ext: "recipecard")
        try Data("{".utf8).write(to: url, options: .atomic)
        return url
    }

    func backup() throws -> URL {
        let library = try self.library()
        let url = try newExport(ext: "recipebackup")
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: nil) else { throw RecipeIssue.localStorage }
        let handle = try FileHandle(forWritingTo: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func write<T: Encodable>(_ value: T) throws {
            let bytes = try encoder.encode(value)
            guard bytes.count <= RecipeTransfer.maxFileLineBytes else { throw RecipeIssue.fileTooLarge }
            try handle.write(contentsOf: bytes)
            try handle.write(contentsOf: Data([10]))
        }
        do {
            let cooked = library.cooked.intersection(library.recipes.map(\.id))
            try write(RecipeTransfer.Header(bookCount: library.books.count, recipeCount: library.recipes.count,
                                            cookedCount: cooked.count))
            for book in library.books {
                try write(RecipeTransfer.Line(kind: "book", book: book))
            }
            for recipe in library.recipes {
                let payload = RecipePayload(recipe: recipe, bookID: recipe.bookID,
                                            photo: try photoData(recipe.photoPath), backupID: recipe.id)
                try payload.validate()
                try write(RecipeTransfer.Line(kind: "recipe", recipe: payload))
            }
            for id in cooked { try write(RecipeTransfer.Line(kind: "cooked", cooked: id)) }
            try handle.close()
            return url
        } catch {
            try? handle.close()
            try? fm.removeItem(at: url)
            throw error
        }
    }

    func preview(code: String) throws -> ImportPreview {
        try prepare(single: RecipeTransfer.decodeCode(code), file: nil)
    }

    func preview(file: URL) throws -> ImportPreview {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        switch file.pathExtension.lowercased() {
        case "recipecard":
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > RecipeTransfer.maxFileLineBytes { throw RecipeIssue.fileTooLarge }
            guard let handle = try? FileHandle(forReadingFrom: file) else { throw RecipeIssue.fileRead }
            defer { try? handle.close() }
            var data = Data()
            while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= RecipeTransfer.maxFileLineBytes else { throw RecipeIssue.fileTooLarge }
            }
            return try prepare(single: RecipeTransfer.decodeCard(data), file: nil)
        case "recipebackup":
            return try prepare(single: nil, file: file)
        default:
            throw RecipeIssue.fileFormat
        }
    }

    private func prepare(single: RecipePayload?, file: URL?) throws -> ImportPreview {
        let library = try self.library()
        let preview = ImportPreview(isBackup: file != nil, books: 0, recipes: 0, skipped: 0, copies: 0)
        let directory = staging.appendingPathComponent(preview.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var plan = ImportPlan(preview: preview, revision: revision, folder: directory)
        var booksByID = Dictionary(uniqueKeysWithValues: library.books.map { ($0.id, $0) })
        var names = Set(library.books.map { displayName($0).folding(options: [.caseInsensitive], locale: .current) })
        var candidates = Dictionary(grouping: library.recipes, by: \.sourceID)
        var suppliedBooks: Set<UUID> = []
        var usedBooks: Set<UUID> = []
        var photoDigests: [UUID: Data] = [:]
        var cookedRecords: Set<UUID> = []
        var matches: [UUID: UUID] = [:]
        var backupIDs: Set<UUID> = []

        func add(_ payload: RecipePayload) throws {
            if let book = payload.bookID, file != nil { usedBooks.insert(book) }
            let raw = payload.photo
            let normalized = try raw.map(RecipePhoto.normalized)
            let incomingRawDigest = raw.map(PhotoDigest.make)
            let incomingPhotoDigest = normalized.map(PhotoDigest.make)
            let sameSource = candidates[payload.sourceID] ?? []
            var matchingID: UUID?
            let decision = ImportResolution.decide(payload, candidates: sameSource) { existing in
                let existingPhoto: Data?
                if let staged = photoDigests[existing.id] {
                    existingPhoto = staged
                } else {
                    existingPhoto = (try? self.photoData(existing.photoPath)).map(PhotoDigest.make)
                }
                let same: Bool
                if raw == nil { same = existing.photoPath == nil }
                else {
                    same = existingPhoto != nil && (incomingRawDigest == existingPhoto || incomingPhotoDigest == existingPhoto)
                }
                if same { matchingID = existing.id }
                return same
            }
            plan.preview.recipes += 1
            if file != nil, let backupID = payload.backupID, !backupIDs.insert(backupID).inserted {
                throw RecipeIssue.fileFormat
            }
            if decision == .skip {
                plan.preview.skipped += 1
                matches[payload.backupID ?? payload.sourceID] = matchingID
                return
            }
            var recipe = payload.makeRecipe(in: file == nil ? Book.defaultID : (payload.bookID ?? Book.defaultID))
            if decision == .copy { plan.preview.copies += 1 }
            if let normalized {
                let photoPath = recipe.id.uuidString + ".jpg"
                recipe.photoPath = photoPath
                try normalized.write(to: directory.appendingPathComponent(photoPath), options: .atomic)
                photoDigests[recipe.id] = incomingPhotoDigest
            }
            plan.recipes.append(recipe)
            candidates[recipe.sourceID, default: []].append(recipe)
            matches[payload.backupID ?? payload.sourceID] = recipe.id
        }

        do {
            if var single {
                try add(single)
                single.photo = nil
                single.notes = nil
                plan.preview.single = single
            } else if let file {
                var reader = try BackupReader(url: file)
                defer { reader.close() }
                guard let first = try reader.next() else { throw RecipeIssue.fileFormat }
                let header = try RecipeTransfer.decodeHeader(first)
                while let line = try reader.next() {
                    if line.isEmpty { continue }
                    let row = try RecipeTransfer.decodeLine(line)
                    if var book = row.book {
                        guard suppliedBooks.insert(book.id).inserted else { throw RecipeIssue.fileFormat }
                        if book.id == Book.defaultID, booksByID[book.id]?.name == "", !book.name.isEmpty,
                           !names.contains(book.name.folding(options: [.caseInsensitive], locale: .current)) {
                            plan.updatedDefault = book
                            booksByID[book.id] = book
                            names.insert(book.name.folding(options: [.caseInsensitive], locale: .current))
                        } else if booksByID[book.id] == nil {
                            let original = book.name
                            var sequence = 2
                            while names.contains(book.name.folding(options: [.caseInsensitive], locale: .current)) {
                                book.name = L.f("book.copyName", String(original.prefix(56)) as NSString, sequence)
                                sequence += 1
                            }
                            names.insert(book.name.folding(options: [.caseInsensitive], locale: .current))
                            booksByID[book.id] = book
                            plan.books.append(book)
                        }
                    } else if let recipe = row.recipe {
                        try add(recipe)
                    } else if let id = row.cooked {
                        guard cookedRecords.insert(id).inserted else { throw RecipeIssue.fileFormat }
                    }
                }
                guard header.bookCount.map({ $0 == suppliedBooks.count }) ?? true,
                      header.recipeCount.map({ $0 == plan.preview.recipes }) ?? true,
                      header.cookedCount.map({ $0 == cookedRecords.count }) ?? true,
                      suppliedBooks.contains(Book.defaultID), usedBooks.isSubset(of: suppliedBooks),
                      cookedRecords.isSubset(of: Set(matches.keys)) else { throw RecipeIssue.fileFormat }
                plan.preview.books = suppliedBooks.count
                plan.cooked = Set(cookedRecords.compactMap { matches[$0] })
            }
            plans[preview.id] = plan
            return plan.preview
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cancelImport(_ id: UUID) {
        if let plan = plans.removeValue(forKey: id) { try? FileManager.default.removeItem(at: plan.folder) }
    }

    func restore(_ id: UUID) throws -> Library {
        guard let plan = plans[id] else { throw RecipeIssue.fileFormat }
        guard plan.revision == revision else {
            cancelImport(id)
            throw RecipeIssue.fileRead
        }
        let context = try context()
        var result = try snapshot(context)
        let fm = FileManager.default
        var copied: [URL] = []
        do {
            for book in plan.books { context.insert(StoredBook(book)) }
            if let updated = plan.updatedDefault,
               let index = result.books.firstIndex(where: { $0.id == updated.id }),
               let original = try context.fetch(FetchDescriptor<StoredBook>()).first(where: { $0.id == updated.id }) {
                original.name = updated.name
                result.books[index].name = updated.name
            }
            for recipe in plan.recipes {
                if let photo = recipe.photoPath, let destination = photoURL(photo) {
                    guard !fm.fileExists(atPath: destination.path) else { throw RecipeIssue.filePhoto }
                    copied.append(destination)
                    try fm.copyItem(at: plan.folder.appendingPathComponent(photo), to: destination)
                }
                context.insert(StoredRecipe(recipe))
            }
            for id in plan.cooked.subtracting(result.cooked) { context.insert(CookedRecipe(recipeID: id)) }
            try context.save()
        } catch {
            context.rollback()
            for path in copied { try? fm.removeItem(at: path) }
            throw error
        }
        revision += 1
        cancelImport(id)
        result.books.append(contentsOf: plan.books)
        result.books.sort { $0.createdAt < $1.createdAt }
        result.recipes.append(contentsOf: plan.recipes)
        result.cooked.formUnion(plan.cooked)
        return result
    }

    private func displayName(_ book: Book) -> String { book.name.isEmpty ? L.t("book.default") : book.name }

    private enum PhotoDigest {
        static func make(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }
    }
}
