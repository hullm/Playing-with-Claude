import Foundation

// MARK: - API models
//
// ┌───────────────────────────────────────────────────────────────────────────┐
// │ RECONCILE-ME:                                                               │
// │ These structs are modelled from the endpoint summary the server team gave  │
// │ us, NOT from the full field-level reference in `timesheets-dev/API.md`.     │
// │ The field NAMES that appear directly in the API summary (ids, dates, the    │
// │ PUT payload keys, `status`, `editable`, `isCurrent`, `submitBlockedUntil`,  │
// │ `dayTypes`) should be correct. The DISPLAY-ONLY fields — mostly the         │
// │ per-day and per-period hour totals — are best-guess names and are all       │
// │ optional, so decoding never fails if the real key differs. When you have    │
// │ API.md handy, verify the names marked `// inferred` below and adjust.       │
// └───────────────────────────────────────────────────────────────────────────┘

// GET /me
struct Me: Codable, Equatable {
    let id: String
    let name: String
    let email: String
    let role: String
    let fillsTimecard: Bool
}

// GET /periods  → array, newest first
struct Period: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let isCurrent: Bool

    // Inferred display fields — a period almost certainly carries some kind of
    // label and/or start/end dates. All optional so absence is harmless.
    let label: String?      // inferred
    let startDate: String?  // inferred ("YYYY-MM-DD")
    let endDate: String?    // inferred ("YYYY-MM-DD")

    /// Human-friendly title for the menu.
    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let startDate, let endDate { return "\(startDate) – \(endDate)" }
        if let startDate { return startDate }
        return "Period \(id)"
    }
}

// A selectable day-type for the picker, from `dayTypes`.
struct DayType: Codable, Identifiable, Equatable, Hashable {
    let value: String   // sent back as `offReason`
    let label: String

    var id: String { value }

    private enum CodingKeys: String, CodingKey { case value, label, id, name }

    init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    // Tolerant of {value,label} or {id,name} shapes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = (try? c.decode(String.self, forKey: .value))
            ?? (try? c.decode(String.self, forKey: .id))
            ?? ""
        label = (try? c.decode(String.self, forKey: .label))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? value
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(label, forKey: .label)
    }
}

// One day within a timesheet.
struct Day: Codable, Identifiable, Equatable {
    let date: String        // "YYYY-MM-DD"
    var regStart: String    // "HH:MM" or "" when clear
    var regEnd: String
    var otStart: String?
    var otEnd: String?
    var offReason: String?
    var offPortion: String?
    var note: String?

    // Inferred display fields.
    let hours: Double?       // inferred: total hours worked/credited that day
    let weekday: String?     // inferred: e.g. "Mon"

    var id: String { date }

    private enum CodingKeys: String, CodingKey {
        case date, regStart, regEnd, otStart, otEnd, offReason, offPortion, note
        case hours, weekday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        regStart = (try? c.decode(String.self, forKey: .regStart)) ?? ""
        regEnd = (try? c.decode(String.self, forKey: .regEnd)) ?? ""
        otStart = try? c.decodeIfPresent(String.self, forKey: .otStart)
        otEnd = try? c.decodeIfPresent(String.self, forKey: .otEnd)
        offReason = try? c.decodeIfPresent(String.self, forKey: .offReason)
        offPortion = try? c.decodeIfPresent(String.self, forKey: .offPortion)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        hours = try? c.decodeIfPresent(Double.self, forKey: .hours)
        weekday = try? c.decodeIfPresent(String.self, forKey: .weekday)
    }

    /// True when the day has any regular or overtime time entered.
    var hasWorkTime: Bool {
        !(regStart.isEmpty && regEnd.isEmpty
          && (otStart ?? "").isEmpty && (otEnd ?? "").isEmpty)
    }

    /// True when the day is marked as time off.
    var isTimeOff: Bool {
        !(offReason ?? "").isEmpty
    }
}

// GET /timesheet/{id}
struct Timesheet: Codable, Equatable {
    let id: String
    var days: [Day]
    let status: String
    let editable: Bool
    let submitBlockedUntil: String?   // date/datetime string, or null
    let dayTypes: [DayType]

    // Inferred period-level hour totals for the summary line.
    let periodHours: Double?          // inferred
    let regularHours: Double?         // inferred
    let overtimeHours: Double?        // inferred
    let timeOffHours: Double?         // inferred

    private enum CodingKeys: String, CodingKey {
        case id, days, status, editable, submitBlockedUntil, dayTypes
        case periodHours, regularHours, overtimeHours, timeOffHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        days = (try? c.decode([Day].self, forKey: .days)) ?? []
        status = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
        editable = (try? c.decode(Bool.self, forKey: .editable)) ?? false
        submitBlockedUntil = try? c.decodeIfPresent(String.self, forKey: .submitBlockedUntil)
        dayTypes = (try? c.decode([DayType].self, forKey: .dayTypes)) ?? []
        periodHours = try? c.decodeIfPresent(Double.self, forKey: .periodHours)
        regularHours = try? c.decodeIfPresent(Double.self, forKey: .regularHours)
        overtimeHours = try? c.decodeIfPresent(Double.self, forKey: .overtimeHours)
        timeOffHours = try? c.decodeIfPresent(Double.self, forKey: .timeOffHours)
    }
}

// PUT /timesheet/{id}/day  request body
struct DayUpdate: Codable {
    let date: String
    let regStart: String
    let regEnd: String
    let otStart: String?
    let otEnd: String?
    let offReason: String?
    let offPortion: String?
    let note: String?
}

// Standard error envelope: many endpoints return `{ "error": "..." }`.
struct APIErrorBody: Codable {
    let error: String?
    let message: String?

    var text: String? { error ?? message }
}
