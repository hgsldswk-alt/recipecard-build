import Foundation

extension RecipeStore {
    func renderShare(_ recipe: Recipe, qr: RecipeCardArt.QR) throws -> [URL] {
        let images = try RecipeCardArt.render(recipe, photo: try photoData(recipe.photoPath), qr: qr)
        return try writeShareImages(images)
    }

    func renderMilestone(qr: RecipeCardArt.QR) throws -> [URL] {
        try writeShareImages([RecipeCardArt.milestone(qr: qr)])
    }

    private func writeShareImages(_ images: [Data]) throws -> [URL] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecipeCardShare", isDirectory: true)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try images.enumerated().map { index, image in
                let name = images.count == 1 ? L.t("export.filename") :
                    L.f("share.filename", L.t("export.filename") as NSString, index + 1)
                let url = directory.appendingPathComponent(name).appendingPathExtension("png")
                try image.write(to: url, options: .atomic)
                return url
            }
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }
}
