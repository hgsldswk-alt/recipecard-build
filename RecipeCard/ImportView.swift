import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportView: View {
    @Bindable var model: AppModel
    @State private var choosingFile = false

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let preview = model.preview { previewBody(preview) }
                    else { options }
                    if model.busy { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.t(model.preview == nil ? "home.import" : "import.preview"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.t(model.preview == nil ? "common.close" : "common.cancel")) {
                    if model.preview != nil { model.cancelPreview() }
                    else { model.panel = nil }
                }
                .disabled(model.busy).accessibilityIdentifier("import-close")
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.recipeCard, .recipeBackup]) { result in
            switch result {
            case .success(let url): model.previewFile(url)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.error = RecipeIssue.fileRead.localizedDescription }
            }
        }
    }

    private var options: some View {
        VStack(spacing: 10) {
            Button {
                let fixture = model.testing ? ProcessInfo.processInfo.environment["RECIPE_IMPORT_CODE"] : nil
                guard let text = fixture ?? UIPasteboard.general.string else {
                    model.error = RecipeIssue.invalidCode.localizedDescription
                    return
                }
                model.previewCode(text)
            } label: { Label(L.t("import.paste"), systemImage: "doc.on.clipboard") }
            .buttonStyle(PaperButton())
            .accessibilityIdentifier("import-paste")
            Button {
                if model.testing && model.args.contains("-fixture-file") { model.importFixtureFile() }
                else { choosingFile = true }
            } label: { Label(L.t("import.file"), systemImage: "folder") }
            .buttonStyle(PaperButton(primary: false))
            .accessibilityIdentifier("import-file")
        }
        .disabled(model.busy)
    }

    @ViewBuilder private func previewBody(_ preview: ImportPreview) -> some View {
        if let recipe = preview.single {
            Paper.title(recipe.name).accessibilityIdentifier("import-recipe-title")
            if let servings = recipe.servings { Text(L.f("portion.serves", servings)).foregroundStyle(Paper.muted) }
            if !recipe.ingredients.isEmpty { lines("recipe.ingredients", values: recipe.ingredients) }
            if !recipe.steps.isEmpty { lines("recipe.steps", values: recipe.steps) }
        } else {
            Text(L.f("import.summary", preview.books, preview.recipes)).font(.title2.weight(.bold))
                .accessibilityIdentifier("restore-summary")
        }
        if preview.isBackup || preview.skipped > 0 || preview.copies > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if preview.isBackup || preview.skipped > 0 { Text(L.f("import.skipped", preview.skipped)) }
                if preview.isBackup || preview.copies > 0 { Text(L.f("import.copies", preview.copies)) }
                if preview.isBackup { Text(L.t("import.merge")) }
            }
            .font(.subheadline).foregroundStyle(Paper.muted)
        }
        Button(L.t(preview.isBackup ? "import.restore" : "import.save")) { model.confirmImport() }
            .buttonStyle(PaperButton())
            .disabled(model.busy)
            .accessibilityIdentifier("import-confirm")
    }

    private func lines(_ key: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(key: key)
            ForEach(Array(values.prefix(5).enumerated()), id: \.offset) { _, line in
                Text(line).font(.subheadline)
            }
            if values.count > 5 {
                Text(L.f("import.moreLines", values.count - 5)).font(.footnote).foregroundStyle(Paper.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .modifier(PaperCard())
    }
}

extension UTType {
    static let recipeCard = UTType(exportedAs: "com.hgsldswk.recipecard.recipe", conformingTo: .json)
    static let recipeBackup = UTType(exportedAs: "com.hgsldswk.recipecard.backup", conformingTo: .data)
}
