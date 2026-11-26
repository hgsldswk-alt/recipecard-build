import Foundation

struct ParsedRecipeText: Equatable {
    var name: String?
    var servings: Int?
    var ingredients: [String] = []
    var steps: [String] = []
    var notes = ""
    var hadSections = false
}

enum RecipeText {
    private enum Section { case ingredients, steps, notes }
    private static let headings: [String: Section] = [
        "食材": .ingredients, "材料": .ingredients, "配料": .ingredients, "ingredients": .ingredients,
        "做法": .steps, "步骤": .steps, "步驟": .steps, "作法": .steps, "做法步骤": .steps,
        "directions": .steps, "steps": .steps, "method": .steps, "instructions": .steps,
        "备注": .notes, "備註": .notes, "自用备注": .notes, "自用備註": .notes, "notes": .notes,
        "小贴士": .notes, "小貼士": .notes, "小撇步": .notes, "tips": .notes
    ]
    private static let heading = try! NSRegularExpression(
        pattern: #"^\s*(?:#{1,6}\s*)?(?:[【\[]\s*)?([^:：】\]]+?)(?:\s*[】\]])?\s*(?:[:：]\s*(.*))?$"#
    )
    private static let portions = try! NSRegularExpression(
        pattern: #"^(?:原始份數|原始份数|份數|份数|servings?)\s*[:：]\s*([0-9]{1,2})$|^([0-9]{1,2})\s*人份$"#,
        options: .caseInsensitive
    )

    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parse(_ text: String) throws -> ParsedRecipeText {
        let source = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeIssue.emptyText }
        let lines = source.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        var result = ParsedRecipeText()
        var section: Section?
        var notes: [String] = []
        var titleLine: Int?

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let groups = match(heading, line), let key = groups[1],
               let next = headings[key.trimmingCharacters(in: .whitespaces).lowercased()] {
                section = next
                if next != .notes { result.hadSections = true }
                if let inline = groups[2], !inline.isEmpty {
                    append(inline, section: next, result: &result, notes: &notes)
                }
            } else if section != nil, line.hasPrefix("##") || line.hasPrefix("【") {
                section = .notes
                notes.append(raw)
            } else if section == nil, let groups = match(portions, line),
                      let number = Int(groups[1] ?? groups[2] ?? ""), (1...24).contains(number) {
                result.servings = number
            } else {
                if result.name == nil, section == nil, !line.isEmpty, line.count <= 80,
                   !line.contains(":"), !line.contains("："), !line.hasPrefix("-"),
                   !line.hasPrefix("•"), !line.hasPrefix("http"),
                   Ingredient(line).amount == nil, lines[..<index].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.name = line
                    titleLine = notes.count
                }
                if let section {
                    append(raw, section: section, result: &result, notes: &notes)
                } else {
                    notes.append(raw)
                }
            }
        }
        if result.hadSections, let titleLine { notes.remove(at: titleLine) }
        result.notes = notes.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return result
    }

    static func match(_ regex: NSRegularExpression, _ text: String) -> [String?]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func append(_ raw: String, section: Section, result: inout ParsedRecipeText, notes: inout [String]) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        switch section {
        case .ingredients:
            if !line.isEmpty {
                result.ingredients.append(line.replacingOccurrences(of: #"^[-•*]\s+"#, with: "", options: .regularExpression))
            }
        case .steps:
            if !line.isEmpty {
                let step = line.replacingOccurrences(of: #"^(?:[0-9]+[.、)）](?![0-9])|[-•*])\s*"#,
                                                      with: "", options: .regularExpression)
                result.steps.append(step.isEmpty ? line : step)
            }
        case .notes:
            notes.append(raw)
        }
    }
}

struct Ingredient: Codable, Equatable, Sendable {
    struct Quantity: Codable, Equatable, Sendable {
        var numerator: Int64
        var denominator: Int64

        init?(_ source: String) {
            let parts = source.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2 {
                guard let n = Int64(parts[0]), let d = Int64(parts[1]), n > 0, d > 0 else { return nil }
                numerator = n
                denominator = d
            } else {
                let decimal = source.split(separator: ".", omittingEmptySubsequences: false)
                guard decimal.count <= 2, let n = Int64(decimal.joined()), n > 0 else { return nil }
                numerator = n
                denominator = decimal.count == 2 ? decimal[1].reduce(1) { value, _ in value * 10 } : 1
            }
        }
    }

