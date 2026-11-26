import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }
    static func number(_ value: Double, decimals: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.*f", locale: Locale.current, decimals, abs(value) < 0.000001 ? 0 : value)
    }
}
