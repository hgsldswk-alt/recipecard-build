import StoreKit
import SwiftUI
import UIKit

@main @MainActor
struct RecipeCardApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            AppRoot(model: model)
                .preferredColorScheme(.light)
                .task { await model.boot() }
                .task(id: model.ready) { await model.observePurchases() }
                .task(id: phase) {
                    model.sceneChanged(phase)
                    guard phase == .active else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(20)) }
                        catch { break }
                        model.tick()
                    }
                }
                .onOpenURL { model.acceptFile($0) }
        }
    }
}

struct AppRoot: View {
    @Bindable var model: AppModel
    @Environment(\.requestReview) private var requestReview

    private struct QuietState: Equatable {
        let path: [AppModel.Destination]
        let panel: AppModel.Panel?
        let share: UUID?
        let preview: UUID?
        let ready: Bool
        let active: Bool
        let busy: Bool
        let expired: Bool
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            HomeView(model: model)
                .navigationDestination(for: AppModel.Destination.self) { destination in
                    switch destination {
                    case .detail(let id): DetailView(model: model, recipeID: id)
                    }
                }
        }
        .tint(Paper.brand)
        .sheet(item: $model.panel, onDismiss: model.panelDismissed) { panel in
            NavigationStack { panelContent(for: panel) }
                .tint(Paper.brand)
                .modifier(Feedback(model: model, inPanel: true))
                .interactiveDismissDisabled(panel == .editor || model.busy)
        }
        .sheet(item: $model.share, onDismiss: model.shareDismissed) { share in
            ActivitySheet(urls: share.urls) { model.share = nil }
                .ignoresSafeArea()
        }
        .sheet(item: $model.sharePreview) { preview in
            NavigationStack {
                CardPreviewScreen(urls: preview.urls) { model.sharePreview = nil }
            }
        }
        .modifier(Feedback(model: model, inPanel: false))
        .task(id: QuietState(path: model.path, panel: model.panel, share: model.share?.id,
                             preview: model.sharePreview?.id, ready: model.ready, active: model.foreground,
                             busy: model.busy, expired: model.expired)) {
            guard model.isHome else { return }
            do { try await Task.sleep(for: .milliseconds(280)) }
            catch { return }
            if await model.homeBecameQuiet() { requestReview() }
        }
    }

    @ViewBuilder private func panelContent(for panel: AppModel.Panel) -> some View {
        switch panel {
        case .editor: EditorView(model: model)
        case .importing: ImportView(model: model)
        case .settings: SettingsView(model: model)
        case .paywall: PaywallView(model: model)
        }
    }
}

private struct Feedback: ViewModifier {
    @Bindable var model: AppModel
    let inPanel: Bool

    private var active: Bool { inPanel ? model.panel != nil : model.panel == nil && model.share == nil }
    private var showingError: Binding<Bool> {
        Binding(get: { active && model.error != nil }, set: { if !$0 && active { model.error = nil } })
    }

    func body(content: Content) -> some View {
        content
            .alert(L.t("common.error"), isPresented: showingError) {
                if let recipe = model.offerEditableFile {
                    Button(L.t("export.family")) {
                        model.offerEditableFile = nil
                        model.error = nil
                        model.export(recipe, includingNotes: false)
                    }
                    Button(L.t("common.cancel"), role: .cancel) {
                        model.offerEditableFile = nil
                        model.error = nil
                    }
                } else {
                    Button(L.t("common.ok")) { model.error = nil }
                }
            } message: {
                Text(model.error ?? "")
            }
            .overlay(alignment: .bottom) {
                if active, let notice = model.notice {
                    Text(notice).font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Paper.ink, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("notice")
                        .task(id: notice) {
                            do { try await Task.sleep(for: .seconds(3)) }
                            catch { return }
                            if model.notice == notice { model.notice = nil }
                        }
                }
            }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]
    let finished: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in finished() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct CardPreviewScreen: View {
    let urls: [URL]
    let done: () -> Void

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(urls, id: \.self) { url in
                        PreviewImage(url: url)
                    }
                }
                .padding(22)
            }
        }
        .navigationTitle(L.t("share.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button(L.t("common.done"), action: done).accessibilityIdentifier("preview-done")
        } }
    }
}

private struct PreviewImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel(L.t("share.title")).accessibilityIdentifier("share-preview-image")
            } else {
                ProgressView().frame(height: 250)
            }
        }
        .task {
            image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
        }
    }
}
