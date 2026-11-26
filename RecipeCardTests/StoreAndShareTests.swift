import CoreImage
import UIKit
import XCTest
@testable import RecipeCard

final class StoreAndShareTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func photo() throws -> Data {
        let size = CGSize(width: 180, height: 120)
        let bytes = UIGraphicsImageRenderer(size: size).pngData { renderer in
            renderer.cgContext.setFillColor(UIColor.red.cgColor)
            renderer.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        return try RecipePhoto.normalized(bytes)
    }

    func testRecipeDraftCookedProgressAndExpiredBookRename() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecipeStore(folder: folder)
        _ = try await store.start(reset: false)
        let initial = try await store.saveBook(id: nil, name: "Weekend")
        let extra = try XCTUnwrap(initial.books.first { $0.id != Book.defaultID })
        let recipe = Recipe(name: "Soup", bookID: extra.id)
        let new = RecipeDraft(recipe: recipe, isNew: true)
        try await store.saveDraft(new, version: 1)
        let recovered = try await store.loadDraft()
        XCTAssertEqual(recovered, new)
        _ = try await store.save(new, canUsePro: true, version: 2)
        try await store.saveDraft(new, version: 1)
        let stale = try await store.loadDraft()
        XCTAssertNil(stale)
        let renamed = try await store.saveBook(id: extra.id, name: "Old favorites")
        XCTAssertEqual(renamed.books.first(where: { $0.id == extra.id })?.name, "Old favorites")
        var edit = RecipeDraft(recipe: recipe, isNew: false)
        edit.recipe.name = "Edited offline"
        let edited = try await store.save(edit, canUsePro: false, version: 3)
        XCTAssertEqual(edited.recipes.first?.bookID, extra.id)
        XCTAssertEqual(edited.recipes.first?.name, "Edited offline")
        let afterNew = try await store.save(RecipeDraft(recipe: Recipe(name: "New", bookID: extra.id), isNew: true),
                                            canUsePro: false, version: 4)
        XCTAssertEqual(afterNew.recipes.first(where: { $0.name == "New" })?.bookID, Book.defaultID)
        try await store.setStep(2, for: recipe.id)
        let step = try await store.step(for: recipe.id)
        XCTAssertEqual(step, 2)
        let first = try await store.finish(recipe.id)
        let second = try await store.finish(recipe.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second.count, 1)
        let finished = try await store.step(for: recipe.id)
        XCTAssertNil(finished)
    }

    func testBackupRestorePreviewPhotoNotesAndRepeat() async throws {
        let sourceFolder = directory()
        let targetFolder = directory()
        defer {
            try? FileManager.default.removeItem(at: sourceFolder)
            try? FileManager.default.removeItem(at: targetFolder)
        }
        let source = RecipeStore(folder: sourceFolder)
        _ = try await source.start(reset: false)
        let library = try await source.saveBook(id: nil, name: "Guests")
        let book = try XCTUnwrap(library.books.first { $0.id != Book.defaultID })
        let recipe = Recipe(name: "红烧豆腐", servings: 2, ingredients: ["豆腐 300 克"], notes: "私用备注", bookID: book.id)
        var draft = RecipeDraft(recipe: recipe, isNew: true)
        draft.pendingPhoto = try photo()
        _ = try await source.save(draft, canUsePro: true, version: 1)
        _ = try await source.finish(recipe.id)
        let backup = try await source.backup()

        let target = RecipeStore(folder: targetFolder)
        _ = try await target.start(reset: false)
        _ = try await target.saveBook(id: nil, name: "Guests")
        let preview = try await target.preview(file: backup)
        XCTAssertTrue(preview.isBackup)
        XCTAssertEqual(preview.books, 2)
        XCTAssertEqual(preview.recipes, 1)
        let before = try await target.library()
        XCTAssertTrue(before.recipes.isEmpty)
        let restored = try await target.restore(preview.id)
        let imported = try XCTUnwrap(restored.recipes.first)
        XCTAssertEqual(restored.books.count, 3)
        XCTAssertEqual(Set(restored.books.map(\.name)).count, 3)
        XCTAssertEqual(imported.sourceID, recipe.sourceID)
        XCTAssertNotEqual(imported.id, recipe.id)
        XCTAssertEqual(imported.notes, recipe.notes)
        XCTAssertEqual(restored.cooked, Set([imported.id]))
        let storedPhoto = try await target.photoData(imported.photoPath)
        XCTAssertNotNil(storedPhoto.flatMap { UIImage(data: $0) })

        let duplicate = try await target.preview(file: backup)
        XCTAssertEqual(duplicate.skipped, 1)
        let repeatRestore = try await target.restore(duplicate.id)
        XCTAssertEqual(repeatRestore.recipes.count, 1)
        let changed = Recipe(id: recipe.id, sourceID: recipe.sourceID, name: "改过的红烧豆腐")
        let external = try await source.export(changed, includingNotes: false)
        let copy = try await target.preview(file: external)
        XCTAssertEqual(copy.copies, 1)
        let both = try await target.restore(copy.id)
        XCTAssertEqual(both.recipes.count, 2)
    }

    func testIncompleteBackupAndMidCommitFailureLeaveLibraryAndDraftIntact() async throws {
        let folder = directory()
        let origin = directory()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: origin)
        }
        let store = RecipeStore(folder: folder)
        _ = try await store.start(reset: false)
        let draft = RecipeDraft(recipe: Recipe(name: "Keep my draft"), isNew: true)
        try await store.saveDraft(draft, version: 1)
        let source = RecipeStore(folder: origin)
        _ = try await source.start(reset: false)
        for index in 1...2 {
            var recipe = RecipeDraft(recipe: Recipe(name: "Recipe \(index)"), isNew: true)
            recipe.pendingPhoto = try photo()
            _ = try await source.save(recipe, canUsePro: true, version: index)
        }
        let backup = try await source.backup()
        let file = folder.appendingPathComponent("bad.recipebackup")
        var bad = try Data(contentsOf: backup)
        bad.append(Data("{".utf8))
        try bad.write(to: file)
        do {
            _ = try await store.preview(file: file)
            XCTFail("Expected corrupt backup to be rejected")
        } catch {
            XCTAssertEqual(error as? RecipeIssue, .fileFormat)
        }
        let preview = try await store.preview(file: backup)
        let stage = folder.appendingPathComponent("Staging").appendingPathComponent(preview.id.uuidString)
        let images = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
        try FileManager.default.removeItem(at: XCTUnwrap(images.last))
        do {
            _ = try await store.restore(preview.id)
            XCTFail("Expected missing staged photo to fail the transaction")
        } catch {}
        let final = try await store.library()
        let finalDraft = try await store.loadDraft()
        let photos = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Photos"),
                                                                 includingPropertiesForKeys: nil)
        XCTAssertTrue(final.recipes.isEmpty)
        XCTAssertEqual(finalDraft, draft)
        XCTAssertTrue(photos.isEmpty)
        await store.cancelImport(preview.id)
    }

    func testFullPageQRReadbackPNGSizeAndPagination() throws {
        let link = "https://example.invalid/test-recipe-card"
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let direct = try XCTUnwrap(RecipeCardArt.qrCode(link)?.cgImage)
        XCTAssertEqual(detector.features(in: CIImage(cgImage: direct)).compactMap {
            ($0 as? CIQRCodeFeature)?.messageString
        }, [link])

        let recipe = Recipe(name: "番茄炒蛋", servings: 2, ingredients: ["鸡蛋 3 个"],
                            steps: Array(repeating: String(repeating: "長行番茄雞蛋 Tomato and eggs. ", count: 15), count: 8),
                            notes: "Should never be printed")
        let data = try RecipeCardArt.render(recipe, photo: nil, qr: .test(link))
        XCTAssertGreaterThan(data.count, 1)
        let first = try XCTUnwrap(UIImage(data: XCTUnwrap(data.first))?.cgImage)
        XCTAssertEqual(first.width, 1_080)
        XCTAssertEqual(first.height, 1_440)
        XCTAssertEqual(detector.features(in: CIImage(cgImage: first)).compactMap {
            ($0 as? CIQRCodeFeature)?.messageString
        }, [link])
        let second = try XCTUnwrap(UIImage(data: data[1])?.cgImage)
        XCTAssertTrue(detector.features(in: CIImage(cgImage: second)).isEmpty)
        var noNotes = recipe
        noNotes.notes = ""
        XCTAssertEqual(data, try RecipeCardArt.render(noNotes, photo: nil, qr: .test(link)))
    }
}
