import SwiftUI

/// Main screen: greeting, period picker, the 14-day list, totals, and submit.
struct TimesheetView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingDay: Day?
    @State private var submitResult: SubmitOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let editingDay {
                DayEditView(day: editingDay) { self.editingDay = nil }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainList
            }
        }
        .animation(.easeInOut(duration: 0.18), value: editingDay)
    }

    private var mainList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let me = state.me {
                HStack {
                    Text("Hi, \(me.name.split(separator: " ").first.map(String.init) ?? me.name)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !me.fillsTimecard {
                        Text("Not required to fill a timecard")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            periodPicker

            if let error = state.errorMessage {
                InlineError(text: error)
            }

            if state.isLoading && state.timesheet == nil {
                loadingPlaceholder
            } else if let ts = state.timesheet {
                daysList(ts)
                Divider()
                TotalsBar(timesheet: ts)
                submitSection(ts)
            } else if !state.isLoading {
                Text("No timesheet available for this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }

    private var periodPicker: some View {
        HStack {
            Picker("Period", selection: Binding(
                get: { state.timesheet?.id ?? state.currentPeriod?.id ?? "" },
                set: { newID in Task { await state.loadTimesheet(periodID: newID) } }
            )) {
                ForEach(state.periods) { period in
                    HStack {
                        Text(period.displayTitle)
                        if period.isCurrent { Text("• current") }
                    }.tag(period.id)
                }
            }
            .labelsHidden()
            .disabled(state.isLoading)
            if let ts = state.timesheet {
                StatusPill(status: ts.status, editable: ts.editable)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func daysList(_ ts: Timesheet) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(ts.days) { day in
                    DayRow(day: day, editable: ts.editable) {
                        state.errorMessage = nil
                        editingDay = day
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func submitSection(_ ts: Timesheet) -> some View {
        VStack(spacing: 6) {
            if let blocked = state.submitBlockedUntilDate, blocked > Date() {
                Label("Submit unlocks \(DateParsing.relativeTime(blocked))",
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let outcome = submitResult {
                Text(outcome.message)
                    .font(.caption)
                    .foregroundStyle(outcome.isSuccess ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                submit()
            } label: {
                HStack {
                    if state.isLoading { ProgressView().controlSize(.small) }
                    Text(ts.status.lowercased() == "submitted" ? "Submitted" : "Sign & Submit")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!state.canSubmit || state.isLoading || ts.status.lowercased() == "submitted")
        }
        .padding(12)
    }

    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView("Loading timesheet…")
                .font(.callout)
                .padding(24)
            Spacer()
        }
    }

    private func submit() {
        submitResult = nil
        Task {
            if let blocking = await state.submit() {
                submitResult = SubmitOutcome(message: blocking, isSuccess: false)
            } else {
                submitResult = SubmitOutcome(message: "Submitted. Thanks!", isSuccess: true)
            }
        }
    }

    struct SubmitOutcome { let message: String; let isSuccess: Bool }
}

// MARK: - Row

private struct DayRow: View {
    let day: Day
    let editable: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateParsing.displayDate(day.date))
                        .font(.callout.weight(.medium))
                    summaryLine
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let hours = day.hours, hours > 0 {
                    Text("\(hours.hoursLabel)h")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if editable {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
    }

    @ViewBuilder private var summaryLine: some View {
        if day.isTimeOff {
            Text("Time off — \(day.offReason ?? "")\(day.offPortion.map { " (\($0))" } ?? "")")
        } else if day.hasWorkTime {
            Text(workSummary)
        } else {
            Text("—")
        }
    }

    private var workSummary: String {
        var parts: [String] = []
        if !day.regStart.isEmpty || !day.regEnd.isEmpty {
            parts.append("\(day.regStart.isEmpty ? "?" : day.regStart)–\(day.regEnd.isEmpty ? "?" : day.regEnd)")
        }
        if let s = day.otStart, let e = day.otEnd, !(s.isEmpty && e.isEmpty) {
            parts.append("OT \(s)–\(e)")
        }
        return parts.joined(separator: "  ")
    }
}

// MARK: - Small components

private struct TotalsBar: View {
    let timesheet: Timesheet
    var body: some View {
        HStack(spacing: 14) {
            total("Total", timesheet.periodHours)
            total("Reg", timesheet.regularHours)
            total("OT", timesheet.overtimeHours)
            total("Off", timesheet.timeOffHours)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func total(_ label: String, _ value: Double?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text("\(value.hoursLabel)h").font(.callout.monospacedDigit().weight(.semibold))
            }
        }
    }
}

private struct StatusPill: View {
    let status: String
    let editable: Bool
    var body: some View {
        Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch status.lowercased() {
        case "submitted", "approved", "signed": return .green
        case "open", "draft", "in_progress": return editable ? .blue : .secondary
        case "locked", "closed": return .secondary
        default: return .secondary
        }
    }
}

private struct InlineError: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }
}
