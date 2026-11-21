import Foundation
import Observation
import StoreKit
import SwiftUI
import UIKit

@MainActor @Observable
final class AppModel {
    enum Panel: String, Identifiable, Hashable {
        case editor, importing, settings, paywall
        var id: Self { self }
    }

    enum Destination: Hashable { case detail(UUID) }

    struct SharedItems: Identifiable {
        var id = UUID()
        var urls: [URL]
    }

    struct SharePreview: Identifiable {
        var id = UUID()
        var urls: [URL]
    }

    private struct OpenedFile {
        let url: URL
        let scoped: Bool
    }

    var library = Library()
    var path: [Destination] = []
    var panel: Panel?
    var preview: ImportPreview?
    var share: SharedItems?
    var sharePreview: SharePreview?
    var draft: RecipeDraft?
    var notice: String?
    var error: String?
    var offerEditableFile: Recipe?
    var selectedBook: UUID?
    var query = ""
    var ready = false
    var startupFailed = false
    var busy = false
    var expiryBanner = false
    var milestoneBanner = false
    var entitlement: Entitlement?
    var product: Product?
    var trialProduct: Product?
    var availableClock = Date()
    var cookID: UUID?
    var cookStep = 0
    var foreground = true

    let testing: Bool
    let args: [String]
    let store: RecipeStore
    private let vault: TrialVault
    private let defaults: UserDefaults
    private var policy = ReviewPolicy()
    private var pendingFiles: [OpenedFile] = []
    private var shareAfterPanel: SharedItems?
    private var draftWrite: Task<Void, Never>?
    private var draftVersion = 0
    private var frozenEditorPro = false
    private var quietAfterCook = false
    private var started = false
    private var observed = false
    private var progressWrite: Task<Void, Never>?
    private var knownProgress: [UUID: Int] = [:]

    init(args: [String] = ProcessInfo.processInfo.arguments) {
        self.args = args
        let testing = args.contains("-ui-testing")
        self.testing = testing
        store = RecipeStore(folder: RecipeStore.location(testing: testing))
        vault = TrialVault(testing: testing, expired: args.contains("-expired"))
        if testing {
            let suite = "com.hgsldswk.recipecard.uitests"
            let isolated = UserDefaults(suiteName: suite) ?? .standard
            if args.contains("-reset") { isolated.removePersistentDomain(forName: suite) }
            defaults = isolated
        } else {
            defaults = .standard
        }
    }

    var free: Bool { Launch.isFree(arguments: args) || (testing && args.contains("-free-mode")) }
    var hasPro: Bool { free || entitlement?.hasPro(at: availableClock, free: false) == true }
    var expired: Bool { !free && entitlement != nil && !hasPro }
    var editorCanChooseBook: Bool { draft?.isNew == false || frozenEditorPro }
    var isHome: Bool { path.isEmpty && panel == nil }

    func boot() async {
        guard !started else { return }
        started = true
        startupFailed = false
        let openedAt = availableClock
        let isFree = free
        let vault = self.vault
        async let startingEntitlement = vault.refresh(at: openedAt, free: isFree)
        do {
            library = try await store.start(reset: testing && args.contains("-reset"))
            if testing && args.contains("-seed") && library.recipes.isEmpty {
                try await seedExamples()
                library = try await store.library()
            }
            if let data = defaults.data(forKey: "review-policy"),
               let restored = try? JSONDecoder().decode(ReviewPolicy.self, from: data) { policy = restored }
            recordUse()
            do { entitlement = try await startingEntitlement }
            catch { self.error = PurchaseIssue.keychain.localizedDescription }
            draft = try await store.loadDraft()
            ready = true
            if testing && args.contains("-paywall") && !free { panel = .paywall }
            else if draft != nil {
                frozenEditorPro = hasPro
                panel = .editor
            }
            processPendingFile()
        } catch {
            self.error = message(for: error)
            started = false
            startupFailed = true
        }
    }

    func observePurchases() async {
        guard ready, !observed, !free, !testing else { return }
        observed = true
        defer { observed = false }
        await reconcilePurchases()
        for await update in StoreKit.Transaction.updates {
            if Task.isCancelled { return }
            if case .verified(let transaction) = update {
                do { try await accept(transaction) }
                catch { self.error = message(for: error) }
            }
        }
    }

    func reconcilePurchases() async {
        guard ready, !free, !testing else { return }
        let status = await Purchases.status()
        do { try await refreshEntitlement(purchased: status.purchased, receipt: status.receiptDate) }
        catch { self.error = message(for: error) }
    }

