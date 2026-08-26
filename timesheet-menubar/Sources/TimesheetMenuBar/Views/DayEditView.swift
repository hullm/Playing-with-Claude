import SwiftUI

/// Editor for a single day. Sends `PUT /timesheet/{id}/day` and adopts the
/// refreshed card the server returns.
///
/// New API (`segments`/`off` present): the day is ONE chronological list of
/// typed blocks. Each block is either work (Reg/OT, start→end, note) or an
/// absence (a reason + Full / AM / PM / Timed; Timed carries start→end). Work
/// and off coexist; a single half-day off retrims a lone work period.
///
/// Old API (both absent): the original single Regular/Overtime pair plus one
/// time-off reason + Full/AM/PM amount, where a full day clears worked time.
struct DayEditView: View {
    @EnvironmentObject private var state: AppState
    let day: Day
    let onDismiss: () -> Void

    // Shared
    @State private var note = ""
    @State private var saving = false
    @State private var loaded = false

    // New-API combined list
    @State private var blocks: [EditableBlock] = []
    // Snapshot of the day's full work span, taken the first time a half-day off
    // splits it, so flipping AM↔PM re-splits the whole day, not the trimmed half.
    @State private var preSplitWork: MinuteRange?

    // Old-API work
    @State private var periods: [EditablePeriod] = []
    @State private var regStart = ""
    @State private var regEnd = ""
    @State private var otStart = ""
    @State private var otEnd = ""
    // Old-API time off
    @State private var offReason = ""
    @State private var offPortion = "full"

    private var usesSegments: Bool { day.supportsSegments }
    private var usesOffArray: Bool { day.supportsOffArray }
    /// The new unified editor is used whenever the server speaks the `off`
    /// array (which implies segments); everything else is the legacy path.
    private var combined: Bool { usesOffArray }

