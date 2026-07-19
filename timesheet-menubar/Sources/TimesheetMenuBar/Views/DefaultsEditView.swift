import SwiftUI

/// Editor for the user's default workday hours (`GET`/`PUT /me/defaults`).
/// These pre-fill blank days on new timesheets.
struct DefaultsEditView: View {
    @EnvironmentObject private var state: AppState

    @State private var regStart = ""
    @State private var regEnd = ""
    @State private var fullDayHours: Double?
    @State private var loading = true
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if loading {
                HStack {
                    Spacer()
                    ProgressView("Loading defaults…").font(.callout).padding(20)
                    Spacer()
                }
            } else {
                Text("Your standard workday. New timesheets pre-fill blank weekdays with these times.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("Workday")
                        .font(.callout)
                        .frame(width: 66, alignment: .leading)
                    timeField($regStart, placeholder: "start")
                    Text("→").foregroundStyle(.secondary)
                    timeField($regEnd, placeholder: "end")
                }

                Text("Enter times like 7:30 AM.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let hours = fullDayHours {
                    Text("A full day off counts as \(hours.hoursLabel) hours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Cancel") { state.cancelEditingDefaults() }
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
        }
        .padding(12)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button(action: { state.cancelEditingDefaults() }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text("Default hours").font(.headline)
            Spacer()
        }
    }

    private var isValid: Bool {
        TimeString.isValid(regStart) && TimeString.isValid(regEnd)
        && !regStart.trimmingCharacters(in: .whitespaces).isEmpty
        && !regEnd.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load() async {
        loading = true
        if let d = await state.loadDefaults() {
            regStart = TimeString.display12(d.regStart)
            regEnd = TimeString.display12(d.regEnd)
            fullDayHours = d.fullDayHours
        }
        loading = false
    }

    private func save() {
        guard !saving, isValid else { return }
        guard let start = TimeString.parse24(regStart), !start.isEmpty,
              let end = TimeString.parse24(regEnd), !end.isEmpty else {
            saveError = "Enter valid start and end times."
            return
        }
        saving = true
        saveError = nil
        Task {
            // saveDefaults returns nil on success (and flips editingDefaults off,
            // routing back to the timesheet), or a message to show on failure.
            let error = await state.saveDefaults(regStart: start, regEnd: end)
            saving = false
            if let error { saveError = error }
        }
    }

    private func timeField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
            .frame(width: 96)
            .foregroundStyle(TimeString.isValid(binding.wrappedValue) ? Color.primary : Color.red)
            .onSubmit { binding.wrappedValue = TimeString.normalizedDisplay(binding.wrappedValue) }
    }
}
