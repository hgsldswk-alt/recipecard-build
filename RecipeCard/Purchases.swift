import Foundation
import Security
import StoreKit

actor TrialVault {
    private var cached: Entitlement?
    private let testing: Bool
    private let expired: Bool
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hgsldswk.recipecard.trial",
        kSecAttrAccount as String: "entitlement-v1"
    ]

    init(testing: Bool, expired: Bool) {
        self.testing = testing
        self.expired = expired
    }

    func refresh(at now: Date, free: Bool, purchased: Bool? = nil, receipt: Date? = nil,
                 disclosingExpiry: Bool = false) throws -> Entitlement {
        var value = try cached ?? read(at: now)
        let previous = value
        value.observe(now, free: free)
        value.reconcile(purchased: purchased, receiptDate: receipt)
        if disclosingExpiry { value.expiryDisclosed = true }
        if cached == nil || previous != value { try persist(value) }
        cached = value
        return value
    }

    private func read(at now: Date) throws -> Entitlement {
        if testing {
            let firstOpen = now.addingTimeInterval(expired ? -31 * 86_400 : -4 * 86_400)
            return Entitlement(firstOpen: firstOpen, proStartedAt: firstOpen)
        }
        var result: CFTypeRef?
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return Entitlement(firstOpen: now) }
        guard status == errSecSuccess, let data = result as? Data else { throw PurchaseIssue.keychain }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    private func persist(_ value: Entitlement) throws {
        if testing { return }
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PurchaseIssue.keychain }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw PurchaseIssue.keychain }
    }
}

enum PurchaseIssue: String, LocalizedError {
    case keychain, unavailable, verification, restore
    var errorDescription: String? { L.t("purchaseError." + rawValue) }
}

enum Purchases {
    static var proID: String {
        Bundle.main.object(forInfoDictionaryKey: "RecipeProProductID") as? String ?? "com.hgsldswk.recipecard.pro"
    }
    static var trialID: String {
        Bundle.main.object(forInfoDictionaryKey: "RecipeTrialProductID") as? String ?? "com.hgsldswk.recipecard.trial"
    }

    static func status() async -> (purchased: Bool?, receiptDate: Date?) {
        var purchased: Bool?
        var receiptDate: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == proID { purchased = true }
            if transaction.productID == trialID { receiptDate = transaction.originalPurchaseDate }
        }
        if purchased == nil, let result = await StoreKit.Transaction.latest(for: proID),
           case .verified(let transaction) = result {
            purchased = transaction.revocationDate == nil
        }
        return (purchased, receiptDate)
    }
}

struct AppStoreLink {
    static var url: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }
}
