import SwiftUI

/// Main screen: greeting, period picker, the 14-day list, totals, and submit.
struct TimesheetView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingDay: Day?
    @State private var submitResult: SubmitOutcome?
    @State private var measuredListHeight: CGFloat = 0

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
                ForEach(state.visiblePeriods) { period in
                    Text("\(period.label) • \(period.isCurrent ? "current" : StatusLabel.text(period.status).lowercased())")
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

    // Approximate rendered height of one DayRow (fallback before measurement).
    private let rowHeight: CGFloat = 47
    // Never grow the list past this; scroll beyond it. High enough that the 10
    // weekday rows (weekends hidden) fit without scrolling; the full 14 scroll.
    private let maxListHeight: CGFloat = 540

    /// Days to show: hides all weekend rows unless "Show weekends" is on.
    private func visibleDays(_ ts: Timesheet) -> [Day] {
        ts.days.filter { state.showWeekends || !$0.isWeekend }
    }

    /// True when `next` falls in a later week of the period than `day` — i.e.
    /// the boundary between the period's two weeks.
    private func startsNewWeek(_ next: Day, after day: Day, _ ts: Timesheet) -> Bool {
        guard let a = DateParsing.weekIndex(startsOn: ts.period.startsOn, date: day.date),
              let b = DateParsing.weekIndex(startsOn: ts.period.startsOn, date: next.date) else {
            return false
        }
        return a != b
    }

    private func daysList(_ ts: Timesheet) -> some View {
        let today = state.today
        let days = visibleDays(ts)
        let hasToday = days.contains { $0.date == today }
        // slug → human label for time-off reasons (admin-managed; never
        // hardcoded). Prefer the /day-types catalog (covers retired reasons),
        // falling back to the timesheet's list.
        var reasonLabels = Dictionary(ts.dayTypes.map { ($0.slug, $0.label) },
                                      uniquingKeysWith: { first, _ in first })
        for t in state.dayTypesCatalog?.off ?? [] { reasonLabels[t.slug] = t.label }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                        DayRow(day: day, editable: ts.editable, isToday: day.date == today,
                               reasonLabels: reasonLabels) {
                            state.errorMessage = nil
                            editingDay = day
                        }
                        .id(day.date)
                        // A heavier rule separates the two weeks of the period.
                        if index < days.count - 1, startsNewWeek(days[index + 1], after: day, ts) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(height: 3)
                        } else {
                            Divider()
                        }
                    }
                }
                // Measure the true content height so the frame fits it exactly
                // (no stray scroll from an off-by-a-few-pixels estimate).
                .background(GeometryReader { geo in
                    Color.clear.preference(key: DayListHeightKey.self, value: geo.size.height)
                })
            }
            // A ScrollView has no intrinsic height, so give it a definite one:
            // exact content height when it fits, capped (scrolling) beyond that.
            .frame(height: min(measuredListHeight > 0 ? measuredListHeight
                               : CGFloat(days.count) * rowHeight, maxListHeight))
            .onPreferenceChange(DayListHeightKey.self) { measuredListHeight = $0 }
            // When the menu opens, bring today's row into view if it isn't
            // already (anchor: nil does a minimal scroll, so a visible row
            // doesn't move). No-op when the period doesn't contain today.
            .onAppear {
                guard hasToday else { return }
                DispatchQueue.main.async { proxy.scrollTo(today, anchor: nil) }
            }
        }
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

/// Reports the day list's true content height so its frame can fit exactly.
private struct DayListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DayRow: View {
    let day: Day
    let editable: Bool
    let isToday: Bool
    let reasonLabels: [String: String]
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
                        // A saved day gets a green check; a pre-filled (default,
                        // not-yet-saved) day gets a "default" tag.
                        if day.saved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Text("default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
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

    // Work and time off can coexist (a call-out on a sick day), so show both
    // when both are present. The right-aligned total carries the summed hours.
    @ViewBuilder private var summaryLine: some View {
        let work = workText
        let off = offText
        if !work.isEmpty && !off.isEmpty {
            Text("\(work) · off: \(off)")
        } else if !off.isEmpty {
            Text("Time off — \(off)")
        } else if !work.isEmpty {
            Text(work)
        } else if day.isWeekend {
            Text("Weekend")
        } else {
            Text("—")
        }
    }

    private func label(_ slug: String) -> String { reasonLabels[slug] ?? slug }

    /// Work ranges from the segment list (new API), else the flat pair (old
    /// API). Never the misleading first-in→last-out span. "" when no work.
    private var workText: String {
        if !day.workPeriods.isEmpty {
            return day.workPeriods.map { seg in
                let range = "\(display(seg.start))–\(display(seg.end))"
                return seg.kind == .ot ? "OT \(range)" : range
            }.joined(separator: ", ")
        }
        var parts: [String] = []
        if !day.regStart.isEmpty || !day.regEnd.isEmpty {
            parts.append("\(display(day.regStart))–\(display(day.regEnd))")
        }
        if !day.otStart.isEmpty || !day.otEnd.isEmpty {
            parts.append("OT \(display(day.otStart))–\(display(day.otEnd))")
        }
        return parts.joined(separator: "  ")
    }

    /// Off blocks joined: "Sick 8:00–10:00" (timed), "Personal Day (am) + Cancer
    /// Screening (pm)" (policy portions), or just the reason for a full day.
    private var offText: String {
        day.offList.map { e in
            switch e.portion {
            case "timed":
                return "\(label(e.reason)) \(display(e.start ?? ""))–\(display(e.end ?? ""))"
            case "am", "pm":
                return "\(label(e.reason)) (\(e.portion))"
            default:
                return label(e.reason)
            }
        }.joined(separator: " + ")
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
        StatusLabel.text(status)
    }
    private var color: Color {
        // Distinct color per lifecycle stage, roughly cool → warm → done.
        switch StatusLabel.normalized(status) {
        case "not-started": return .secondary          // nothing yet — gray
        case "draft":       return editable ? .blue : .secondary
        case "in-progress": return editable ? .blue : .secondary
        case "submitted":   return .orange             // sent, awaiting review
        case "approved":    return .purple             // approved, awaiting acceptance
        case "accepted":    return .green              // Complete
        case "rejected":    return .red
        default:            return .secondary
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
