import SwiftUI

/// Editor for a single day. Sends `PUT /timesheet/{id}/day` and adopts the
/// refreshed card the server returns.
///
/// One unified form (not a mode toggle), because the API's model isn't
/// exclusive: a half-day off (`am`/`pm`) records the *worked* half alongside the
/// time-off reason, while a full-day off clears the times automatically.
struct DayEditView: View {
    @EnvironmentObject private var state: AppState
    let day: Day
    let onDismiss: () -> Void

    @State private var regStart = ""
    @State private var regEnd = ""
    @State private var otStart = ""
    @State private var otEnd = ""
    @State private var note = ""
    @State private var offReason = ""     // "" = none, else a DayType.slug
    @State private var offPortion = "full"
    @State private var saving = false

    private var dayTypes: [DayType] { state.timesheet?.dayTypes ?? [] }
    private var offPortions: [OffPortionOption] { state.timesheet?.offPortions ?? [] }
    private var isFullDayOff: Bool { !offReason.isEmpty && offPortion == "full" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Worked time
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
            .opacity(isFullDayOff ? 0.5 : 1)

            Divider()

            // Time off
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
                }
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
        .onAppear(perform: loadFromDay)
    }

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

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note").font(.caption).foregroundStyle(.secondary)
            TextField("Optional", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
    }

    // MARK: - Logic

    private var isValid: Bool {
        // Times must be valid or blank, and paired (both or neither).
        let times = [regStart, regEnd, otStart, otEnd].allSatisfy(TimeString.isValid)
        let regPaired = regStart.isEmpty == regEnd.isEmpty
        let otPaired = otStart.isEmpty == otEnd.isEmpty
        return times && regPaired && otPaired
    }

    private func loadFromDay() {
        regStart = TimeString.display12(day.regStart)
        regEnd = TimeString.display12(day.regEnd)
        otStart = TimeString.display12(day.otStart)
        otEnd = TimeString.display12(day.otEnd)
        note = day.note
        offReason = day.offReason
        offPortion = day.offPortion.isEmpty ? (offPortions.first?.value ?? "full") : day.offPortion
        state.errorMessage = nil
    }

    private func save() {
        guard !saving else { return }
        saving = true

        let fullDayOff = !offReason.isEmpty && offPortion == "full"
        let update = DayUpdate(
            date: day.date,
            // A full-day off clears worked times; otherwise send what's entered,
            // converted from the 12-hour display back to the API's 24-hour "HH:MM".
            regStart: fullDayOff ? "" : (TimeString.parse24(regStart) ?? ""),
            regEnd: fullDayOff ? "" : (TimeString.parse24(regEnd) ?? ""),
            otStart: fullDayOff ? "" : (TimeString.parse24(otStart) ?? ""),
            otEnd: fullDayOff ? "" : (TimeString.parse24(otEnd) ?? ""),
            offReason: offReason,
            offPortion: offReason.isEmpty ? "" : offPortion,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        Task {
            let ok = await state.saveDay(update)
            saving = false
            if ok { onDismiss() }
        }
    }
}

/// A labelled start/end pair of time fields.
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
