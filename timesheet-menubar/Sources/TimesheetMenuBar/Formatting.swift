import Foundation

/// Parsing helpers for the string date/time formats the API uses.
/// All timesheet times are US Eastern per the API contract.
enum DateParsing {
    static let eastern = TimeZone(identifier: "America/New_York") ?? .current

    /// Parse a `submitBlockedUntil` value, which may be a date or a datetime.
    static func parse(_ raw: String) -> Date? {
        // Try ISO 8601 datetime first (with and without fractional seconds).
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }

        // Fall back to a plain "YYYY-MM-DD" (interpreted at midnight Eastern).
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = eastern
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: raw)
    }

    /// Turn "YYYY-MM-DD" into a display string like "Mon, Jul 6".
    static func displayDate(_ raw: String) -> String {
        let inFmt = DateFormatter()
        inFmt.calendar = Calendar(identifier: .gregorian)
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = eastern
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: raw) else { return raw }

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US")
        outFmt.timeZone = eastern
        outFmt.dateFormat = "EEE, MMM d"
        return outFmt.string(from: date)
    }

    static func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Validation + light normalisation for "HH:MM" 24-hour time strings.
enum TimeString {
    /// True if `s` is empty (meaning "clear") or a valid 24-hour "HH:MM".
    static func isValid(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              parts[0].count == 2, parts[1].count == 2,
              (0...23).contains(h), (0...59).contains(m) else {
            return false
        }
        return true
    }

    /// Normalise loose input ("9:5", "9.05", "930") toward "HH:MM" where possible.
    /// Returns the input unchanged if it can't be confidently parsed.
    static func normalized(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "" }

        // "HH:MM" style with 1–2 digit parts.
        let sep = t.replacingOccurrences(of: ".", with: ":")
        let parts = sep.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return String(format: "%02d:%02d", h, m)
        }

        // Bare digits: "930" → 09:30, "9" → 09:00, "1430" → 14:30.
        if t.allSatisfy(\.isNumber) {
            switch t.count {
            case 1, 2:
                if let h = Int(t), (0...23).contains(h) { return String(format: "%02d:00", h) }
            case 3:
                let h = Int(t.prefix(1)); let m = Int(t.suffix(2))
                if let h, let m, (0...23).contains(h), (0...59).contains(m) {
                    return String(format: "%02d:%02d", h, m)
                }
            case 4:
                let h = Int(t.prefix(2)); let m = Int(t.suffix(2))
                if let h, let m, (0...23).contains(h), (0...59).contains(m) {
                    return String(format: "%02d:%02d", h, m)
                }
            default:
                break
            }
        }
        return t
    }
}

extension Double {
    /// Compact hours label: 8.0 → "8", 7.5 → "7.5", 7.25 → "7.25".
    var hoursLabel: String {
        if self == rounded() { return String(format: "%.0f", self) }
        var s = String(format: "%.2f", self)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
