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
    let status: String     // not-started · draft · in_progress · submitted · approved · accepted · rejected
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

/// One reason a portion of a day is off. A day can hold several — e.g. a
/// morning at a screening (`am`) and an afternoon sick (`pm`) — each charged to
/// the leave bucket its reason names. `full`/`am`/`pm` pay POLICY hours and
/// carry no times; `timed` pays CLOCK hours and carries real `start`/`end`.
struct DayOff: Codable, Equatable, Hashable {
    let portion: String       // "full" | "am" | "pm" | "timed"
    let reason: String        // a DayType.slug
    let start: String?        // "HH:MM" 24-hour, present (non-null) only for "timed"
    let end: String?
    let note: String?         // free text about this absence; "" when empty (optional
                              // so an older server that omits it still decodes)
}

/// GET /day-types — the admin-managed catalog of work kinds and off reasons.
/// Preferred over hardcoding slugs; retired off types come back `active: false`
/// (still needed to label an old sheet, but not offered when creating).
struct DayTypesResponse: Codable, Equatable {
    let work: [WorkType]
    let off: [OffType]
}

struct WorkType: Codable, Identifiable, Equatable, Hashable {
    let slug: String
    let label: String
    let kind: String     // "reg" | "ot" — what goes in segments[].kind
    var id: String { slug }
}

struct OffType: Codable, Identifiable, Equatable, Hashable {
    let slug: String     // what goes in off[].reason
    let label: String
    let active: Bool     // false = retired; label it, but don't offer it
    var id: String { slug }

    private enum CodingKeys: String, CodingKey { case slug, label, active }
    init(slug: String, label: String, active: Bool) {
        self.slug = slug; self.label = label; self.active = active
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        label = (try? c.decode(String.self, forKey: .label)) ?? slug
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? true
    }
}

/// One work period within a day. Hours are the SUM of a day's periods, never
/// the span from the first start to the last end.
struct Segment: Codable, Equatable {
    enum Kind: String, Codable { case reg, ot }
    var kind: Kind
    var start: String   // "HH:MM" 24-hour, or ""
    var end: String
    var note: String    // per-period note; may be ""

    private enum CodingKeys: String, CodingKey { case kind, start, end, note }

    init(kind: Kind, start: String, end: String, note: String) {
        self.kind = kind; self.start = start; self.end = end; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient kind: an unrecognized kind falls back to reg rather than throwing.
        let raw = (try? c.decode(String.self, forKey: .kind)) ?? "reg"
        kind = Kind(rawValue: raw) ?? .reg
        start = (try? c.decodeIfPresent(String.self, forKey: .start)) ?? ""
        end = (try? c.decodeIfPresent(String.self, forKey: .end)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }
}

// One day within a timesheet.
struct Day: Codable, Identifiable, Equatable {
    let date: String        // "YYYY-MM-DD"
    let weekday: String     // "Mon"
    let isWeekend: Bool
    // `segments` is the source of truth for worked time on the new API. It's
    // ABSENT (nil) on the un-updated server; present ([] when no work) on the
    // new one — so `nil` cleanly means "flat single-pair mode".
    let segments: [Segment]?
    // `off` is the source of truth for time off on the new API: one entry per
    // portion (a split day carries two). ABSENT (nil) on the old server, so nil
    // cleanly means "flat single-reason mode". Never derive hours from it —
    // `hours` is always server-correct.
    let off: [DayOff]?
    // Flat fields still returned, but on the new API they are only a DISPLAY
    // MIRROR (first-in / last-out; off* name only the FIRST portion). NEVER
    // compute hours or the full off picture from them — use `hours` / `off`.
    var regStart: String    // "HH:MM" or ""
    var regEnd: String
    var otStart: String
    var otEnd: String
    var offReason: String   // a DayType.slug, or "" — legacy mirror only
    var offPortion: String  // "full" | "am" | "pm", or "" — legacy mirror only
    // NOTE: the day-level `note` was removed server-side (migration 44). Notes
    // now live on each work segment and each off entry, never on the day.
    let hours: HourTotals
    let saved: Bool         // false = pre-filled default, not yet written

    var id: String { date }

