import SwiftUI

/// Editor for a single day. Sends `PUT /timesheet/{id}/day` and adopts the
/// refreshed card the server returns.
///
/// A day is a list of typed blocks: work (`segments`, reg/ot) and absences
/// (`off`, each a reason + a portion). The two are independent — a day can be
/// off AND carry work outside the off hours (a call-out on a sick day).
///
///  - New API (`segments`/`off` present): a list of work periods plus a list of
///    off blocks. Each off block is Full / AM / PM (policy hours, no times) or
///    Timed (clock hours, with start→end).
///  - Old API (both absent): the original single Regular/Overtime pair with one
///    time-off reason + Full/AM/PM amount, where a full day clears worked time.
struct DayEditView: View {
    @EnvironmentObject private var state: AppState
    let day: Day
    let onDismiss: () -> Void

    // Shared state
    @State private var note = ""
    @State private var saving = false
    @State private var loaded = false     // true once the initial load has settled

    // Segments mode (work)
    @State private var periods: [EditablePeriod] = []

    // Flat fallback mode (work)
    @State private var regStart = ""
    @State private var regEnd = ""
    @State private var otStart = ""
    @State private var otEnd = ""

    // Time off — new API: a list of blocks.
    @State private var offBlocks: [EditableOff] = []
    // Time off — old API: a single reason + amount.
    @State private var offReason = ""     // "" = none, else a DayType.slug
    @State private var offPortion = "full"

    // Snapshot of the day's full work span, taken the first time a half-day off
    // splits it, so flipping AM↔PM re-splits the whole day, not the trimmed half.
    @State private var preSplitWork: MinuteRange?

    private var usesSegments: Bool { day.supportsSegments }
    private var usesOffArray: Bool { day.supportsOffArray }

    // Reason/label sources. Prefer the /day-types catalog; fall back to the
    // timesheet's list. Offer only active reasons; label lookups cover retired
    // ones so an old sheet still renders.
    private var offTypesForEntry: [OffType] {
        if let cat = state.dayTypesCatalog { return cat.off.filter { $0.active } }
        return (state.timesheet?.dayTypes ?? []).map { OffType(slug: $0.slug, label: $0.label, active: true) }
    }
    private func reasonLabel(_ slug: String) -> String {
        if let t = state.dayTypesCatalog?.off.first(where: { $0.slug == slug }) { return t.label }
        if let d = state.timesheet?.dayTypes.first(where: { $0.slug == slug }) { return d.label }
        return slug
    }
    private var serverPortions: [OffPortionOption] { state.timesheet?.offPortions ?? [] }

    /// Full / AM / PM / Timed with labels (server wording where available).
    private var portionOptions: [OffPortionOption] {
        var opts = ["full", "am", "pm"].map { v in
            OffPortionOption(value: v, label: serverPortions.first { $0.value == v }?.label ?? defaultPortionLabel(v))
        }
        opts.append(OffPortionOption(value: "timed", label: "Timed"))
        return opts
    }
    private func defaultPortionLabel(_ v: String) -> String {
        switch v {
        case "full": return "Full day"
        case "am": return "Morning"
        case "pm": return "Afternoon"
        case "timed": return "Timed"
        default: return v.uppercased()
        }
    }

    // Legacy (old-server) helpers.
    private var isFullDayOffLegacy: Bool { !offReason.isEmpty && offPortion == "full" }
    private var isHalfOffLegacy: Bool { !offReason.isEmpty && (offPortion == "am" || offPortion == "pm") }
    /// Dim/disable the work section only on the old server's full-day off, where
    /// work and off can't coexist. The new API never dims — work is independent.
    private var dimWork: Bool { !usesOffArray && isFullDayOffLegacy }

