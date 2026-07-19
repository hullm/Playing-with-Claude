import Foundation

// MARK: - API models
//
// These match the field-level reference in `timesheets-dev/API.md`.

// GET /me
struct Me: Codable, Equatable {
    let id: String
    let name: String
    let email: String
    let role: String
    let fillsTimecard: Bool

    /// First name for a friendly greeting.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

// GET /periods → { "periods": [ … ] }, newest first
struct PeriodsResponse: Codable {
    let periods: [Period]
}

struct Period: Codable, Identifiable, Equatable {
    let id: Int
    let label: String
    let startsOn: String   // "YYYY-MM-DD"
    let endsOn: String     // "YYYY-MM-DD"
    let status: String     // not-started · draft · submitted · approved · accepted · rejected
    let isCurrent: Bool

    /// True when there's no sheet for this period yet.
    var notStarted: Bool { status == "not-started" }

    /// True for a finished timesheet (shown as "Complete").
    var isCompleted: Bool { status.lowercased() == "accepted" }
}

/// The lighter `period` object embedded in a timesheet response.
struct PeriodInfo: Codable, Equatable {
    let id: Int
    let label: String
    let startsOn: String
    let endsOn: String
}

/// Hour tallies — used for both per-day `hours` and period `totals`.
struct HourTotals: Codable, Equatable {
    let reg: Double
    let ot: Double
    let off: Double
    let total: Double
}

/// A time-off type for the reason picker (from `dayTypes`).
struct DayType: Codable, Identifiable, Equatable, Hashable {
    let slug: String    // sent back as `offReason`
    let label: String
    var id: String { slug }
}

/// A portion-of-day option for time off (from `offPortions`): full · am · pm.
struct OffPortionOption: Codable, Identifiable, Equatable, Hashable {
    let value: String   // sent back as `offPortion`
    let label: String
    var id: String { value }
}

// One day within a timesheet.
struct Day: Codable, Identifiable, Equatable {
    let date: String        // "YYYY-MM-DD"
    let weekday: String     // "Mon"
    let isWeekend: Bool
    var regStart: String    // "HH:MM" or ""
    var regEnd: String
    var otStart: String
    var otEnd: String
    var offReason: String   // a DayType.slug, or ""
    var offPortion: String  // "full" | "am" | "pm", or ""
    var note: String
    let hours: HourTotals
    let saved: Bool         // false = pre-filled default, not yet written

    var id: String { date }

    // Defensive decoding: coerce nulls to "" so the editor always has strings.
    private enum CodingKeys: String, CodingKey {
        case date, weekday, isWeekend, regStart, regEnd, otStart, otEnd
        case offReason, offPortion, note, hours, saved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        weekday = (try? c.decode(String.self, forKey: .weekday)) ?? ""
        isWeekend = (try? c.decode(Bool.self, forKey: .isWeekend)) ?? false
        regStart = (try? c.decodeIfPresent(String.self, forKey: .regStart)) ?? ""
        regEnd = (try? c.decodeIfPresent(String.self, forKey: .regEnd)) ?? ""
        otStart = (try? c.decodeIfPresent(String.self, forKey: .otStart)) ?? ""
        otEnd = (try? c.decodeIfPresent(String.self, forKey: .otEnd)) ?? ""
        offReason = (try? c.decodeIfPresent(String.self, forKey: .offReason)) ?? ""
        offPortion = (try? c.decodeIfPresent(String.self, forKey: .offPortion)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        hours = (try? c.decode(HourTotals.self, forKey: .hours))
            ?? HourTotals(reg: 0, ot: 0, off: 0, total: 0)
        saved = (try? c.decode(Bool.self, forKey: .saved)) ?? true
    }

    var isTimeOff: Bool { !offReason.isEmpty }

    var hasWorkTime: Bool {
        !(regStart.isEmpty && regEnd.isEmpty && otStart.isEmpty && otEnd.isEmpty)
    }
}

// GET /timesheet/{periodId}  (also the shape returned by PUT day and POST submit)
struct Timesheet: Codable, Equatable {
    let period: PeriodInfo
    let status: String
    let editable: Bool
    let defaults: Defaults
    let fullDayHours: Double
    let submitBlockedUntil: String?   // human string ("Fri Jul 17 at 3:30 PM") or null
    let totals: HourTotals
    let dayTypes: [DayType]
    let offPortions: [OffPortionOption]
    var days: [Day]

    struct Defaults: Codable, Equatable {
        let regStart: String
        let regEnd: String
    }

    var id: Int { period.id }

    /// null means "submittable now"; a string means blocked with that message.
    var isSubmitBlocked: Bool { (submitBlockedUntil?.isEmpty == false) }
}

// GET /me/defaults  and the response of  PUT /me/defaults
struct WorkdayDefaults: Codable, Equatable {
    let regStart: String            // "HH:MM" 24-hour
    let regEnd: String
    let fullDayHours: Double?        // read-only; may be absent on PUT responses
}

// PUT /me/defaults  request body
struct DefaultsUpdate: Codable {
    let regStart: String
    let regEnd: String
}

// PUT /timesheet/{periodId}/day  request body.
// All fields optional except `date`; "" clears. We send the full day so the
// server can reconcile worked time and time off in one call.
struct DayUpdate: Codable {
    let date: String
    let regStart: String
    let regEnd: String
    let otStart: String
    let otEnd: String
    let offReason: String
    let offPortion: String
    let note: String
}

// Standard error envelope on 409/422: { "error": "…" }
struct APIErrorBody: Codable {
    let error: String?
    let message: String?
    var text: String? { error ?? message }
}
