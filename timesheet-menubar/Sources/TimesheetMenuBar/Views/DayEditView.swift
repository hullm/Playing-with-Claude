import SwiftUI

/// Editor for a single day. Sends a `PUT /timesheet/{id}/day` and adopts the
/// refreshed card the server returns.
struct DayEditView: View {
    @EnvironmentObject private var state: AppState
    let day: Day
    let onDismiss: () -> Void

    // Editable copies
    @State private var regStart: String = ""
    @State private var regEnd: String = ""
    @State private var otStart: String = ""
    @State private var otEnd: String = ""
    @State private var note: String = ""
    @State private var offReason: String = ""          // "" = none; else a DayType.value
    @State private var offPortion: String = OffPortion.full.rawValue
    @State private var mode: EntryMode = .worked
    @State private var saving = false

    // ┌── RECONCILE-ME ────────────────────────────────────────────────────────┐
    // │ `offPortion` values below are inferred. If API.md specifies different    │
    // │ strings (e.g. "1", "0.5"), change the rawValues here only.               │
    // └──────────────────────────────────────────────────────────────────────────┘
    enum OffPortion: String, CaseIterable, Identifiable {
        case full, half
        var id: String { rawValue }
        var label: String { self == .full ? "Full day" : "Half day" }
    }

    enum EntryMode: String, CaseIterable, Identifiable {
        case worked, timeOff
        var id: String { rawValue }
        var label: String { self == .worked ? "Worked" : "Time off" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("", selection: $mode) {
                ForEach(EntryMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .worked {
                workedFields
            } else {
                timeOffFields
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
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text(DateParsing.displayDate(day.date))
                .font(.headline)
            Spacer()
        }
    }

    private var workedFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimeRange(title: "Regular", start: $regStart, end: $regEnd)
            TimeRange(title: "Overtime", start: $otStart, end: $otEnd)
            Text("24-hour time, e.g. 09:00. Leave blank to clear.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var timeOffFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Reason", selection: $offReason) {
                Text("Select…").tag("")
                ForEach(state.timesheet?.dayTypes ?? []) { type in
                    Text(type.label).tag(type.value)
                }
            }
            Picker("Amount", selection: $offPortion) {
                ForEach(OffPortion.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
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
        if mode == .worked {
            return [regStart, regEnd, otStart, otEnd].allSatisfy(TimeString.isValid)
        } else {
            return !offReason.isEmpty
        }
    }

    private func loadFromDay() {
        regStart = day.regStart
        regEnd = day.regEnd
        otStart = day.otStart ?? ""
        otEnd = day.otEnd ?? ""
        note = day.note ?? ""
        offReason = day.offReason ?? ""
        offPortion = day.offPortion ?? OffPortion.full.rawValue
        mode = day.isTimeOff ? .timeOff : .worked
        state.errorMessage = nil
    }

    private func save() {
        guard !saving else { return }
        saving = true

        let update: DayUpdate
        if mode == .worked {
            update = DayUpdate(
                date: day.date,
                regStart: TimeString.normalized(regStart),
                regEnd: TimeString.normalized(regEnd),
                otStart: emptyToNil(TimeString.normalized(otStart)),
                otEnd: emptyToNil(TimeString.normalized(otEnd)),
                offReason: "",          // clear any prior time-off
                offPortion: nil,
                note: emptyToNil(note)
            )
        } else {
            update = DayUpdate(
                date: day.date,
                regStart: "",            // clear work times when taking time off
                regEnd: "",
                otStart: nil,
                otEnd: nil,
                offReason: offReason,
                offPortion: offPortion,
                note: emptyToNil(note)
            )
        }

        Task {
            let ok = await state.saveDay(update)
            saving = false
            if ok { onDismiss() }
        }
    }

    private func emptyToNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
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
            .frame(width: 74)
            .monospacedDigit()
            .foregroundStyle(TimeString.isValid(binding.wrappedValue) ? .primary : .red)
            .onSubmit { binding.wrappedValue = TimeString.normalized(binding.wrappedValue) }
    }
}