    /// "am"/"pm" when the day has exactly one half-day off block — the case that
    /// drives the worked-half auto-update; "" otherwise (so reason edits, full
    /// days, timed off, and multi-block days don't retrigger a split).
    private var halfPortionKey: String {
        guard offBlocks.count == 1, let b = offBlocks.first,
              b.portion == "am" || b.portion == "pm" else { return "" }
        return b.portion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Group {
                if usesSegments { workPeriodsSection } else { flatWorkSection }
            }
            .opacity(dimWork ? 0.5 : 1)

            Divider()
            if usesOffArray { offBlocksSection } else { legacyOffSection }
            noteField

            if let error = state.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    save()
                } label: {
                    if saving { ProgressView().controlSize(.small) }
                    else { Text("Save") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving || !isValid)
            }
        }
        .padding(12)
        .onAppear {
            loadFromDay()
            // Let the initial load settle before honoring onChange auto-fills,
            // so opening an existing day doesn't overwrite its saved times.
            DispatchQueue.main.async { loaded = true }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button(action: onDismiss) { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(DateParsing.displayDate(day.date))
                .font(.headline)
            if day.isWeekend {
                Text("weekend").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// New API: a list of work periods with add/remove.
    private var workPeriodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Work periods").font(.caption).foregroundStyle(.secondary)

            ForEach($periods) { $period in
                PeriodRow(period: $period) { remove(period.id) }
            }

            if !dimWork {
                Button {
                    periods.append(EditablePeriod(kind: .reg, start: "", end: "", note: ""))
                } label: {
                    Label(periods.isEmpty ? "Add work period" : "Add another work period",
                          systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }

            if let overlap = overlapMessage {
                Text(overlap)
                    .font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(dimWork
                 ? "This day is fully off — worked time is cleared automatically."
                 : "Each period is paid on its own — gaps between them aren't.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(dimWork)
    }

    /// Old API fallback: one Regular + one Overtime pair.
    private var flatWorkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimeRange(title: "Regular", start: $regStart, end: $regEnd)
                .disabled(dimWork)
            TimeRange(title: "Overtime", start: $otStart, end: $otEnd)
                .disabled(dimWork)
            Text(dimWork
                 ? "This day is fully off — worked times are cleared automatically."
                 : "Enter times like 7:30 AM. Leave blank to clear.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// New API: time off is a list of blocks (reason + Full/AM/PM/Timed).
    private var offBlocksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time off").font(.caption).foregroundStyle(.secondary)

            ForEach($offBlocks) { $block in
                OffRow(block: $block,
                       reasons: offTypesForEntry,
                       reasonLabel: reasonLabel,
                       portions: portionOptions) { removeOff(block.id) }
            }

            Button {
                offBlocks.append(EditableOff(
                    reason: offTypesForEntry.first?.slug ?? "", portion: "full", start: "", end: ""))
            } label: {
                Label(offBlocks.isEmpty ? "Add time off" : "Add another time off", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .font(.callout)

            if let msg = offValidationMessage {
                Text(msg).font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !offBlocks.isEmpty {
                Text("Work outside these hours is fine; work inside them is refused by the server.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Picking a single AM/PM off updates the worked half: it trims an
        // existing single work period to the other half, or fills an empty day
        // from your standard hours. Fires only when the half selection changes.
        .onChange(of: halfPortionKey) { key in
            guard loaded else { return }
            if key.isEmpty { preSplitWork = nil; return }
            if preSplitWork == nil { preSplitWork = currentSingleWorkRange() ?? workdayRange() }
            applyHalfSplit(key)
        }
    }

    /// Old API: a single reason + Full/AM/PM amount, with the worked half filled
    /// for an am/pm choice and worked time cleared for a full day.
    private var legacyOffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Time off", selection: $offReason) {
                Text("None").tag("")
                ForEach(offTypesForEntry) { type in
                    Text(type.label).tag(type.slug)
                }
            }
            let portions = serverPortions.filter { $0.value != "timed" }
            if !offReason.isEmpty && !portions.isEmpty {
                Picker("Amount", selection: $offPortion) {
                    ForEach(portions) { p in Text(p.label).tag(p.value) }
                }
                .pickerStyle(.segmented)
                if offPortion == "am" || offPortion == "pm" {
                    Text("Worked half filled in from your standard hours — edit if needed.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: offReason) { _ in
            guard loaded else { return }
            legacySyncWork()
        }
        .onChange(of: offPortion) { _ in
            guard loaded else { return }
            legacySyncWork()
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Day note").font(.caption).foregroundStyle(.secondary)
            TextField("Optional", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        if usesOffArray { return workIsValid && offValidationMessage == nil }
        if isFullDayOffLegacy { return true }   // legacy: work irrelevant
        return workIsValid
    }

    private var workIsValid: Bool {
        if usesSegments {
            for p in periods {
                guard TimeString.isValid(p.start), TimeString.isValid(p.end) else { return false }
                if p.start.isEmpty != p.end.isEmpty { return false }  // both or neither
            }
            return overlapMessage == nil
        } else {
            let times = [regStart, regEnd, otStart, otEnd].allSatisfy(TimeString.isValid)
            let regPaired = regStart.isEmpty == regEnd.isEmpty
            let otPaired = otStart.isEmpty == otEnd.isEmpty
            return times && regPaired && otPaired
        }
    }

    /// Client-side mirror of the server's off rules, so the user is guided
    /// before a 422. (Work-vs-off overlap is left to the server — it needs the
    /// resolved hours.)
    private var offValidationMessage: String? {
        guard !offBlocks.isEmpty else { return nil }
        if offBlocks.contains(where: { $0.reason.isEmpty }) {
            return "Choose a reason for each time-off row."
        }
        let fulls = offBlocks.filter { $0.portion == "full" }.count
        if fulls > 1 || (fulls == 1 && offBlocks.count > 1) {
            return "A full day off is the whole day — remove the other time-off rows."
        }
        if offBlocks.filter({ $0.portion == "am" }).count > 1 { return "Only one morning (AM) off per day." }
        if offBlocks.filter({ $0.portion == "pm" }).count > 1 { return "Only one afternoon (PM) off per day." }
        let hasTimed = offBlocks.contains { $0.portion == "timed" }
        let hasPolicy = offBlocks.contains { ["full", "am", "pm"].contains($0.portion) }
        if hasTimed && hasPolicy {
            return "Use either half/full-day off or specific hours on a day — not both."
        }
        for b in offBlocks where b.portion == "timed" {
            guard TimeString.isValid(b.start), TimeString.isValid(b.end),
                  !b.start.isEmpty, !b.end.isEmpty else {
                return "Enter a start and end time for the timed time off."
            }
            if let s = TimeString.parse24(b.start).flatMap(TimeString.minutes),
               let e = TimeString.parse24(b.end).flatMap(TimeString.minutes), e <= s {
                return "Timed time off must end after it starts."
            }
        }
        return nil
    }

    /// Non-nil when two work periods of the SAME kind overlap. Matches the
    /// server rule so the user is stopped before a 422. Touching ends allowed.
    private var overlapMessage: String? {
        for kind in [Segment.Kind.reg, .ot] {
            let ranges = periods
                .filter { $0.kind == kind }
                .compactMap { p -> (start: Int, end: Int, label: String)? in
                    guard let s = TimeString.parse24(p.start).flatMap(TimeString.minutes),
                          let e = TimeString.parse24(p.end).flatMap(TimeString.minutes),
                          e > s else { return nil }
                    let label = "\(TimeString.display12(TimeString.fromMinutes(s)))–\(TimeString.display12(TimeString.fromMinutes(e)))"
                    return (s, e, label)
                }
                .sorted { $0.start < $1.start }

            var maxEnd = -1
            var maxLabel = ""
            for r in ranges {
                if r.start < maxEnd {
                    return "These \(kind == .ot ? "overtime" : "worked") periods overlap: \(maxLabel) and \(r.label)."
                }
                if r.end > maxEnd { maxEnd = r.end; maxLabel = r.label }
            }
        }
        return nil
    }

    // MARK: - Mutation

    private func remove(_ id: EditablePeriod.ID) {
        periods.removeAll { $0.id == id }
    }
    private func removeOff(_ id: EditableOff.ID) {
        offBlocks.removeAll { $0.id == id }
    }

    private func loadFromDay() {
        note = day.note

        if usesSegments {
            periods = day.workPeriods.map {
                EditablePeriod(kind: $0.kind,
                               start: TimeString.display12($0.start),
                               end: TimeString.display12($0.end),
                               note: $0.note)
            }
        } else {
            regStart = TimeString.display12(day.regStart)
            regEnd = TimeString.display12(day.regEnd)
            otStart = TimeString.display12(day.otStart)
            otEnd = TimeString.display12(day.otEnd)
        }

        if usesOffArray {
            offBlocks = day.offList.map { e in
                EditableOff(reason: e.reason,
                            portion: e.portion.isEmpty ? "full" : e.portion,
                            start: e.start.map(TimeString.display12) ?? "",
                            end: e.end.map(TimeString.display12) ?? "")
            }
        } else if let first = day.offList.first {
            offReason = first.reason
            offPortion = first.portion.isEmpty ? "full" : first.portion
        } else {
            offReason = ""
            offPortion = serverPortions.first?.value ?? "full"
        }
        state.errorMessage = nil
    }

    /// The standard workday (24-hour "HH:MM") used to split a half day.
    private var workday: (start: String, end: String)? {
        if let d = state.timesheet?.defaults, !d.regStart.isEmpty, !d.regEnd.isEmpty {
            return (d.regStart, d.regEnd)
        }
        if !day.regStart.isEmpty, !day.regEnd.isEmpty {
            return (day.regStart, day.regEnd)
        }
        return nil
    }

    /// Fill the worked half for an AM/PM off. "am" = morning off (work the
    /// afternoon); "pm" = afternoon off (work the morning).
    private func applyHalfDay(_ portion: String) {
        guard portion == "am" || portion == "pm",
              let wd = workday,
              let startMin = TimeString.minutes(wd.start),
              let endMin = TimeString.minutes(wd.end), endMin > startMin else { return }
        let midMin = (startMin + endMin) / 2
        let (hs, he) = portion == "am"
            ? (midMin, endMin)     // morning off → afternoon
            : (startMin, midMin)   // afternoon off → morning
        let startDisp = TimeString.display12(TimeString.fromMinutes(hs))
        let endDisp = TimeString.display12(TimeString.fromMinutes(he))

        if usesSegments {
            let seg = EditablePeriod(kind: .reg, start: startDisp, end: endDisp, note: "")
            if periods.isEmpty {
                periods = [seg]
            } else if periods.count == 1 {
                periods[0].kind = .reg
                periods[0].start = startDisp
                periods[0].end = endDisp
            }
        } else {
            regStart = startDisp
            regEnd = endDisp
        }
    }

    /// The single existing work period's span (minutes), or nil unless there's
    /// exactly one — a multi-period day is left alone.
    private func currentSingleWorkRange() -> MinuteRange? {
        if usesSegments {
            let real = periods.filter { !$0.start.isEmpty || !$0.end.isEmpty }
            guard real.count == 1,
                  let s = TimeString.parse24(real[0].start).flatMap(TimeString.minutes),
                  let e = TimeString.parse24(real[0].end).flatMap(TimeString.minutes), e > s
            else { return nil }
            return MinuteRange(start: s, end: e)
        } else {
            guard let s = TimeString.parse24(regStart).flatMap(TimeString.minutes),
                  let e = TimeString.parse24(regEnd).flatMap(TimeString.minutes), e > s
            else { return nil }
            return MinuteRange(start: s, end: e)
        }
    }

    /// The standard workday span (minutes) from defaults or the day's reg times.
    private func workdayRange() -> MinuteRange? {
        guard let wd = workday,
              let s = TimeString.minutes(wd.start),
              let e = TimeString.minutes(wd.end), e > s else { return nil }
        return MinuteRange(start: s, end: e)
    }

    /// Set the worked half from the snapshot span for an AM/PM off: "am" =
    /// morning off → work the afternoon; "pm" = afternoon off → work the morning.
    private func applyHalfSplit(_ portion: String) {
        guard let src = preSplitWork else { return }
        let mid = (src.start + src.end) / 2
        let (hs, he) = portion == "am" ? (mid, src.end) : (src.start, mid)
        guard he > hs else { return }
        setSingleWorkPeriod(startMin: hs, endMin: he)
    }

    /// Overwrite the single work period (or create one) with the given span,
    /// leaving a multi-period day untouched.
    private func setSingleWorkPeriod(startMin: Int, endMin: Int) {
        let sDisp = TimeString.display12(TimeString.fromMinutes(startMin))
        let eDisp = TimeString.display12(TimeString.fromMinutes(endMin))
        if usesSegments {
            let realIdx = periods.indices.filter { !periods[$0].start.isEmpty || !periods[$0].end.isEmpty }
            if realIdx.count > 1 { return }   // multi-period → leave to the user
            if let i = realIdx.first {
                periods[i].start = sDisp
                periods[i].end = eDisp
            } else {
                periods.append(EditablePeriod(kind: .reg, start: sDisp, end: eDisp, note: ""))
            }
        } else {
            regStart = sDisp
            regEnd = eDisp
        }
    }

    /// Old API: clear work on a full day off, fill the worked half on am/pm.
    private func legacySyncWork() {
        if isFullDayOffLegacy {
            if usesSegments { periods = [] } else { regStart = ""; regEnd = ""; otStart = ""; otEnd = "" }
        } else if isHalfOffLegacy {
            applyHalfDay(offPortion)
        }
    }

    // MARK: - Save

    private func save() {
        guard !saving else { return }
        saving = true

        let dayNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        // Time off: authoritative `off` array on the new API; flat pair on the old.
        let offArray: [DayOff]?
        let flatReason: String?
        let flatPortion: String?
        if usesOffArray {
            offArray = offBlocks.map { b in
                let timed = b.portion == "timed"
                return DayOff(portion: b.portion, reason: b.reason,
                              start: timed ? (TimeString.parse24(b.start) ?? "") : nil,
                              end: timed ? (TimeString.parse24(b.end) ?? "") : nil)
            }
            flatReason = nil
            flatPortion = nil
        } else {
            offArray = nil
            flatReason = offReason
            flatPortion = offReason.isEmpty ? "" : offPortion
        }

        // Work is independent of off on the new API; only a legacy full-day off
        // clears it.
        let clearWork = !usesOffArray && isFullDayOffLegacy

        let update: DayUpdate
        if usesSegments {
            let segments = clearWork ? [] : periods.compactMap { $0.toSegment() }
            update = DayUpdate(
                date: day.date,
                segments: segments,
                off: offArray,
                regStart: nil, regEnd: nil, otStart: nil, otEnd: nil,
                offReason: flatReason, offPortion: flatPortion, note: dayNote
            )
        } else {
            update = DayUpdate(
                date: day.date,
                segments: nil,
                off: offArray,
                regStart: clearWork ? "" : (TimeString.parse24(regStart) ?? ""),
                regEnd: clearWork ? "" : (TimeString.parse24(regEnd) ?? ""),
                otStart: clearWork ? "" : (TimeString.parse24(otStart) ?? ""),
                otEnd: clearWork ? "" : (TimeString.parse24(otEnd) ?? ""),
                offReason: flatReason, offPortion: flatPortion, note: dayNote
            )
        }

        Task {
            let ok = await state.saveDay(update)
            saving = false
            if ok { onDismiss() }
        }
    }
}

/// Editor-side representation of a work period (12-hour display strings + a
/// stable id for the list). Converted to/from the wire `Segment` at the edges.
private struct EditablePeriod: Identifiable, Equatable {
    let id = UUID()
    var kind: Segment.Kind
    var start: String   // 12-hour display
    var end: String
    var note: String

    /// Convert to a wire segment, or nil when the period is blank (dropped).
    func toSegment() -> Segment? {
        let s = TimeString.parse24(start) ?? ""
        let e = TimeString.parse24(end) ?? ""
        if s.isEmpty && e.isEmpty { return nil }
        return Segment(kind: kind, start: s, end: e,
                       note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A start–end span in minutes since midnight.
private struct MinuteRange: Equatable { let start: Int; let end: Int }

/// Editor-side representation of one off block (12-hour display times for the
/// timed case). Converted to a wire `DayOff` at save.
private struct EditableOff: Identifiable, Equatable {
    let id = UUID()
    var reason: String    // DayType slug
    var portion: String   // full | am | pm | timed
    var start: String     // 12-hour display (timed only)
    var end: String
}

/// One editable work-period row: kind toggle, start→end, note, remove.
private struct PeriodRow: View {
    @Binding var period: EditablePeriod
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Picker("", selection: $period.kind) {
                    Text("Reg").tag(Segment.Kind.reg)
                    Text("OT").tag(Segment.Kind.ot)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 78)

                timeField($period.start, placeholder: "start")
                Text("→").foregroundStyle(.secondary)
                timeField($period.end, placeholder: "end")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this period")
            }
            TextField("Note (optional)", text: $period.note)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func timeField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
            .frame(width: 78)
            .foregroundStyle(TimeString.isValid(binding.wrappedValue) ? Color.primary : Color.red)
            .onSubmit { binding.wrappedValue = TimeString.normalizedDisplay(binding.wrappedValue) }
    }
}

/// One editable off row: reason, a Full/AM/PM/Timed toggle, and — when Timed —
/// a start→end pair.
private struct OffRow: View {
    @Binding var block: EditableOff
    let reasons: [OffType]
    let reasonLabel: (String) -> String
    let portions: [OffPortionOption]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Picker("", selection: $block.reason) {
                    // Include a retired reason so an old sheet still renders it.
                    if !block.reason.isEmpty && !reasons.contains(where: { $0.slug == block.reason }) {
                        Text(reasonLabel(block.reason)).tag(block.reason)
                    }
                    ForEach(reasons) { Text($0.label).tag($0.slug) }
                }
                .labelsHidden()
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this time off")
            }
            Picker("", selection: $block.portion) {
                ForEach(portions) { p in Text(p.label).tag(p.value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if block.portion == "timed" {
                HStack(spacing: 8) {
                    timeField($block.start, placeholder: "start")
                    Text("→").foregroundStyle(.secondary)
                    timeField($block.end, placeholder: "end")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func timeField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .foregroundStyle(TimeString.isValid(binding.wrappedValue) ? Color.primary : Color.red)
            .onSubmit { binding.wrappedValue = TimeString.normalizedDisplay(binding.wrappedValue) }
    }
}

/// A labelled start/end pair of time fields (flat fallback mode).
private struct TimeRange: View {
    let title: String
    @Binding var start: String
    @Binding var end: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .frame(width: 66, alignment: .leading)
            field($start, placeholder: "start")
            Text("→").foregroundStyle(.secondary)
            field($end, placeholder: "end")
        }
    }

    private func field(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
            .frame(width: 96)
            .foregroundStyle(TimeString.isValid(binding.wrappedValue) ? Color.primary : Color.red)
            .onSubmit { binding.wrappedValue = TimeString.normalizedDisplay(binding.wrappedValue) }
    }
}
