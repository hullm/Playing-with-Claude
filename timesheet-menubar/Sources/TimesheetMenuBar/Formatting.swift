import Foundation

/// Parsing helpers for the string date/time formats the API uses.
/// All timesheet times are US Eastern per the API contract.
enum DateParsing {
    static let eastern = TimeZone(identifier: "America/New_York") ?? .current

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

    /// Today's date as "YYYY-MM-DD" in US Eastern (the timesheet's timezone),
    /// so "today" is correct no matter where the user's Mac is set.
    static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = eastern
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Time handling. The API always uses 24-hour "HH:MM"; the UI shows and accepts
/// 12-hour AM/PM. These helpers convert between the two.
///
/// Parsing is forgiving: "7:30 AM", "7:30am", "730a", "3pm" all work. Input with
/// **no** AM/PM is read as 24-hour ("15:30", "1530", "0730") — so what you type
/// is never ambiguous. Everything is displayed back as 12-hour after you commit.
enum TimeString {
    /// True if `s` is empty (meaning "clear") or parses to a valid time.
    static func isValid(_ s: String) -> Bool {
        parse24(s) != nil
    }

    /// Parse flexible 12- or 24-hour input into canonical 24-hour "HH:MM".
    /// Returns "" for empty input (a cleared field), or nil if unparseable.
    static func parse24(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return "" }

        // Pull off an AM/PM suffix if present.
        var meridiem: Int? = nil            // 0 = AM, 1 = PM
        if t.hasSuffix("am") { meridiem = 0; t.removeLast(2) }
        else if t.hasSuffix("pm") { meridiem = 1; t.removeLast(2) }
        else if t.hasSuffix("a") { meridiem = 0; t.removeLast() }
        else if t.hasSuffix("p") { meridiem = 1; t.removeLast() }
        t = t.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: ":")

        var hour = 0
        var minute = 0
        if t.contains(":") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            hour = h; minute = m
        } else if !t.isEmpty, t.allSatisfy(\.isNumber) {
            switch t.count {
            case 1, 2: hour = Int(t) ?? -1
            case 3: hour = Int(t.prefix(1)) ?? -1; minute = Int(t.suffix(2)) ?? -1
            case 4: hour = Int(t.prefix(2)) ?? -1; minute = Int(t.suffix(2)) ?? -1
            default: return nil
            }
        } else {
            return nil
        }

        guard (0...59).contains(minute) else { return nil }

        if let mer = meridiem {
            guard (1...12).contains(hour) else { return nil }
            if mer == 1, hour != 12 { hour += 12 }   // PM
            if mer == 0, hour == 12 { hour = 0 }     // 12 AM → 00
        } else {
            guard (0...23).contains(hour) else { return nil }
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Format a canonical 24-hour "HH:MM" as 12-hour "7:30 AM". Empty stays empty.
    static func display12(_ hhmm24: String) -> String {
        let t = hhmm24.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "" }
        let parts = t.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return hhmm24 }
        let meridiem = h < 12 ? "AM" : "PM"
        var h12 = h % 12
        if h12 == 0 { h12 = 12 }
        return String(format: "%d:%02d %@", h12, m, meridiem)
    }

    /// Re-format a field's text into canonical 12-hour display, leaving it
    /// untouched if it can't be parsed (so the invalid state stays visible).
    static func normalizedDisplay(_ s: String) -> String {
        guard let canonical = parse24(s) else { return s }
        return display12(canonical)
    }
}

/// User-facing wording for a timesheet/period status.
enum StatusLabel {
    static func text(_ status: String) -> String {
        switch status.lowercased() {
        case "accepted": return "Complete"
        default: return status.replacingOccurrences(of: "-", with: " ").capitalized
        }
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