    private func refreshEntitlement(purchased: Bool? = nil, receipt: Date? = nil, disclosingExpiry: Bool = false) async throws {
        let now = Date()
        let value = try await vault.refresh(at: now, free: free, purchased: purchased,
                                            receipt: receipt, disclosingExpiry: disclosingExpiry)
        if (entitlement?.latestSeen ?? .distantPast) <= (value.latestSeen ?? .distantFuture) { entitlement = value }
        availableClock = max(now, availableClock)
    }

    func tick() {
        availableClock = max(Date(), availableClock)
    }

    func sceneChanged(_ phase: ScenePhase) {
        foreground = phase == .active
        syncScreenAwake()
        if foreground && ready {
            recordUse()
            Task {
                do { try await refreshEntitlement() }
                catch { self.error = message(for: error) }
                await reconcilePurchases()
            }
        } else if !foreground, !busy, let draft, panel == .editor {
            queueDraft(draft, immediate: true)
        }
    }

    func bookName(_ book: Book) -> String { book.name.isEmpty ? L.t("book.default") : book.name }

    func open(_ recipe: Recipe) {
        quietAfterCook = false
        path.append(.detail(recipe.id))
        Task {
            do {
                let latest = try await store.open(recipe.id)
                if let index = library.recipes.firstIndex(where: { $0.id == latest.id }) {
                    library.recipes[index].openedAt = latest.openedAt
                }
            } catch { self.error = message(for: error) }
        }
    }

    func edit(_ recipe: Recipe?) {
        guard panel == nil else { return }
        var blank = Recipe()
        if hasPro, let selectedBook { blank.bookID = selectedBook }
        let editing = RecipeDraft(recipe: recipe ?? blank, isNew: recipe == nil)
        frozenEditorPro = hasPro
        draft = editing
        panel = .editor
        queueDraft(editing)
    }

    func queueDraft(_ draft: RecipeDraft, immediate: Bool = false) {
        draftVersion += 1
        let version = draftVersion
        draftWrite?.cancel()
        draftWrite = Task {
            if !immediate {
                do { try await Task.sleep(for: .milliseconds(220)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            do { try await store.saveDraft(draft, version: version) }
            catch { self.error = message(for: error) }
        }
    }

    func saveDraft() {
        guard let draft, !busy else { return }
        busy = true
        draftWrite?.cancel()
        draftVersion += 1
        let version = draftVersion
        Task {
            defer { busy = false }
            do {
                library = try await store.save(draft, canUsePro: frozenEditorPro, version: version)
                self.draft = nil
                panel = nil
            } catch {
                do { try await store.saveDraft(draft, version: version) }
                catch { self.error = RecipeIssue.localStorage.localizedDescription }
                self.error = message(for: error)
            }
        }
    }

    func discardDraft() {
        guard !busy else { return }
        busy = true
        draftWrite?.cancel()
        draftVersion += 1
        let version = draftVersion
        Task {
            defer { busy = false }
            do {
                try await store.saveDraft(nil, version: version)
                draft = nil
                panel = nil
            } catch { self.error = message(for: error) }
        }
    }

    func saveBook(id: UUID?, name: String, completed: @escaping () -> Void) {
        if id == nil && !hasPro { panel = .paywall; return }
        run {
            self.library = try await self.store.saveBook(id: id, name: name)
            completed()
        }
    }

    func startCooking(_ recipe: Recipe) {
        guard cookID == nil, !recipe.steps.isEmpty else { return }
        cookStep = min(max(knownProgress[recipe.id] ?? 0, 0), recipe.steps.count - 1)
        cookID = recipe.id
        syncScreenAwake()
        guard knownProgress[recipe.id] == nil else { return }
        Task {
            let saved = try? await store.step(for: recipe.id)
            if cookID == recipe.id, knownProgress[recipe.id] == nil {
                let step = min(max(saved ?? 0, 0), recipe.steps.count - 1)
                knownProgress[recipe.id] = step
                cookStep = step
            }
        }
    }

    func endCooking() {
        cookID = nil
        syncScreenAwake()
    }

    func chooseStep(_ index: Int, in recipe: Recipe) {
        guard !busy, cookID == recipe.id, recipe.steps.indices.contains(index) else { return }
        cookStep = index
        knownProgress[recipe.id] = index
        let previous = progressWrite
        progressWrite = Task {
            await previous?.value
            do { try await store.setStep(index, for: recipe.id) }
            catch { self.error = message(for: error) }
        }
    }

    func finish(_ recipe: Recipe) {
        guard cookID == recipe.id else { return }
        run {
            await self.progressWrite?.value
            self.library.cooked = try await self.store.finish(recipe.id)
            self.knownProgress[recipe.id] = nil
            self.recordUse()
            self.policy.pendingAfterCook = true
            self.quietAfterCook = true
            self.savePolicy()
            self.endCooking()
            self.path = []
        }
    }

    private func syncScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = foreground && cookID != nil
    }

    func homeBecameQuiet() async -> Bool {
        guard ready, isHome, foreground, !busy, share == nil, sharePreview == nil, error == nil else { return false }
        if expired && !expiryBanner && entitlement?.expiryDisclosed == false {
            expiryBanner = true
            do { try await refreshEntitlement(disclosingExpiry: true) }
            catch { self.error = message(for: error) }
            return false
        }
        if library.cooked.count >= 10 && !policy.milestoneOffered {
            milestoneBanner = true
            policy.milestoneOffered = true
            savePolicy()
            return false
        }
        guard quietAfterCook, policy.canRequest(at: Date(), distinctCooked: library.cooked.count,
              isQuiet: !expiryBanner && !milestoneBanner && notice == nil) else { return false }
        quietAfterCook = false
        policy.pendingAfterCook = false
        policy.lastRequest = Date()
        savePolicy()
        return !testing
    }

    func closeExpiryBanner() {
        expiryBanner = false
        quietAfterCook = false
    }

    func closeMilestoneBanner() {
        milestoneBanner = false
        quietAfterCook = false
    }

    private func recordUse() {
        policy.recordUse(Date())
        savePolicy()
    }

    private func savePolicy() {
        if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: "review-policy") }
    }

