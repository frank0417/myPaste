import Foundation

/// Favorites are the long-term library; everything else is a short-lived buffer.
/// Age counts from the last time an item was used, so re-pasting something keeps it
/// around instead of letting a still-useful record expire on its copy date.
enum RetentionPolicy {
    static let defaultDays = 3
    static let minimumDays = 1
    static let maximumDays = 30

    private static let day: TimeInterval = 24 * 60 * 60

    static func clampDays(_ days: Int) -> Int {
        min(max(days, minimumDays), maximumDays)
    }

    static func isProtected(isFavorite: Bool, isPinned: Bool) -> Bool {
        isFavorite || isPinned
    }

    /// Items last used before this moment have outlived the buffer.
    static func cutoff(days: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(clampDays(days)) * day)
    }

    static func expiry(lastUsed: Date, days: Int) -> Date {
        lastUsed.addingTimeInterval(Double(clampDays(days)) * day)
    }

    static func isExpired(
        isFavorite: Bool,
        isPinned: Bool,
        lastUsed: Date,
        days: Int,
        now: Date
    ) -> Bool {
        guard !isProtected(isFavorite: isFavorite, isPinned: isPinned) else { return false }
        return lastUsed < cutoff(days: days, now: now)
    }

    /// One line explaining what will happen to this record, for the detail views.
    static func statusText(
        isFavorite: Bool,
        isPinned: Bool,
        lastUsed: Date,
        days: Int,
        now: Date
    ) -> String {
        if isFavorite { return PanelL10n.keptFavorite }
        if isPinned { return PanelL10n.keptPinned }
        let remaining = expiry(lastUsed: lastUsed, days: days).timeIntervalSince(now)
        if remaining <= 0 { return PanelL10n.expired }
        if remaining < day { return PanelL10n.expiresUnderOneDay }
        return PanelL10n.expiresInDays(Int(remaining / day))
    }

    /// Cards flag only the last day, where losing the item is imminent.
    static func isExpiringSoon(
        isFavorite: Bool,
        isPinned: Bool,
        lastUsed: Date,
        days: Int,
        now: Date
    ) -> Bool {
        guard !isProtected(isFavorite: isFavorite, isPinned: isPinned) else { return false }
        return expiry(lastUsed: lastUsed, days: days).timeIntervalSince(now) < day
    }
}

extension ClipboardItem {
    var isRetentionProtected: Bool {
        RetentionPolicy.isProtected(isFavorite: isFavorite, isPinned: isPinned)
    }

    /// `nil` while the item is kept indefinitely.
    func retentionExpiry(days: Int) -> Date? {
        guard !isRetentionProtected else { return nil }
        return RetentionPolicy.expiry(lastUsed: updatedAt, days: days)
    }

    func retentionStatus(days: Int, now: Date = .now) -> String {
        RetentionPolicy.statusText(
            isFavorite: isFavorite,
            isPinned: isPinned,
            lastUsed: updatedAt,
            days: days,
            now: now
        )
    }

    func isExpiringSoon(days: Int, now: Date = .now) -> Bool {
        RetentionPolicy.isExpiringSoon(
            isFavorite: isFavorite,
            isPinned: isPinned,
            lastUsed: updatedAt,
            days: days,
            now: now
        )
    }
}
