import SwiftUI

struct DetailView: View {
    @Bindable var model: AppModel
    let recipeID: UUID
    @State private var target: Int?
    @State private var choosingPortion = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var recipe: Recipe? { model.library.recipes.first { $0.id == recipeID } }
    private var cooking: Bool { model.cookID == recipeID }

    var body: some View {
        PaperScreen {
            if let recipe {
                if cooking { cookingPage(recipe) }
                else { detailPage(recipe) }
            } else {
                Text(L.t("error.missingRecipe"))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            if cooking { model.endCooking() }
        }
        .onChange(of: model.hasPro) { _, hasPro in
            if !hasPro && !cooking { target = nil; choosingPortion = false }
        }
        .sheet(isPresented: $choosingPortion) {
            if let servings = recipe?.servings {
                portionPicker(original: servings)
            }
        }
    }

    private func detailPage(_ recipe: Recipe) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                backButton("common.back", id: "detail-back") { dismiss() }
                Spacer()
                Button(L.t("common.edit")) { model.edit(recipe) }
                    .font(.subheadline.weight(.bold)).frame(minHeight: 44)
                    .accessibilityIdentifier("detail-edit")
                more(recipe)
            }
            .padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Paper.title(recipe.name).accessibilityIdentifier("detail-title")
                    portionSummary(recipe)
                    if !recipe.ingredients.isEmpty { ingredients(recipe) }
                    if !recipe.steps.isEmpty {
                        SectionLabel(key: "recipe.steps")
                        ForEach(recipe.steps.indices, id: \.self) { index in
                            stepRow(recipe.steps[index], index: index, current: nil)
                        }
                    }
                    if !recipe.notes.isEmpty { note(recipe.notes) }
                    if recipe.photoPath != nil { RecipePhotoView(store: model.store, path: recipe.photoPath) }
                }
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 15)
                .frame(maxWidth: 650).frame(maxWidth: .infinity, alignment: .center)
            }
            actionBar(recipe)
        }
    }

    private func more(_ recipe: Recipe) -> some View {
        Menu {
            Button { model.copyTags(recipe) } label: { Label(L.t("share.copyTags"), systemImage: "number") }
            Button { model.copyCode(recipe) } label: { Label(L.t("code.copy"), systemImage: "doc.on.doc") }
            Button { model.export(recipe, includingNotes: false) } label: {
                Label(L.t("export.family"), systemImage: "person.2")
            }
            Button { model.export(recipe, includingNotes: true) } label: {
                Label(L.t("export.full"), systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis").font(.title3.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(L.t("common.more"))
        .accessibilityIdentifier("detail-more")
    }

    @ViewBuilder private func portionSummary(_ recipe: Recipe) -> some View {
        if let original = recipe.servings, recipe.canScale {
            Button {
                if model.hasPro { choosingPortion = true }
                else { model.panel = .paywall }
            } label: {
                Label(L.f("portion.serves", target ?? original), systemImage: "person.2")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 13).frame(minHeight: 44)
                    .modifier(PaperCard(radius: 10, fill: Paper.wash))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Paper.brand)
            .accessibilityIdentifier("servings-button")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let original = recipe.servings { Text(L.f("portion.serves", original)).font(.subheadline.weight(.bold)) }
                Text(L.t(recipe.servings == nil ? "portion.missing" : "portion.noAmounts"))
                    .font(.footnote).foregroundStyle(Paper.muted)
            }
        }
    }

    private func portionPicker(original: Int) -> some View {
        NavigationStack {
            PaperScreen {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 9) {
                        ForEach(1...24, id: \.self) { count in
                            Button {
                                target = count == original ? nil : count
                                choosingPortion = false
                            } label: {
                                Text(count.formatted()).accessibilityLabel(L.f("portion.serves", count))
                            }
                            .buttonStyle(PaperButton(primary: (target ?? original) == count))
                            .accessibilityIdentifier("portion-" + String(count))
                        }
                    }.padding(22)
                }
            }
            .navigationTitle(L.t("portion.choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { choosingPortion = false }
                        .accessibilityIdentifier("portions-close")
                }
            }
        }
        .tint(Paper.brand)
        .presentationDetents([.medium, .large])
    }

    private func actionBar(_ recipe: Recipe) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 9))
        return layout {
            Button {
                model.shareRecipe(recipe, displayPreview: model.testing && model.args.contains("-store-shots"))
            } label: { Label(L.t("share.title"), systemImage: "square.and.arrow.up") }
                .buttonStyle(PaperButton(primary: false, tall: true))
                .accessibilityIdentifier("detail-share")
                .disabled(model.busy)
            if !recipe.steps.isEmpty {
                Button { model.startCooking(recipe) } label: {
                    Label(L.t("cook.start"), systemImage: "play.fill")
                }
                .buttonStyle(PaperButton(tall: true))
                .accessibilityIdentifier("cook-start")
                .disabled(model.busy)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 8)
        .background(Paper.base)
    }

    private func cookingPage(_ recipe: Recipe) -> some View {
        VStack(spacing: 0) {
            HStack {
                backButton("cook.back", id: "cook-back") {
                    model.endCooking()
                    if !model.hasPro { target = nil }
                }
                Spacer()
                Text(L.t("cook.active")).font(.footnote.weight(.bold)).foregroundStyle(Paper.muted)
            }
            .padding(.horizontal, 22)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading, spacing: 5) {
                            Paper.title(recipe.name)
                            if let servings = target ?? recipe.servings {
                                Text(L.f("portion.serves", servings)).font(.subheadline).foregroundStyle(Paper.muted)
                            }
                        }
                        if !recipe.ingredients.isEmpty { ingredients(recipe) }
                        SectionLabel(key: "recipe.steps")
                        VStack(spacing: 7) {
                            ForEach(recipe.steps.indices, id: \.self) { index in
                                Button { model.chooseStep(index, in: recipe) } label: {
                                    stepRow(recipe.steps[index], index: index, current: model.cookStep)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("cook-step-" + String(index + 1))
                                .id(index)
                            }
                        }
                        if !recipe.notes.isEmpty { note(recipe.notes) }
                    }
                    .padding(.horizontal, 22).padding(.top, 11).padding(.bottom, 14)
                    .frame(maxWidth: 650).frame(maxWidth: .infinity)
                }
                .onChange(of: model.cookStep) { _, step in
                    withAnimation(.easeInOut(duration: 0.22)) { reader.scrollTo(step, anchor: .bottom) }
                }
            }
            let final = model.cookStep >= recipe.steps.count - 1
            Button {
                if final { model.finish(recipe) }
                else { model.chooseStep(model.cookStep + 1, in: recipe) }
            } label: {
                Label(L.t(final ? "cook.finish" : "cook.next"), systemImage: final ? "checkmark" : "chevron.right")
            }
            .buttonStyle(PaperButton(tall: true))
            .accessibilityIdentifier(final ? "cook-finish" : "cook-next")
            .padding(.horizontal, 22).padding(.vertical, 8)
            .disabled(model.busy)
        }
    }

    private func backButton(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L.t(key), systemImage: "chevron.left")
                .font(.subheadline.weight(.bold)).frame(minHeight: 44)
        }
        .accessibilityIdentifier(id)
    }

    private func ingredients(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(key: "recipe.ingredients")
            let isWideText = typeSize >= .xxLarge
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: isWideText ? 1 : 2),
                      alignment: .leading, spacing: 8) {
                ForEach(Array(recipe.ingredientLines(for: target).enumerated()), id: \.offset) { index, text in
                    Text(text)
                        .font(cooking ? .body.weight(.medium) : .subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ingredient-" + String(index + 1))
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PaperCard())
    }

    private func stepRow(_ text: String, index: Int, current: Int?) -> some View {
        let selected = index == current
        let complete = current.map { index < $0 } ?? false
        return HStack(alignment: .top, spacing: 9) {
            Group {
                if complete { Image(systemName: "checkmark") }
                else { Text((index + 1).formatted()) }
            }
            .font(.caption.weight(.bold)).frame(width: 24, height: 24)
            .foregroundStyle(selected ? .white : Paper.muted)
            .background(selected ? Paper.brand : Paper.sheet, in: Circle())
            .overlay { Circle().strokeBorder(selected ? .clear : Paper.line, lineWidth: 1) }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if selected {
                    Text(L.f("cook.current", index + 1)).font(.footnote.weight(.bold)).foregroundStyle(Paper.brand)
                }
                Text(text).font(selected ? .title3.weight(.bold) : .body)
                    .foregroundStyle(complete ? Paper.muted : Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, selected ? 12 : 8)
        .frame(maxWidth: .infinity, minHeight: current == nil ? 0 : 44, alignment: .leading)
        .modifier(PaperCard(radius: 14, fill: selected ? Paper.wash : .clear, border: selected ? Paper.brand.opacity(0.35) : .clear))
        .contentShape(Rectangle())
    }

    private func note(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Paper.line)
            Text(L.t("recipe.notes")).font(.footnote.weight(.bold))
            Text(notes).font(.subheadline).foregroundStyle(Paper.muted).textSelection(.enabled)
        }
    }
}
