import SwiftUI
import UIKit

enum Paper {
    static let base = Color(red: 248.0 / 255, green: 245.0 / 255, blue: 239.0 / 255)
    static let sheet = Color(uiColor: RecipeCardArt.paper)
    static let ink = Color(uiColor: RecipeCardArt.ink)
    static let muted = Color(red: 98.0 / 255, green: 90.0 / 255, blue: 83.0 / 255)
    static let brand = Color(uiColor: RecipeCardArt.brand)
    static let line = Color(uiColor: RecipeCardArt.line)
    static let wash = Color(red: 248.0 / 255, green: 234.0 / 255, blue: 228.0 / 255)

    static func title(_ text: String) -> some View {
        Text(text).font(.largeTitle.weight(.heavy)).tracking(-0.8)
            .foregroundStyle(ink).accessibilityAddTraits(.isHeader)
    }
}

struct PaperCard: ViewModifier {
    var radius: CGFloat = 15
    var fill = Paper.sheet
    var border = Paper.line

    func body(content: Content) -> some View {
        content.background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1).allowsHitTesting(false)
            }
    }
}

struct PaperButton: ButtonStyle {
    var primary = true
    var tall = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: tall ? 53 : 46)
            .foregroundStyle(primary ? .white : Paper.ink)
            .modifier(PaperCard(radius: 12, fill: primary ? Paper.brand : Paper.sheet,
                                border: primary ? .clear : Paper.line))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Rectangle())
    }
}

struct IconButton: View {
    let key: String
    let symbol: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t(key))
        .accessibilityIdentifier(id)
    }
}

struct SectionLabel: View {
    var key: String
    var body: some View {
        Text(L.t(key)).font(.subheadline.weight(.heavy)).accessibilityAddTraits(.isHeader)
    }
}

struct PaperScreen<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Paper.base.ignoresSafeArea())
            .foregroundStyle(Paper.ink)
            .tint(Paper.brand)
    }
}

struct NoteBanner: View {
    let text: String
    let id: String
    var actionKey: String? = nil
    var action: (() -> Void)? = nil
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(text).font(.footnote.weight(.medium))
                    .padding(.top, 9)
                if let action, let actionKey {
                    Button(L.t(actionKey), action: action)
                        .font(.subheadline.weight(.bold)).padding(.vertical, 7)
                        .accessibilityIdentifier(id + "-action")
                }
            }
            Spacer(minLength: 0)
            IconButton(key: "common.dismiss", symbol: "xmark", id: id + "-dismiss", action: dismiss)
                .foregroundStyle(Paper.muted)
        }
        .padding(.leading, 12)
        .modifier(PaperCard(radius: 10, fill: Paper.wash))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

struct RecipePhotoView: View {
    let store: RecipeStore
    let path: String?
    var pending: Data? = nil
    @State private var image: UIImage?

    private struct Input: Equatable {
        let path: String?
        let pending: Data?
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit().frame(maxHeight: 260).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(L.t("photo.label"))
                    .accessibilityIdentifier("recipe-photo")
            }
        }
        .task(id: Input(path: path, pending: pending)) {
            image = nil
            let data: Data?
            if let pending { data = pending } else { data = try? await store.photoData(path) }
            let loaded = await Task.detached { data.flatMap { UIImage(data: $0)?.preparingForDisplay() } }.value
            if !Task.isCancelled { image = loaded }
        }
    }
}
