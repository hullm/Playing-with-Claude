import SwiftUI

/// Editor for a single day. Sends `PUT /timesheet/{id}/day` and adopts the
/// refreshed card the server returns.
///
/// Two modes, chosen by whether the server sent a `segments` array:
///  - Segments mode (new API): a day is a LIST of work periods. Hours are the
///    sum of the periods, never the span. You can add/edit/remove periods and
///    give each its own note.
///  - Flat fallback (old API, `segments` absent): the original single Regular +
///    Overtime pair, with the add-a-period affordance hidden.
///
/// Time off is shared by both: a full-day off clears worked time, and a half-day
/// off (am/pm) records the worked half.
struct DayEditView: View {
    @EnvironmentObject private var state: AppState
    let day: Day
    let onDismiss: () -> Void

    // Shared state
    @State private var note = ""
    @State private var offReason = ""     // "" = none, else a DayType.slug
    @State private var offPortion = "full"
    @State private var saving = false
    @State private var loaded = false     // true once the initial load has settled

    // Segments mode
    @State private var periods: [EditablePeriod] = []

    // Flat fallback mode
    @State private var regStart = ""
    @State private var regEnd = ""
    @State private var otStart = ""
    @State private var otEnd = ""

    private var usesSegments: Bool { day.supportsSegments }
    private var dayTypes: [DayType] { state.timesheet?.dayTypes ?? [] }
    private var offPortions: [OffPortionOption] { state.timesheet?.offPortions ?? [] }
    private var isFullDayOff: Bool { !offReason.isEmpty && offPortion == "full" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Group {
                if usesSegments { workPeriodsSection } else { flatWorkSection }
            }
            .opacity(isFullDayOff ? 0.5 : 1)

            Divider()
            timeOffSection
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
            // so opening an existing half-day doesn't overwrite its saved times.
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

            if !isFullDayOff {
                Button {
                    // "another" only once there's a first period (requirement 3).
                    periods.append(EditablePeriod(kind: .reg, start: "", end: "", note: ""))
                } label: {
                    Label(periods.isEmpty ? "Add work period" : "Add another work period",
                          systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }

            Text(isFullDayOff
                 ? "A full-day off clears worked time automatically."
                 : "Each period is paid on its own — gaps between them aren't.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(isFullDayOff)
    }

    /// Old API fallback: one Regular + one Overtime pair.
    private var flatWorkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimeRange(title: "Regular", start: $regStart, end: $regEnd)
                .disabled(isFullDayOff)
            TimeRange(title: "Overtime", start: $otStart, end: $otEnd)
                .disabled(isFullDayOff)
            Text(isFullDayOff
                 ? "A full-day off clears worked times automatically."
                 : "Enter times like 7:30 AM. Leave blank to clear.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var timeOffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Time off", selection: $offReason) {
                Text("None").tag("")
                ForEach(dayTypes) { type in
                    Text(type.label).tag(type.slug)
                }
            }
            if !offReason.isEmpty && !offPortions.isEmpty {
                Picker("Amount", selection: $offPortion) {
                    ForEach(offPortions) { p in Text(p.label).tag(p.value) }
                }
                .pickerStyle(.segmented)
                if offPortion == "am" || offPortion == "pm" {
                    Text("Worked half filled in from your standard hours — edit if needed.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        // Auto-fill the worked half when a half-day off is chosen (only after
        // load, so an existing half-day's saved times aren't clobbered).
        .onChange(of: offReason) { reason in
            if loaded, !reason.isEmpty { applyHalfDay(offPortion) }
        }
        .onChange(of: offPortion) { portion in
            if loaded, !offReason.isEmpty { applyHalfDay(portion) }
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

    // MARK: - Logic

    private var isValid: Bool {
        if usesSegments {
            if isFullDayOff { return true }
            for p in periods {
                guard TimeString.isValid(p.start), TimeString.isValid(p.end) else { return false }
                if p.start.isEmpty != p.end.isEmpty { return false }  // both or neither
            }
            return true
        } else {
            let times = [regStart, regEnd, otStart, otEnd].allSatisfy(TimeString.isValid)
            let regPaired = regStart.isEmpty == regEnd.isEmpty
            let otPaired = otStart.isEmpty == otEnd.isEmpty
            return times && regPaired && otPaired
        }
    }

    private func remove(_ id: EditablePeriod.ID) {
        periods.removeAll { $0.id == id }
    }

    private func loadFromDay() {
        note = day.note
        offReason = day.offReason
        offPortion = day.offPortion.isEmpty ? (offPortions.first?.value ?? "full") : day.offPortion
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
        state.errorMessage = nil
    }

    /// The standard workday (24-hour "HH:MM") used to split a half day: prefer
    /// the period's defaults, else the day's own regular times.
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
    /// afternoon); "pm" = afternoon off (work the morning). In segments mode this
    /// sets a single reg period when there's room; in flat mode it fills reg
    /// start/end. Full day and unknown portions are handled by save (clears).
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
            // Several periods already → leave them to the user.
        } else {
            regStart = startDisp
            regEnd = endDisp
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true

        let dayNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentPortion = offReason.isEmpty ? "" : offPortion
        let fullDayOff = !offReason.isEmpty && offPortion == "full"

        let update: DayUpdate
        if usesSegments {
            // Send the whole list; it replaces the day. A full-day off clears it.
            let segments = fullDayOff ? [] : periods.compactMap { $0.toSegment() }
            update = DayUpdate(
                date: day.date,
                segments: segments,
                regStart: nil, regEnd: nil, otStart: nil, otEnd: nil,
                offReason: offReason, offPortion: sentPortion, note: dayNote
            )
        } else {
            update = DayUpdate(
                date: day.date,
                segments: nil,
                regStart: fullDayOff ? "" : (TimeString.parse24(regStart) ?? ""),
                regEnd: fullDayOff ? "" : (TimeString.parse24(regEnd) ?? ""),
                otStart: fullDayOff ? "" : (TimeString.parse24(otStart) ?? ""),
                otEnd: fullDayOff ? "" : (TimeString.parse24(otEnd) ?? ""),
                offReason: offReason, offPortion: sentPortion, note: dayNote
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