    // Catalog sources: prefer /day-types; fall back to the timesheet's lists.
    private var offTypesForEntry: [OffType] {
        if let cat = state.dayTypesCatalog { return cat.off.filter { $0.active } }
        return (state.timesheet?.dayTypes ?? []).map { OffType(slug: $0.slug, label: $0.label, active: true) }
    }
    private var workTypeOptions: [WorkOption] {
        if let cat = state.dayTypesCatalog, !cat.work.isEmpty {
            return cat.work.map { WorkOption(tag: $0.kind == "ot" ? "work:ot" : "work:reg", label: $0.label) }
        }
        return [WorkOption(tag: "work:reg", label: "Worked"), WorkOption(tag: "work:ot", label: "Overtime")]
    }
    private var defaultWorkTag: String { workTypeOptions.first?.tag ?? "work:reg" }
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
        case "full": return "Full day"; case "am": return "Morning"
        case "pm": return "Afternoon"; case "timed": return "Timed"; default: return v.uppercased()
        }
    }

    // Legacy helpers
    private var isFullDayOffLegacy: Bool { !offReason.isEmpty && offPortion == "full" }
    private var isHalfOffLegacy: Bool { !offReason.isEmpty && (offPortion == "am" || offPortion == "pm") }
    private var dimWork: Bool { !combined && isFullDayOffLegacy }

    /// "am"/"pm" when the day has exactly one half-day off block — the case that
    /// drives the worked-half auto-update; "" otherwise.
    private var halfPortionKey: String {
        let offs = blocks.filter { !$0.isWork }
        guard offs.count == 1, let b = offs.first, b.portion == "am" || b.portion == "pm" else { return "" }
        return b.portion
    }
    /// Changes when a block's type or portion changes, or a block is added or
    /// removed — the moments a re-sort is wanted (not on every keystroke).
    private var typePortionSignature: String {
        blocks.map { "\($0.typeTag)|\($0.portion)" }.joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if combined {
                combinedSection
            } else {
                Group {
                    if usesSegments { workPeriodsSection } else { flatWorkSection }
                }
                .opacity(dimWork ? 0.5 : 1)
                Divider()
                legacyOffSection
            }

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

    /// New API: one chronological list of work and off blocks.
    private var combinedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocks").font(.caption).foregroundStyle(.secondary)

            ForEach($blocks) { $block in
                CombinedRow(block: $block,
                            workTypes: workTypeOptions,
                            offTypes: offTypesForEntry,
                            reasonLabel: reasonLabel,
                            portions: portionOptions,
                            onRemove: { removeBlock(block.id) },
                            onCommit: sortBlocks)
                Divider().opacity(0.4)
            }

            Button {
                addBlock()
            } label: {
                Label("Add block", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .font(.callout)

            if let msg = combinedValidationMessage {
                Text(msg).font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if blocks.contains(where: { !$0.isWork }) {
                Text("Work outside the off hours is fine; work inside them is refused by the server.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Re-sort on discrete changes (type/portion/add/remove); time typing
        // re-sorts on commit via the row's onCommit.
        .onChange(of: typePortionSignature) { _ in
            guard loaded else { return }
            sortBlocks()
        }
        // A single AM/PM off updates the worked half: trims a lone work period
        // to the other half, or fills an empty day from your standard hours.
        .onChange(of: halfPortionKey) { key in
            guard loaded else { return }
            if key.isEmpty { preSplitWork = nil; return }
            if preSplitWork == nil { preSplitWork = currentSingleWorkRange() ?? workdayRange() }
            applyHalfSplit(key)
        }
    }

    /// Legacy: a list of work periods with add/remove.
    private var workPeriodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Work periods").font(.caption).foregroundStyle(.secondary)
            ForEach($periods) { $period in
                PeriodRow(period: $period) { periods.removeAll { $0.id == period.id } }
            }
            if !dimWork {
                Button {
                    periods.append(EditablePeriod(kind: .reg, start: "", end: "", note: ""))
                } label: {
                    Label(periods.isEmpty ? "Add work period" : "Add another work period", systemImage: "plus")
                }
                .buttonStyle(.borderless).font(.callout)
            }
            if let overlap = legacyOverlapMessage {
                Text(overlap).font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(dimWork ? "This day is fully off — worked time is cleared automatically."
                         : "Each period is paid on its own — gaps between them aren't.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(dimWork)
    }

    /// Legacy: one Regular + one Overtime pair.
    private var flatWorkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimeRange(title: "Regular", start: $regStart, end: $regEnd).disabled(dimWork)
            TimeRange(title: "Overtime", start: $otStart, end: $otEnd).disabled(dimWork)
            Text(dimWork ? "This day is fully off — worked times are cleared automatically."
                         : "Enter times like 7:30 AM. Leave blank to clear.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Legacy: a single reason + Full/AM/PM amount.
    private var legacyOffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Time off", selection: $offReason) {
                Text("None").tag("")
                ForEach(offTypesForEntry) { type in Text(type.label).tag(type.slug) }
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
        .onChange(of: offReason) { _ in if loaded { legacySyncWork() } }
        .onChange(of: offPortion) { _ in if loaded { legacySyncWork() } }
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
        if combined { return combinedValidationMessage == nil }
        if isFullDayOffLegacy { return true }
        return legacyWorkIsValid
    }

    /// Combined-mode validation, mirroring the server so the user is guided
    /// before a 422. Work-vs-off overlap is left to the server (it resolves the
    /// hours); same-kind work overlap is caught here.
    private var combinedValidationMessage: String? {
        let workRanges = blocks.compactMap { b -> (kind: Segment.Kind, start: Int, end: Int)? in
            guard b.isWork, let s = mins(b.start), let e = mins(b.end), e > s else { return nil }
            return (b.workKind, s, e)
        }
        if let m = overlapMessage(for: workRanges) { return m }

        for b in blocks where b.isWork {
            if b.start.isEmpty && b.end.isEmpty { continue }  // blank row → dropped
            guard TimeString.isValid(b.start), TimeString.isValid(b.end),
                  !b.start.isEmpty, !b.end.isEmpty else { return "Each work period needs a valid start and end." }
        }

        let offs = blocks.filter { !$0.isWork }
        if offs.contains(where: { $0.reason.isEmpty }) { return "Choose a reason for each time-off block." }
        let fulls = offs.filter { $0.portion == "full" }.count
        if fulls > 1 || (fulls >= 1 && offs.count > 1) {
            return "A full day off is the whole day — remove the other time-off blocks."
        }
        if offs.filter({ $0.portion == "am" }).count > 1 { return "Only one morning (AM) off per day." }
        if offs.filter({ $0.portion == "pm" }).count > 1 { return "Only one afternoon (PM) off per day." }
        let hasTimed = offs.contains { $0.portion == "timed" }
        let hasPolicy = offs.contains { ["full", "am", "pm"].contains($0.portion) }
        if hasTimed && hasPolicy { return "Use either half/full-day off or specific hours on a day — not both." }
        for b in offs where b.portion == "timed" {
            guard TimeString.isValid(b.start), TimeString.isValid(b.end),
                  !b.start.isEmpty, !b.end.isEmpty else { return "Enter a start and end time for the timed time off." }
            if let s = mins(b.start), let e = mins(b.end), e <= s { return "Timed time off must end after it starts." }
        }
        return nil
    }

    private var legacyWorkIsValid: Bool {
        if usesSegments {
            for p in periods {
                guard TimeString.isValid(p.start), TimeString.isValid(p.end) else { return false }
                if p.start.isEmpty != p.end.isEmpty { return false }
            }
            return legacyOverlapMessage == nil
        } else {
            let times = [regStart, regEnd, otStart, otEnd].allSatisfy(TimeString.isValid)
            return times && (regStart.isEmpty == regEnd.isEmpty) && (otStart.isEmpty == otEnd.isEmpty)
        }
    }

    private var legacyOverlapMessage: String? {
        let ranges = periods.compactMap { p -> (kind: Segment.Kind, start: Int, end: Int)? in
            guard let s = mins(p.start), let e = mins(p.end), e > s else { return nil }
            return (p.kind, s, e)
        }
        return overlapMessage(for: ranges)
    }

    /// Non-nil when two work ranges of the SAME kind overlap. Touching ends allowed.
    private func overlapMessage(for ranges: [(kind: Segment.Kind, start: Int, end: Int)]) -> String? {
        for kind in [Segment.Kind.reg, .ot] {
            let sorted = ranges.filter { $0.kind == kind }.sorted { $0.start < $1.start }
            var maxEnd = -1
            var maxLabel = ""
            for r in sorted {
                let label = "\(TimeString.display12(TimeString.fromMinutes(r.start)))–\(TimeString.display12(TimeString.fromMinutes(r.end)))"
                if r.start < maxEnd {
                    return "These \(kind == .ot ? "overtime" : "worked") periods overlap: \(maxLabel) and \(label)."
                }
                if r.end > maxEnd { maxEnd = r.end; maxLabel = label }
            }
        }
        return nil
    }

    // MARK: - Mutation

    /// Add a new block, defaulting to a work period — the type dropdown on the
    /// row switches it to any work kind or off reason.
    private func addBlock() {
        blocks.append(EditableBlock(typeTag: defaultWorkTag, start: "", end: "", note: "", portion: "full"))
        sortBlocks()
    }
    private func removeBlock(_ id: EditableBlock.ID) { blocks.removeAll { $0.id == id } }

    /// Stable sort by chronological position: full-day off first, then AM, then
    /// timed/work by start time, then PM. Blank times sort last.
    private func sortBlocks() {
        blocks = blocks.enumerated()
            .sorted { a, b in
                let ka = sortKey(a.element), kb = sortKey(b.element)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map { $0.element }
    }
    private func sortKey(_ b: EditableBlock) -> Int {
        if b.isWork { return mins(b.start) ?? 100_000 }
        switch b.portion {
        case "full": return -1
        case "am": return 0
        case "pm": return 12 * 60
        case "timed": return mins(b.start) ?? 100_000
        default: return 100_000
        }
    }
    private func mins(_ display: String) -> Int? { TimeString.parse24(display).flatMap(TimeString.minutes) }

    // MARK: - Load

    private func loadFromDay() {
        note = day.note

        if combined {
            var bs: [EditableBlock] = []
            for seg in day.workPeriods {
                bs.append(EditableBlock(typeTag: seg.kind == .ot ? "work:ot" : "work:reg",
                                        start: TimeString.display12(seg.start),
                                        end: TimeString.display12(seg.end),
                                        note: seg.note, portion: "full"))
            }
            for e in day.offList {
                bs.append(EditableBlock(typeTag: "off:\(e.reason)",
                                        start: e.start.map(TimeString.display12) ?? "",
                                        end: e.end.map(TimeString.display12) ?? "",
                                        note: "", portion: e.portion.isEmpty ? "full" : e.portion))
            }
            blocks = bs
            sortBlocks()
        } else {
            if usesSegments {
                periods = day.workPeriods.map {
                    EditablePeriod(kind: $0.kind, start: TimeString.display12($0.start),
                                   end: TimeString.display12($0.end), note: $0.note)
                }
            } else {
                regStart = TimeString.display12(day.regStart)
                regEnd = TimeString.display12(day.regEnd)
                otStart = TimeString.display12(day.otStart)
                otEnd = TimeString.display12(day.otEnd)
            }
            if let first = day.offList.first {
                offReason = first.reason
                offPortion = first.portion.isEmpty ? "full" : first.portion
            } else {
                offReason = ""
                offPortion = serverPortions.first?.value ?? "full"
            }
        }
        state.errorMessage = nil
    }

    // MARK: - Worked-half auto-fill

    private var workday: (start: String, end: String)? {
        if let d = state.timesheet?.defaults, !d.regStart.isEmpty, !d.regEnd.isEmpty {
            return (d.regStart, d.regEnd)
        }
        if !day.regStart.isEmpty, !day.regEnd.isEmpty { return (day.regStart, day.regEnd) }
        return nil
    }

    /// Combined-mode: indices of non-blank work blocks.
    private func realWorkIndices() -> [Int] {
        blocks.indices.filter { blocks[$0].isWork && !(blocks[$0].start.isEmpty && blocks[$0].end.isEmpty) }
    }
    private func currentSingleWorkRange() -> MinuteRange? {
        let idx = realWorkIndices()
        guard idx.count == 1, let s = mins(blocks[idx[0]].start), let e = mins(blocks[idx[0]].end), e > s
        else { return nil }
        return MinuteRange(start: s, end: e)
    }
    private func workdayRange() -> MinuteRange? {
        guard let wd = workday, let s = TimeString.minutes(wd.start), let e = TimeString.minutes(wd.end), e > s
        else { return nil }
        return MinuteRange(start: s, end: e)
    }
    private func applyHalfSplit(_ portion: String) {
        guard let src = preSplitWork else { return }
        let mid = (src.start + src.end) / 2
        let (hs, he) = portion == "am" ? (mid, src.end) : (src.start, mid)
        guard he > hs else { return }
        let sDisp = TimeString.display12(TimeString.fromMinutes(hs))
        let eDisp = TimeString.display12(TimeString.fromMinutes(he))
        let idx = realWorkIndices()
        if idx.count > 1 { return }   // multi-period → leave to the user
        if let i = idx.first {
            blocks[i].start = sDisp
            blocks[i].end = eDisp
        } else {
            blocks.append(EditableBlock(typeTag: defaultWorkTag, start: sDisp, end: eDisp, note: "", portion: "full"))
        }
        sortBlocks()
    }

    /// Legacy: fill the worked half for an AM/PM off from the standard workday.
    private func applyHalfDay(_ portion: String) {
        guard portion == "am" || portion == "pm",
              let wd = workday,
              let startMin = TimeString.minutes(wd.start),
              let endMin = TimeString.minutes(wd.end), endMin > startMin else { return }
        let midMin = (startMin + endMin) / 2
        let (hs, he) = portion == "am" ? (midMin, endMin) : (startMin, midMin)
        let sDisp = TimeString.display12(TimeString.fromMinutes(hs))
        let eDisp = TimeString.display12(TimeString.fromMinutes(he))
        if usesSegments {
            if periods.isEmpty {
                periods = [EditablePeriod(kind: .reg, start: sDisp, end: eDisp, note: "")]
            } else if periods.count == 1 {
                periods[0].kind = .reg; periods[0].start = sDisp; periods[0].end = eDisp
            }
        } else {
            regStart = sDisp; regEnd = eDisp
        }
    }
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

        let update: DayUpdate
        if combined {
            let segments = blocks.compactMap { b -> Segment? in
                guard b.isWork else { return nil }
                let s = TimeString.parse24(b.start) ?? ""
                let e = TimeString.parse24(b.end) ?? ""
                if s.isEmpty && e.isEmpty { return nil }
                return Segment(kind: b.workKind, start: s, end: e,
                               note: b.note.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let off = blocks.compactMap { b -> DayOff? in
                guard !b.isWork else { return nil }
                let timed = b.portion == "timed"
                return DayOff(portion: b.portion, reason: b.reason,
                              start: timed ? (TimeString.parse24(b.start) ?? "") : nil,
                              end: timed ? (TimeString.parse24(b.end) ?? "") : nil)
            }
            update = DayUpdate(date: day.date, segments: segments, off: off,
                               regStart: nil, regEnd: nil, otStart: nil, otEnd: nil,
                               offReason: nil, offPortion: nil, note: dayNote)
        } else {
            let clearWork = isFullDayOffLegacy
            let flatReason = offReason
            let flatPortion = offReason.isEmpty ? "" : offPortion
            if usesSegments {
                let segments = clearWork ? [] : periods.compactMap { $0.toSegment() }
                update = DayUpdate(date: day.date, segments: segments, off: nil,
                                   regStart: nil, regEnd: nil, otStart: nil, otEnd: nil,
                                   offReason: flatReason, offPortion: flatPortion, note: dayNote)
            } else {
                update = DayUpdate(date: day.date, segments: nil, off: nil,
                                   regStart: clearWork ? "" : (TimeString.parse24(regStart) ?? ""),
                                   regEnd: clearWork ? "" : (TimeString.parse24(regEnd) ?? ""),
                                   otStart: clearWork ? "" : (TimeString.parse24(otStart) ?? ""),
                                   otEnd: clearWork ? "" : (TimeString.parse24(otEnd) ?? ""),
                                   offReason: flatReason, offPortion: flatPortion, note: dayNote)
            }
        }

        Task {
            let ok = await state.saveDay(update)
            saving = false
            if ok { onDismiss() }
        }
    }
}

// MARK: - Editor-side models

/// A work period for the legacy segments list.
private struct EditablePeriod: Identifiable, Equatable {
    let id = UUID()
    var kind: Segment.Kind
    var start: String
    var end: String
    var note: String

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

/// A work-type choice for the block type picker.
private struct WorkOption: Identifiable, Equatable {
    let tag: String     // "work:reg" | "work:ot"
    let label: String
    var id: String { tag }
}

/// One row in the combined list — a work period or an off block. `typeTag` is
/// "work:reg" | "work:ot" | "off:<slug>".
private struct EditableBlock: Identifiable, Equatable {
    let id = UUID()
    var typeTag: String
    var start: String     // 12-hour display (work, or timed off)
    var end: String
    var note: String      // work only
    var portion: String   // off only: full | am | pm | timed

    var isWork: Bool { typeTag.hasPrefix("work:") }
    var workKind: Segment.Kind { typeTag == "work:ot" ? .ot : .reg }
    var reason: String { isWork ? "" : String(typeTag.dropFirst("off:".count)) }
}

// MARK: - Rows

/// One row of the combined list: a type picker, then either work times + note
/// or an off portion (+ times when Timed).
private struct CombinedRow: View {
    @Binding var block: EditableBlock
    let workTypes: [WorkOption]
    let offTypes: [OffType]
    let reasonLabel: (String) -> String
    let portions: [OffPortionOption]
    let onRemove: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Picker("", selection: $block.typeTag) {
                    Section("Work") {
                        ForEach(workTypes) { Text($0.label).tag($0.tag) }
                    }
                    Section("Time off") {
                        // Include a retired reason if the current one isn't offered,
                        // so an old sheet still renders and round-trips.
                        if !block.isWork && !offTypes.contains(where: { "off:\($0.slug)" == block.typeTag }) {
                            Text(reasonLabel(block.reason)).tag(block.typeTag)
                        }
                        ForEach(offTypes) { Text($0.label).tag("off:\($0.slug)") }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 160, alignment: .leading)

                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this block")
            }

            if block.isWork {
                HStack(spacing: 8) {
                    timeField($block.start, placeholder: "start")
                    Text("→").foregroundStyle(.secondary)
                    timeField($block.end, placeholder: "end")
                }
                TextField("Note (optional)", text: $block.note)
                    .textFieldStyle(.roundedBorder).font(.caption)
            } else {
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
        }
        .padding(.vertical, 4)
    }

    private func timeField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .foregroundStyle(TimeString.isValid(binding.wrappedValue) ? Color.primary : Color.red)
            .onSubmit {
                binding.wrappedValue = TimeString.normalizedDisplay(binding.wrappedValue)
                onCommit()
            }
    }
}

/// One editable work-period row (legacy segments mode).
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
                .pickerStyle(.segmented).labelsHidden().frame(width: 78)

                timeField($period.start, placeholder: "start")
                Text("→").foregroundStyle(.secondary)
                timeField($period.end, placeholder: "end")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove this period")
            }
            TextField("Note (optional)", text: $period.note)
                .textFieldStyle(.roundedBorder).font(.caption)
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

/// A labelled start/end pair (legacy flat mode).
private struct TimeRange: View {
    let title: String
    @Binding var start: String
    @Binding var end: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).frame(width: 66, alignment: .leading)
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
