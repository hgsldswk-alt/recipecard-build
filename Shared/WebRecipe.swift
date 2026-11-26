import Foundation

enum WebRecipe {
    static let maxBytes = 4_000_000

    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2_000,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              var url = match.url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        guard Double(match.range.length) >= Double((trimmed as NSString).length) * 0.6 else { return nil }
        if scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.scheme = "https"
            url = parts.url ?? url
        }
        return url
    }

    static func fetch(_ url: URL) async throws -> ParsedRecipeText {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= maxBytes else { throw RecipeIssue.webRecipe }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard let parsed = parse(html: html) else { throw RecipeIssue.webRecipe }
        return parsed
    }

    static func parse(html: String) -> ParsedRecipeText? {
        for block in jsonLDBlocks(html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let node = findRecipe(json) else { continue }
            var result = ParsedRecipeText()
            result.name = (node["name"] as? String).map(clean).flatMap { $0.isEmpty ? nil : $0 }
            result.servings = servings(node["recipeYield"])
            result.ingredients = strings(node["recipeIngredient"] ?? node["ingredients"]).map(clean).filter { !$0.isEmpty }
            result.steps = steps(node["recipeInstructions"]).map(clean).filter { !$0.isEmpty }
            result.hadSections = true
            if !result.ingredients.isEmpty || !result.steps.isEmpty { return result }
        }
        return nil
    }

    private static func jsonLDBlocks(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func isRecipe(_ type: Any?) -> Bool {
        if let s = type as? String { return s.lowercased().hasSuffix("recipe") }
        if let a = type as? [Any] { return a.contains { isRecipe($0) } }
        return false
    }

    private static func findRecipe(_ json: Any, depth: Int = 0) -> [String: Any]? {
        guard depth < 6 else { return nil }
        if let dict = json as? [String: Any] {
            if isRecipe(dict["@type"]) { return dict }
            for key in ["@graph", "mainEntity", "itemListElement", "item"] {
                if let child = dict[key], let found = findRecipe(child, depth: depth + 1) { return found }
            }
        } else if let array = json as? [Any] {
            for item in array { if let found = findRecipe(item, depth: depth + 1) { return found } }
        }
        return nil
    }

    private static func strings(_ value: Any?) -> [String] {
        if let s = value as? String { return [s] }
        if let a = value as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private static func steps(_ value: Any?, depth: Int = 0) -> [String] {
        guard depth < 4 else { return [] }
        if let s = value as? String {
            let split = s.replacingOccurrences(of: #"<\s*(br|/p|/li)\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            return RecipeText.lines(split)
        }
        if let a = value as? [Any] { return a.flatMap { steps($0, depth: depth + 1) } }
        if let d = value as? [String: Any] {
            if let items = d["itemListElement"] { return steps(items, depth: depth + 1) }   // HowToSection
            if let text = d["text"] as? String { return [text] }                               // HowToStep
            if let name = d["name"] as? String { return [name] }
        }
        return []
    }

    private static func servings(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { let v = n.intValue; return (1...24).contains(v) ? v : nil }
        if let a = value as? [Any] { return a.first.flatMap { servings($0) } }
        guard let s = (value as? String)?.applyingTransform(.fullwidthToHalfwidth, reverse: false),
              let range = s.range(of: #"\d{1,2}"#, options: .regularExpression),
              let v = Int(s[range]), (1...24).contains(v) else { return nil }
        return v
    }

    static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                        "&nbsp;": " ", "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾", "&deg;": "°", "&#8217;": "’", "&#8211;": "–"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