    private static let number = #"(?:[0-9]{1,7}/[0-9]{1,7}|[0-9]{1,7}(?:\.[0-9]{1,7})?|\.[0-9]{1,7})"#
    private static let atStart = try! NSRegularExpression(
        pattern: #"^\s*([-•*]\s+)?("# + number + #")(?=\s|[\p{L}])(.+)$"#
    )
    private static let afterName = try! NSRegularExpression(
        pattern: #"^([^0-9]+?)("# + number + #")(?=\s|[\p{L}]|$)([^0-9]*)$"#
    )
    private static let ambiguous = try! NSRegularExpression(
        pattern: #"[0-9]\s*(?:[-–—~～至到×xX]|又|[+])\s*[0-9]|適量|适量|少許|少许|左右|大約|大约|約|约|to taste|as needed|about|approx|[½¼¾⅓⅔]|[0-9],[0-9]"#,
        options: .caseInsensitive
    )
    private static let chineseUnits = ["毫升", "公斤", "茶匙", "大匙", "小匙", "大勺", "小勺", "湯匙", "汤匙",
                                       "公克", "毫米", "个", "個", "克", "斤", "升", "杯", "勺", "片", "瓣", "根",
                                       "顆", "颗", "朵", "条", "條", "尾", "块", "塊", "包", "袋"]
    private static let latinUnits: Set<String> = ["tsp", "tbsp", "cup", "cups", "g", "kg", "ml", "l", "oz", "lb",
                                                  "lbs", "gram", "grams", "liter", "liters", "teaspoon",
                                                  "teaspoons", "tablespoon", "tablespoons", "clove", "cloves",
                                                  "slice", "slices"]

    let raw: String
    var amount: Quantity?
    var unit: String?
    var name: String?
    var prefix = ""
    var suffix = ""

    init(_ raw: String) {
        self.raw = raw
        guard RecipeText.match(Self.ambiguous, raw) == nil else { return }
        if let groups = RecipeText.match(Self.atStart, raw), let number = groups[2], let tail = groups[3],
           let parsed = Quantity(number), tail.first(where: { !$0.isWhitespace })?.isLetter == true,
           !tail.contains(where: \.isNumber), Self.details(tail).name?.isEmpty == false {
            amount = parsed
            prefix = groups[1] ?? ""
            suffix = tail
            (unit, name) = Self.details(tail)
        } else if let groups = RecipeText.match(Self.afterName, raw), let name = groups[1],
                  let number = groups[2], let tail = groups[3], let parsed = Quantity(number),
                  name.contains(where: \.isLetter),
                  !(name.trimmingCharacters(in: .whitespaces).last.map { "-−+".contains($0) } ?? false),
                  tail.isEmpty || tail.first(where: { !$0.isWhitespace })?.isLetter == true {
            amount = parsed
            prefix = name
            suffix = tail
            self.name = name.trimmingCharacters(in: .whitespaces)
            let units = tail.trimmingCharacters(in: .whitespaces)
            unit = units.isEmpty ? nil : units
        }
    }

    private static func details(_ source: String) -> (unit: String?, name: String?) {
        let clean = source.trimmingCharacters(in: .whitespaces)
        if let unit = chineseUnits.first(where: { clean.hasPrefix($0) }) {
            return (unit, String(clean.dropFirst(unit.count)).trimmingCharacters(in: .whitespaces))
        }
        if let first = clean.split(whereSeparator: \.isWhitespace).first,
           latinUnits.contains(first.lowercased()) {
            let remainder = clean.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
            let name = remainder.hasPrefix("of ") ? String(remainder.dropFirst(3)) : remainder
            return (String(first), name)
        }
        return (nil, clean)
    }

    func scaled(from original: Int, to target: Int) -> String {
        guard (1...24).contains(original), (1...24).contains(target), let amount, original != target else { return raw }
        let denominator = amount.denominator * Int64(original)
        let numerator = amount.numerator * Int64(target) * 100
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        let hundredths = (quotient + (remainder * 2 >= denominator ? 1 : 0))
        let display = Decimal(hundredths) / 100
        let formatted = NSDecimalNumber(decimal: display).description(withLocale: Locale.current)
        let value = remainder == 0 ? formatted : L.f("portion.approximate", formatted as NSString)
        return prefix + value + suffix
    }
}
