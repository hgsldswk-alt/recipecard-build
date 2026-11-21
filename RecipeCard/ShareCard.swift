import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum RecipeCardArt {
    static let size = CGSize(width: 360, height: 480)
    static let brand = UIColor(red: 165 / 255, green: 59 / 255, blue: 45 / 255, alpha: 1)
    static let ink = UIColor(red: 37 / 255, green: 33 / 255, blue: 30 / 255, alpha: 1)
    static let paper = UIColor(red: 255 / 255, green: 253 / 255, blue: 248 / 255, alpha: 1)
    static let line = UIColor(red: 230 / 255, green: 219 / 255, blue: 209 / 255, alpha: 1)
    private static let margin: CGFloat = 22
    private static let width: CGFloat = 316

    struct Block {
        var text: String
        let font: UIFont
        let color: UIColor
        let spacing: CGFloat
        var attributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: color] }
    }

    enum QR: Sendable {
        case appStore(URL), test(String), placeholder

        var payload: String? {
            switch self {
            case .appStore(let url): return url.absoluteString
            case .test(let text): return text
            case .placeholder: return nil
            }
        }
    }

    static func qrCode(_ payload: String, scale: Int = 6) -> UIImage? {
        guard scale > 0, scale <= 32 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: .white).cropped(to: extent)
        let combined = output.composited(over: white).cropped(to: extent)
        let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        let scaled = combined.samplingNearest().transformed(by: transform)
            .transformed(by: .init(scaleX: CGFloat(scale), y: CGFloat(scale)))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: image)
    }

    static func render(_ recipe: Recipe, photo: Data?, qr: QR) throws -> [Data] {
        let image = photo.flatMap { UIImage(data: $0) }
        if photo != nil && image == nil { throw RecipeIssue.filePhoto }
        let blocks = blocks(for: recipe)
        let pages = paginate(blocks, firstCapacity: image == nil ? 343 : 237, nextCapacity: 401)
        let code = qr.payload.flatMap { qrCode($0) }
        return try pages.enumerated().map { index, blocks in
            let data: Data = autoreleasepool {
                renderer().pngData { context in
                    frame(context.cgContext)
                    header(in: context.cgContext, page: index + 1, total: pages.count)
                    var y: CGFloat = 58
                    if index == 0, let image {
                        drawPhoto(image, in: CGRect(x: margin, y: y, width: width, height: 96), context: context.cgContext)
                        y += 106
                    }
                    for block in blocks {
                        let height = measure(block, text: block.text)
                        draw(block, rect: CGRect(x: margin, y: y, width: width, height: height + 1))
                        y += height + block.spacing
                    }
                    if index == 0 { footer(context.cgContext, code: code, qr: qr, milestone: false) }
                }
            }
            guard !data.isEmpty else { throw RecipeIssue.share }
            return data
        }
    }

    static func milestone(qr: QR) -> Data {
        let code = qr.payload.flatMap { qrCode($0) }
        return renderer().pngData { context in
            frame(context.cgContext)
            header(in: context.cgContext, page: 1, total: 1)
            let count = Block(text: "10", font: .systemFont(ofSize: 105, weight: .heavy), color: brand, spacing: 0)
            draw(count, rect: CGRect(x: margin, y: 90, width: width, height: 142))
            let title = Block(text: L.t("milestone.card"), font: .systemFont(ofSize: 32, weight: .heavy), color: ink, spacing: 0)
            draw(title, rect: CGRect(x: margin, y: 237, width: width, height: 141))
            footer(context.cgContext, code: code, qr: qr, milestone: true)
        }
    }

    private static func blocks(for recipe: Recipe) -> [Block] {
        let title = Block(text: recipe.name, font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacing: 8)
        var blocks: [Block] = [title]
        if let servings = recipe.servings {
            blocks.append(Block(text: L.f("portion.serves", servings), font: .boldSystemFont(ofSize: 13), color: brand, spacing: 12))
        }
        func heading(_ key: String) -> Block {
            Block(text: L.t(key), font: .boldSystemFont(ofSize: 14), color: brand, spacing: 5)
        }
        if !recipe.ingredients.isEmpty {
            blocks.append(heading("recipe.ingredients"))
            blocks += recipe.ingredients.map { Block(text: $0, font: .systemFont(ofSize: 14), color: ink, spacing: 4) }
        }
        if !recipe.steps.isEmpty {
            blocks.append(heading("recipe.steps"))
            blocks += recipe.steps.enumerated().map {
                Block(text: L.f("share.step", $0.offset + 1, $0.element as NSString),
                      font: .systemFont(ofSize: 15), color: ink, spacing: 6)
            }
        }
        return blocks
    }

    private static func paginate(_ blocks: [Block], firstCapacity: CGFloat, nextCapacity: CGFloat) -> [[Block]] {
        var pages: [[Block]] = [[]]
        var available = firstCapacity
        for block in blocks {
            let text = Array(block.text)
            var start = 0
            while start < text.count {
                let rest = String(text[start...])
                if measure(block, text: rest) + block.spacing <= available {
                    var part = block
                    part.text = rest
                    pages[pages.count - 1].append(part)
                    available -= measure(block, text: rest) + block.spacing
                    break
                }
                if available < block.font.lineHeight * 2 + block.spacing {
                    pages.append([])
                    available = nextCapacity
                    continue
                }
                var lower = 1
                var upper = text.count - start
                while lower < upper {
                    let middle = (lower + upper + 1) / 2
                    if measure(block, text: String(text[start..<(start + middle)])) + block.spacing <= available {
                        lower = middle
                    } else {
                        upper = middle - 1
                    }
                }
                let end = start + lower
                var part = block
                part.text = String(text[start..<end])
                pages[pages.count - 1].append(part)
                pages.append([])
                available = nextCapacity
                start = end
            }
        }
        return pages
    }

    private static func measure(_ block: Block, text: String) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
              options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: block.attributes, context: nil).height)
    }

    private static func draw(_ block: Block, rect: CGRect) {
        (block.text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                      attributes: block.attributes, context: nil)
    }

    private static func renderer() -> UIGraphicsImageRenderer {
        let config = UIGraphicsImageRendererFormat()
        config.scale = 3
        config.opaque = true
        return UIGraphicsImageRenderer(size: size, format: config)
    }

    private static func frame(_ context: CGContext) {
        context.setFillColor(paper.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(brand.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: 7))
    }

    private static func header(in context: CGContext, page: Int, total: Int) {
        let label = total == 1 ? L.t("app.name") :
            L.f("share.pagination", L.t("app.name") as NSString, page, total)
        draw(Block(text: label, font: .boldSystemFont(ofSize: 12), color: brand, spacing: 0),
             rect: CGRect(x: margin, y: 25, width: width, height: 18))
        context.setFillColor(line.cgColor)
        context.fill(CGRect(x: margin, y: 48, width: width, height: 1))
    }

    private static func footer(_ context: CGContext, code: UIImage?, qr: QR, milestone: Bool) {
        context.setFillColor(line.cgColor)
        context.fill(CGRect(x: margin, y: 412, width: width, height: 1))
        let qrRect = CGRect(x: 285, y: 418, width: 53, height: 53)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(qrRect)
        if let code {
            context.saveGState()
            context.interpolationQuality = .none
            let pixels = code.size.width / 6
            let displayedWidth = max(1, floor(qrRect.width * 3 / pixels)) * pixels / 3
            let offset = floor((qrRect.width - displayedWidth) * 1.5) / 3
            code.draw(in: CGRect(x: qrRect.minX + offset, y: qrRect.minY + offset,
                                 width: displayedWidth, height: displayedWidth))
            context.restoreGState()
        } else {
            let symbol = UIImage(systemName: "qrcode")?.withTintColor(brand, renderingMode: .alwaysOriginal)
            symbol?.draw(in: qrRect.insetBy(dx: 12, dy: 12))
        }
        let prompt: String
        if case .appStore = qr, code != nil { prompt = L.t("share.download") }
        else { prompt = L.t("share.placeholder") }
        draw(Block(text: prompt, font: .boldSystemFont(ofSize: 12), color: brand, spacing: 0),
             rect: CGRect(x: margin, y: 425, width: 250, height: 17))
        let tags = L.t(milestone ? "share.milestoneTag" : "share.tags")
        draw(Block(text: tags, font: .systemFont(ofSize: 10), color: ink, spacing: 0),
             rect: CGRect(x: margin, y: 445, width: 250, height: 23))
    }

    private static func drawPhoto(_ image: UIImage, in rect: CGRect, context: CGContext) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        context.setFillColor(line.cgColor)
        context.fill(rect)
        image.draw(in: CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
    }
}
