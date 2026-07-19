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
                    Text("Hi, \(me.firstName)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !me.fillsTimecard {
                        Text("No timecard required")
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
                TotalsBar(totals: ts.totals)
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
                get: { state.timesheet?.id ?? state.currentPeriod?.id ?? -1 },
                set: { newID in Task { await state.loadTimesheet(periodID: newID) } }
            )) {
                ForEach(state.periods) { period in
                    Text(period.isCurrent ? "\(period.label) • current" : period.label)
                        .tag(period.id)
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

    // Approximate rendered height of one DayRow (content + padding + divider).
    private let rowHeight: CGFloat = 47
    // Never grow the list past this; scroll beyond it.
    private let maxListHeight: CGFloat = 470

    private func daysList(_ ts: Timesheet) -> some View {
        let today = DateParsing.todayString()
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(ts.days) { day in
                    DayRow(day: day, editable: ts.editable, isToday: day.date == today) {
                        state.errorMessage = nil
                        editingDay = day
                    }
                    Divider()
                }
            }
        }
        // A ScrollView has no intrinsic height, so give it a definite one:
        // fit the days exactly for short lists, cap + scroll for the full 14.
        .frame(height: min(CGFloat(ts.days.count) * rowHeight, maxListHeight))
    }

    private func submitSection(_ ts: Timesheet) -> some View {
        VStack(spacing: 6) {
            if let blocked = state.submitBlockedMessage {
                Label(blocked, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(isSubmitted(ts) ? "Submitted ✓" : "Sign & Submit")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!state.canSubmit || state.isLoading)
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

    private func isSubmitted(_ ts: Timesheet) -> Bool {
        ["submitted", "approved", "accepted"].contains(ts.status.lowercased())
    }

    private func submit() {
        submitResult = nil
        Task {
            if let blocking = await state.submit() {
                submitResult = SubmitOutcome(message: blocking, isSuccess: false)
            } else {
                submitResult = SubmitOutcome(message: "Signed & submitted. Your approver has been emailed.", isSuccess: true)
            }
        }
    }

    struct SubmitOutcome { let message: String; let isSuccess: Bool }
}

// MARK: - Row

private struct DayRow: View {
    let day: Day
    let editable: Bool
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(DateParsing.displayDate(day.date))
                            .font(.callout.weight(isToday ? .semibold : .medium))
                            .foregroundStyle(isToday ? Color.accentColor
                                             : (day.isWeekend ? Color.secondary : Color.primary))
                        if isToday {
                            Text("Today")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    summaryLine
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if day.hours.total > 0 {
                    Text("\(day.hours.total.hoursLabel)h")
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
            .background(isToday ? Color.accentColor.opacity(0.10) : Color.clear)
            .overlay(alignment: .leading) {
                if isToday {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
    }

    @ViewBuilder private var summaryLine: some View {
        if day.isTimeOff {
            Text(timeOffSummary)
        } else if day.hasWorkTime {
            Text(workSummary)
        } else if day.isWeekend {
            Text("Weekend")
        } else {
            Text("—")
        }
    }

    private var timeOffSummary: String {
        let portion = day.offPortion.isEmpty || day.offPortion == "full" ? "" : " (\(day.offPortion.uppercased()))"
        return "Time off — \(day.offReason)\(portion)"
    }

    private var workSummary: String {
        var parts: [String] = []
        if !day.regStart.isEmpty || !day.regEnd.isEmpty {
            parts.append("\(display(day.regStart))–\(display(day.regEnd))")
        }
        if !day.otStart.isEmpty || !day.otEnd.isEmpty {
            parts.append("OT \(display(day.otStart))–\(display(day.otEnd))")
        }
        return parts.joined(separator: "  ")
    }

    private func display(_ s: String) -> String {
        s.isEmpty ? "?" : TimeString.display12(s)
    }
}

// MARK: - Small components

private struct TotalsBar: View {
    let totals: HourTotals
    var body: some View {
        HStack(spacing: 16) {
            total("Total", totals.total, emphasised: true)
            total("Reg", totals.reg)
            total("OT", totals.ot)
            total("Off", totals.off)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func total(_ label: String, _ value: Double, emphasised: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(value.hoursLabel)h")
                .font(.callout.monospacedDigit().weight(emphasised ? .bold : .semibold))
                .foregroundStyle(emphasised ? .primary : .secondary)
        }
    }
}

private struct StatusPill: View {
    let status: String
    let editable: Bool
    var body: some View {
        Text(prettyStatus)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var prettyStatus: String {
        status.replacingOccurrences(of: "-", with: " ").capitalized
    }
    private var color: Color {
        switch status.lowercased() {
        case "submitted", "approved", "accepted": return .green
        case "rejected": return .red
        case "draft": return editable ? .blue : .secondary
        case "not-started": return .secondary
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