    // Defensive decoding: coerce nulls to "" so the editor always has strings.
    private enum CodingKeys: String, CodingKey {
        case date, weekday, isWeekend, segments, off, regStart, regEnd, otStart, otEnd
        case offReason, offPortion, hours, saved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        weekday = (try? c.decode(String.self, forKey: .weekday)) ?? ""
        isWeekend = (try? c.decode(Bool.self, forKey: .isWeekend)) ?? false
        // nil when the key is absent (old server); [] or [items] on the new one.
        segments = (try? c.decodeIfPresent([Segment].self, forKey: .segments)) ?? nil
        off = (try? c.decodeIfPresent([DayOff].self, forKey: .off)) ?? nil
        regStart = (try? c.decodeIfPresent(String.self, forKey: .regStart)) ?? ""
        regEnd = (try? c.decodeIfPresent(String.self, forKey: .regEnd)) ?? ""
        otStart = (try? c.decodeIfPresent(String.self, forKey: .otStart)) ?? ""
        otEnd = (try? c.decodeIfPresent(String.self, forKey: .otEnd)) ?? ""
        offReason = (try? c.decodeIfPresent(String.self, forKey: .offReason)) ?? ""
        offPortion = (try? c.decodeIfPresent(String.self, forKey: .offPortion)) ?? ""
        hours = (try? c.decode(HourTotals.self, forKey: .hours))
            ?? HourTotals(reg: 0, ot: 0, off: 0, total: 0)
        saved = (try? c.decode(Bool.self, forKey: .saved)) ?? true
    }

    /// True when the server sent a `segments` array (new API) for this day.
    var supportsSegments: Bool { segments != nil }

    /// True when the server sent the per-portion `off` array for this day.
    var supportsOffArray: Bool { off != nil }

    /// The day's work periods (empty on the old API or a work-free day).
    var workPeriods: [Segment] { segments ?? [] }

    /// Unified time-off list for display and editing: the authoritative `off`
    /// array on the new API, else a single entry synthesized from the legacy
    /// flat pair. Empty means the day isn't off.
    var offList: [DayOff] {
        if let off = off { return off }
        if !offReason.isEmpty {
            return [DayOff(portion: offPortion.isEmpty ? "full" : offPortion,
                           reason: offReason, start: nil, end: nil, note: nil)]
        }
        return []
    }

    var isTimeOff: Bool { !offList.isEmpty }

    var hasWorkTime: Bool {
        if !workPeriods.isEmpty { return true }
        return !(regStart.isEmpty && regEnd.isEmpty && otStart.isEmpty && otEnd.isEmpty)
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
    // Legacy in-timesheet catalogs. The new server exposes these via
    // GET /day-types instead, so tolerate their absence (default []).
    let dayTypes: [DayType]
    let offPortions: [OffPortionOption]
    var days: [Day]

    struct Defaults: Codable, Equatable {
        let regStart: String
        let regEnd: String
    }

    private enum CodingKeys: String, CodingKey {
        case period, status, editable, defaults, fullDayHours
        case submitBlockedUntil, totals, dayTypes, offPortions, days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decode(PeriodInfo.self, forKey: .period)
        status = try c.decode(String.self, forKey: .status)
        editable = try c.decode(Bool.self, forKey: .editable)
        defaults = try c.decode(Defaults.self, forKey: .defaults)
        fullDayHours = try c.decode(Double.self, forKey: .fullDayHours)
        submitBlockedUntil = try c.decodeIfPresent(String.self, forKey: .submitBlockedUntil)
        totals = try c.decode(HourTotals.self, forKey: .totals)
        dayTypes = (try? c.decode([DayType].self, forKey: .dayTypes)) ?? []
        offPortions = (try? c.decode([OffPortionOption].self, forKey: .offPortions)) ?? []
        days = try c.decode([Day].self, forKey: .days)
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
// All fields optional except `date`. Optional Swift properties encode via
// `encodeIfPresent`, so nil ones are omitted from the JSON.
//   - `segments` is AUTHORITATIVE for worked time when present (replaces, not
//     merges); the flat reg/ot fields are the old-server fallback.
//   - `off` is AUTHORITATIVE for time off when present (the server ignores the
//     flat offReason/offPortion then). Sending the flat pair on a day that
//     already has two portions is refused, so we send `off` and omit the pair
//     whenever the server supports the array.
struct DayUpdate: Codable {
    let date: String
    var segments: [Segment]?     // authoritative when present; replaces, not merges
    var off: [DayOff]?           // authoritative when present; [] clears time off
    var regStart: String?        // flat fallback only (omitted when segments sent)
    var regEnd: String?
    var otStart: String?
    var otEnd: String?
    var offReason: String?       // legacy flat fallback (omitted when `off` sent)
    var offPortion: String?
    // No day-level note: notes live on each segment and each off entry. (A
    // day-level note in the body is silently ignored by the server, so we don't
    // send one.)
}

// Standard error envelope on 409/422: { "error": "…" }
struct APIErrorBody: Codable {
    let error: String?
    let message: String?
    var text: String? { error ?? message }
}