    func acceptFile(_ file: URL) {
        pendingFiles.append(OpenedFile(url: file, scoped: file.startAccessingSecurityScopedResource()))
        processPendingFile()
    }

    func panelDismissed() {
        if let outgoing = shareAfterPanel {
            shareAfterPanel = nil
            share = outgoing
        }
        if let preview {
            self.preview = nil
            Task { await store.cancelImport(preview.id) }
        }
        processPendingFile()
    }

    func shareDismissed() { processPendingFile() }

    private func processPendingFile() {
        guard ready, panel == nil, !busy, share == nil, shareAfterPanel == nil, !pendingFiles.isEmpty else { return }
        panel = .importing
        let file = pendingFiles.removeFirst()
        run {
            defer { if file.scoped { file.url.stopAccessingSecurityScopedResource() } }
            self.replacePreview(try await self.store.preview(file: file.url))
        }
    }

    func previewFile(_ file: URL) {
        run { self.replacePreview(try await self.store.preview(file: file)) }
    }

    func previewCode(_ code: String) {
        run { self.replacePreview(try await self.store.preview(code: code)) }
    }

    func importFixtureFile() {
        guard testing else { return }
        let mode = ProcessInfo.processInfo.environment["RECIPE_FILE_FIXTURE"]
        run {
            let url: URL
            if mode == "backup" {
                url = try await self.store.backup()
            } else if mode == "corrupt" {
                url = try await self.store.makeCorruptFixture()
            } else {
                let recipe = Recipe(name: L.t("fixture.fileRecipe"), servings: 3,
                                    ingredients: [L.t("fixture.fileIngredient")])
                url = try await self.store.export(recipe, includingNotes: true)
            }
            self.replacePreview(try await self.store.preview(file: url))
        }
    }

    private func replacePreview(_ incoming: ImportPreview) {
        guard panel == .importing else {
            Task { await store.cancelImport(incoming.id) }
            return
        }
        if let old = preview { Task { await store.cancelImport(old.id) } }
        preview = incoming
    }

    func cancelPreview() {
        guard let preview else { return }
        self.preview = nil
        Task { await store.cancelImport(preview.id) }
    }

    func confirmImport() {
        guard let preview else { return }
        run {
            self.library = try await self.store.restore(preview.id)
            self.preview = nil
            self.query = ""
            self.selectedBook = nil
            self.notice = L.t(!preview.isBackup && preview.skipped == preview.recipes ? "import.alreadySaved" : "import.saved")
            self.panel = nil
        }
    }

    func copyCode(_ recipe: Recipe) {
        run {
            do {
                let code = try RecipeTransfer.makeCode(recipe)
                UIPasteboard.general.string = code
                self.notice = L.t("code.copied")
            } catch RecipeIssue.longCode {
                self.offerEditableFile = recipe
                self.error = RecipeIssue.longCode.localizedDescription
            }
        }
    }

    func copyTags(_ recipe: Recipe) {
        UIPasteboard.general.string = L.f("share.topicText", recipe.name as NSString)
        notice = L.t("share.tagsCopied")
    }

