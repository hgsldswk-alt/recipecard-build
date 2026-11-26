import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    private var recipes: [Recipe] { model.library.visible(book: model.selectedBook, query: model.query) }
    private var recent: Recipe? {
        guard model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return recipes.filter { $0.openedAt != nil }.max { ($0.openedAt ?? .distantPast) < ($1.openedAt ?? .distantPast) }
    }

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if !model.ready {
                        if model.startupFailed {
                            Button(L.t("common.retry")) { Task { await model.boot() } }
                                .buttonStyle(PaperButton(primary: false))
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 42)
                        }
                    } else {
                        if model.library.recipes.isEmpty { emptyTitle }
                        actions
                        if model.expiryBanner {
                            NoteBanner(text: L.t("paywall.expired"), id: "expiry-banner", dismiss: model.closeExpiryBanner)
                                .padding(.top, 12)
                        }
                        if model.milestoneBanner {
                            NoteBanner(text: L.t("milestone.card"), id: "milestone-banner",
                                       actionKey: "milestone.share", action: model.shareMilestone,
                                       dismiss: model.closeMilestoneBanner)
                                .padding(.top, 12)
                        }
                        if !model.library.recipes.isEmpty {
                            search.padding(.top, 12)
                            if model.library.books.count > 1 { bookFilter.padding(.top, 12) }
                            libraryContent
                        }
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 22).padding(.top, 17).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-scroll")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Paper.title(L.t("home.title"))
            Spacer(minLength: 0)
            if model.ready {
                IconButton(key: "common.more", symbol: "ellipsis", id: "home-more") {
                    searchFocused = false
                    model.panel = .settings
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 9) {
            Button {
                searchFocused = false
                model.edit(nil)
            } label: { Label(L.t("home.new"), systemImage: "plus") }
            .buttonStyle(PaperButton())
            .accessibilityIdentifier("home-new")

            Button {
                searchFocused = false
                model.panel = .importing
            } label: {
                Text(L.t("home.import")).frame(minWidth: 90)
            }
            .buttonStyle(PaperButton(primary: false))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("home-import")
        }
        .padding(.top, 21)
    }

    private var emptyTitle: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L.t("home.empty")).font(.title2.weight(.bold))
            Text(L.t("home.emptyHint")).font(.subheadline).foregroundStyle(Paper.muted)
        }
        .padding(.top, 38)
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Paper.muted).accessibilityHidden(true)
            TextField(L.t("home.search"), text: $model.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("home-search")
            if !model.query.isEmpty {
                IconButton(key: "home.clearSearch", symbol: "xmark.circle.fill", id: "home-clear-search") {
                    model.query = ""
                }.foregroundStyle(Paper.muted)
            }
        }
        .font(.subheadline)
        .padding(.leading, 14).padding(.trailing, 9)
        .frame(minHeight: 45)
        .modifier(PaperCard(radius: 12))
    }

    private var bookFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterButton(L.t("home.all"), id: nil)
                ForEach(model.library.books) { filterButton(model.bookName($0), id: $0.id) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterButton(_ title: String, id: UUID?) -> some View {
        Button {
            model.selectedBook = id
            searchFocused = false
        } label: {
            Text(title).font(.footnote.weight(.semibold)).padding(.horizontal, 13).frame(minHeight: 44)
                .foregroundStyle(model.selectedBook == id ? Paper.brand : Paper.ink)
                .modifier(PaperCard(radius: 13, fill: model.selectedBook == id ? Paper.wash : Paper.sheet))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.selectedBook == id ? .isSelected : [])
        .accessibilityIdentifier("filter-" + (id?.uuidString ?? "all"))
    }

    @ViewBuilder private var libraryContent: some View {
        let recent = self.recent
        if let recent {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(key: "home.recent")
                Button { open(recent) } label: { recentCard(recent) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recent-recipe")
            }
            .padding(.top, 26)
        }

        let rest = recipes.filter { $0.id != recent?.id }
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(key: recent == nil ? "home.recipes" : "home.other")
                LazyVStack(spacing: 0) {
                    ForEach(rest) { recipe in
                        if recipe.id != rest.first?.id { Divider().overlay(Paper.line) }
                        Button { open(recipe) } label: { row(recipe) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recipe-" + recipe.id.uuidString)
                    }
                }
                .modifier(PaperCard())
            }
            .padding(.top, 25)
        } else if recent == nil {
            Text(L.t("home.noResults")).font(.subheadline).foregroundStyle(Paper.muted).padding(.top, 25)
        }
    }

    private func open(_ recipe: Recipe) {
        searchFocused = false
        model.open(recipe)
    }

    private func recentCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(recipe.name).font(.largeTitle.weight(.heavy)).tracking(-0.8)
            Text(meta(recipe)).font(.footnote).foregroundStyle(.white.opacity(0.95))
            Rectangle().fill(.white.opacity(0.38)).frame(height: 1).padding(.top, 12)
            HStack {
                Text(L.t("home.view")).font(.subheadline.weight(.bold))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
            }.padding(.top, 6)
        }
        .padding(.horizontal, 21).padding(.vertical, 17)
        .frame(maxWidth: .infinity, minHeight: 163, alignment: .leading)
        .background(Paper.brand, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }

    private func row(_ recipe: Recipe) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.name).font(.body.weight(.bold)).foregroundStyle(Paper.ink)
                Text(meta(recipe)).font(.footnote).foregroundStyle(Paper.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(Paper.muted).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func meta(_ recipe: Recipe) -> String {
        let count = recipe.ingredients.count
        let ingredientCount = L.f(count == 1 ? "home.ingredientOne" : "home.ingredientCount", count)
        guard let servings = recipe.servings else { return ingredientCount }
        return L.f("home.meta", L.f("portion.serves", servings) as NSString, ingredientCount as NSString)
    }
}
