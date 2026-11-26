import Foundation

struct Entitlement: Codable, Equatable, Sendable {
    var firstOpen: Date
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var latestSeen: Date?
    var purchasedPro = false
    var expiryDisclosed = false

    var trialStart: Date { proStartedAt ?? firstOpen }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || (now >= trialStart && max(now, latestSeen ?? now) < trialEnd)
    }

    mutating func observe(_ now: Date, free: Bool) {
        if !free { proStartedAt = proStartedAt ?? now }
        latestSeen = max(now, latestSeen ?? now)
    }

    mutating func reconcile(purchased: Bool?, receiptDate: Date?) {
        if let purchased { purchasedPro = purchased }
        if let receiptDate {
            trialClaimedAt = min(trialClaimedAt ?? receiptDate, receiptDate)
            proStartedAt = min(trialStart, receiptDate)
        }
    }
}

struct ReviewPolicy: Codable, Equatable {
    var useDays: Set<String> = []
    var lastRequest: Date?
    var pendingAfterCook = false
    var milestoneOffered = false

    mutating func recordUse(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        if useDays.count < 3, let year = day.year, let month = day.month, let date = day.day {
            useDays.insert("\(year)-\(month)-\(date)")
        }
    }

    func canRequest(at now: Date, distinctCooked: Int, isQuiet: Bool) -> Bool {
        pendingAfterCook && isQuiet && useDays.count >= 3 && distinctCooked >= 3 &&
        (lastRequest.map { now.timeIntervalSince($0) >= 120 * 86_400 } ?? true)
    }
}
