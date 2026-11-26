import PhotosUI
import SwiftUI
import UIKit

struct EditorView: View {
    @Bindable var model: AppModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var handlingPhoto = false
    @State private var pasteHint = false
    @State private var fetchingWeb = false
    @State private var confirmingDiscard = false

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basics
                    pasteButton
                    field("recipe.ingredients", hint: "editor.ingredientsHint", id: "edit-ingredients",
                          text: fieldBinding(\.ingredients, default: ""), height: 108)
                    field("recipe.steps", hint: "editor.stepsHint", id: "edit-steps",
                          text: fieldBinding(\.steps, default: ""), height: 130)
                    field("recipe.notes", hint: "editor.notesHint", id: "edit-notes",
                          text: fieldBinding(\.recipe.notes, default: ""), height: 92)
                    photos
                }
                .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .disabled(model.busy)
        .navigationTitle(L.t(model.draft?.isNew == true ? "editor.new" : "common.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.t("common.cancel")) { confirmingDiscard = true }
                    .disabled(model.busy).accessibilityIdentifier("editor-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L.t("common.save")) { model.saveDraft() }
                    .fontWeight(.bold)
                    .disabled(model.busy || handlingPhoto || (model.draft?.recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
                    .accessibilityIdentifier("editor-save")
            }
        }
        .confirmationDialog(L.t("editor.discardTitle"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button(L.t("editor.discard"), role: .destructive) { model.discardDraft() }
            Button(L.t("editor.keep"), role: .cancel) {}
        }
        .onChange(of: model.draft) { _, value in
            if let value, !model.busy { model.queueDraft(value) }
        }
        .task(id: pickerItem) { await loadPhoto(pickerItem) }
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(key: "editor.name")
            TextField(L.t("editor.name"), text: fieldBinding(\.recipe.name, default: ""))
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 12).frame(minHeight: 46)
                .modifier(PaperCard(radius: 10)).accessibilityIdentifier("edit-name")
            SectionLabel(key: "editor.portions").padding(.top, 3)
            TextField(L.t("editor.portionsHint"), text: fieldBinding(\.portions, default: ""))
                .keyboardType(.numberPad)
                .padding(.horizontal, 12).frame(minHeight: 46)
                .modifier(PaperCard(radius: 10)).accessibilityIdentifier("edit-portions")
            if model.library.books.count > 1, model.editorCanChooseBook {
                Picker(L.t("book.title"), selection: fieldBinding(\.recipe.bookID, default: Book.defaultID)) {
                    ForEach(model.library.books) { book in
                        Text(model.bookName(book)).tag(book.id)
                    }
                }
                .pickerStyle(.menu).accessibilityIdentifier("edit-book")
                .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private var pasteButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: paste) {
                if fetchingWeb { ProgressView().frame(maxWidth: .infinity) }
                else { Label(L.t("editor.paste"), systemImage: "doc.on.clipboard") }
            }
                .buttonStyle(PaperButton(primary: false))
                .disabled(fetchingWeb)
                .accessibilityIdentifier("editor-paste")
            if pasteHint {
                Text(L.t("editor.pasteHint")).font(.footnote).foregroundStyle(Paper.muted)
                    .accessibilityIdentifier("editor-paste-hint")
            }
        }
    }

    private func paste() {
        let fixture = model.testing ? ProcessInfo.processInfo.environment["RECIPE_PASTE_TEXT"] : nil
        guard let text = fixture ?? UIPasteboard.general.string else {
            model.error = RecipeIssue.emptyText.localizedDescription
            return
        }
        if let url = WebRecipe.url(from: text) {
            fetchingWeb = true
            Task {
                defer { fetchingWeb = false }
                do {
                    var parsed = try await WebRecipe.fetch(url)
                    parsed.notes = url.absoluteString
                    fill(parsed, hint: false)
                } catch {
                    model.error = RecipeIssue.webRecipe.localizedDescription
                }
            }
            return
        }
        do {
            let parsed = try RecipeText.parse(text)
            fill(parsed, hint: !parsed.notes.isEmpty || !parsed.hadSections)
        } catch {
            model.error = model.message(for: error)
        }
    }

    private func fill(_ parsed: ParsedRecipeText, hint: Bool) {
        guard var draft = model.draft else { return }
        let untitled = draft.recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if untitled, let name = parsed.name { draft.recipe.name = name }
        if draft.portions.isEmpty, let servings = parsed.servings { draft.portions = String(servings) }
        draft.ingredients = append(parsed.ingredients.joined(separator: "\n"), to: draft.ingredients)
        draft.steps = append(parsed.steps.joined(separator: "\n"), to: draft.steps)
        draft.recipe.notes = append(parsed.notes, to: draft.recipe.notes)
        model.draft = draft
        pasteHint = hint
    }

    private func append(_ text: String, to old: String) -> String {
        guard !text.isEmpty else { return old }
        return old.isEmpty ? text : old + "\n" + text
    }

    private func field(_ title: String, hint: String, id: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(key: title)
            TextEditor(text: text)
                .font(.body)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .scrollContentBackground(.hidden)
                .frame(minHeight: height)
                .modifier(PaperCard(radius: 10))
                .accessibilityLabel(L.t(title))
                .accessibilityIdentifier(id)
            Text(L.t(hint)).font(.footnote).foregroundStyle(Paper.muted)
        }
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(key: "photo.title")
            if let draft = model.draft, !draft.removePhoto,
               draft.recipe.photoPath != nil || draft.pendingPhoto != nil {
                RecipePhotoView(store: model.store, path: draft.recipe.photoPath, pending: draft.pendingPhoto)
                Button(role: .destructive) {
                    pickerItem = nil
                    model.draft?.pendingPhoto = nil
                    model.draft?.removePhoto = true
                } label: {
                    Text(L.t("photo.remove")).frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("photo-remove")
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(L.t("photo.add"), systemImage: "photo")
            }
            .buttonStyle(PaperButton(primary: false))
            .accessibilityIdentifier("photo-add")
            .disabled(handlingPhoto)
            if handlingPhoto { ProgressView() }
        }
    }

    private func fieldBinding<T>(_ keyPath: WritableKeyPath<RecipeDraft, T>, default fallback: T) -> Binding<T> {
        Binding(get: { model.draft?[keyPath: keyPath] ?? fallback },
                set: { model.draft?[keyPath: keyPath] = $0 })
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        handlingPhoto = true
        defer { handlingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw RecipeIssue.noPhoto }
            let normalized = try await Task.detached { try RecipePhoto.normalized(data) }.value
            guard !Task.isCancelled, pickerItem == item else { return }
            model.draft?.pendingPhoto = normalized
            model.draft?.removePhoto = false
        } catch {
            if !Task.isCancelled { model.error = RecipeIssue.noPhoto.localizedDescription }
        }
    }
}