    func export(_ recipe: Recipe, includingNotes: Bool) {
        run { self.share = SharedItems(urls: [try await self.store.export(recipe, includingNotes: includingNotes)]) }
    }

    func backup() {
        guard hasPro else { panel = .paywall; return }
        run {
            self.shareAfterPanel = SharedItems(urls: [try await self.store.backup()])
            self.panel = nil
        }
    }

    func shareRecipe(_ recipe: Recipe, displayPreview: Bool = false) {
        let qr = shareQR
        run {
            let images = try await self.store.renderShare(recipe, qr: qr)
            if displayPreview { self.sharePreview = SharePreview(urls: images) }
            else { self.share = SharedItems(urls: images) }
        }
    }

    func shareMilestone() {
        let qr = shareQR
        closeMilestoneBanner()
        run { self.share = SharedItems(urls: try await self.store.renderMilestone(qr: qr)) }
    }

    private var shareQR: RecipeCardArt.QR {
        if testing, let value = ProcessInfo.processInfo.environment["RECIPE_TEST_QR"] { return .test(value) }
        return AppStoreLink.url.map(RecipeCardArt.QR.appStore) ?? .placeholder
    }

    func loadProducts() async {
        guard !testing, !free, product == nil || trialProduct == nil else { return }
        do {
            let products = try await Product.products(for: [Purchases.proID, Purchases.trialID])
            product = products.first { $0.id == Purchases.proID }
            trialProduct = products.first { $0.id == Purchases.trialID }
        } catch {
        }
    }

    func purchase(trial: Bool) {
        run {
            await self.loadProducts()
            guard let product = trial ? self.trialProduct : self.product else { throw PurchaseIssue.unavailable }
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { throw PurchaseIssue.verification }
                try await self.accept(transaction)
                self.notice = L.t(trial ? "paywall.trialRecorded" : "paywall.unlocked")
                self.panel = nil
            case .pending:
                self.notice = L.t("paywall.pending")
            case .userCancelled: break
            @unknown default: throw PurchaseIssue.unavailable
            }
        }
    }

    private func accept(_ transaction: StoreKit.Transaction) async throws {
        if transaction.productID == Purchases.proID {
            try await refreshEntitlement(purchased: transaction.revocationDate == nil)
        } else if transaction.productID == Purchases.trialID, transaction.revocationDate == nil {
            try await refreshEntitlement(receipt: transaction.originalPurchaseDate)
        }
        await transaction.finish()
    }

    func restorePurchases() {
        run {
            do { try await AppStore.sync() }
            catch { throw PurchaseIssue.restore }
            let value = await Purchases.status()
            try await self.refreshEntitlement(purchased: value.purchased, receipt: value.receiptDate)
            self.notice = L.t(self.entitlement?.purchasedPro == true || self.entitlement?.trialClaimedAt != nil
                                ? "paywall.restored" : "paywall.nothingToRestore")
        }
    }

    func message(for error: Error) -> String {
        if let error = error as? RecipeIssue { return error.localizedDescription }
        if let error = error as? PurchaseIssue { return error.localizedDescription }
        return RecipeIssue.localStorage.localizedDescription
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer {
                busy = false
                processPendingFile()
            }
            do { try await action() }
            catch { self.error = message(for: error) }
        }
    }

    private func seedExamples() async throws {
        let extra: Book?
        if args.contains("-expired") {
            extra = try await store.saveBook(id: nil, name: L.t("sample.book")).books.first { $0.id != Book.defaultID }
        } else {
            extra = nil
        }
        let expanded = args.contains("-seed-ten")
        let count = expanded ? 10 : 5
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        var first: UUID?
        for index in (0..<count).reversed() {
            let prefix = "sample.\(index + 1)."
            var recipe = Recipe(
                name: L.t(prefix + "name"), servings: [2, 2, 3, 2, 4, 2, 3, 2, 4, 2][index],
                ingredients: L.t(prefix + "ingredients").components(separatedBy: "\n"),
                steps: L.t(prefix + "steps").components(separatedBy: "\n"),
                notes: index == 0 ? L.t("sample.note") : "",
                bookID: index == 1 && args.contains("-expired") ? (extra?.id ?? Book.defaultID) : Book.defaultID,
                createdAt: reference.addingTimeInterval(TimeInterval(index))
            )
            recipe.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 101)) ?? recipe.id
            _ = try await store.save(RecipeDraft(recipe: recipe, isNew: true), canUsePro: true, version: 0)
            if index == 0 { first = recipe.id }
        }
        if let first { _ = try await store.open(first) }
    }
}
