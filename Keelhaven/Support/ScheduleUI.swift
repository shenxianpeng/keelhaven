import SwiftUI
import KeelhavenCore

// The UI-side vocabulary for Schedule, shared by the wizard's schedule step,
// the plan row's caption, and the Edit Plan window — one mapping, one wording.

extension Schedule {
    /// The default time-of-day offered when a plan switches to daily: 21:00,
    /// same as the wizard's initial value.
    static var defaultDailyTime: Date {
        Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    }

    init(kind: ScheduleKind, dailyTime: Date, weekday: Int) {
        switch kind {
        case .hourly:
            self = .hourly
        case .daily:
            let components = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            self = .daily(hour: components.hour ?? 21, minute: components.minute ?? 0)
        case .weekly:
            let components = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            self = .weekly(
                weekday: weekday,
                hour: components.hour ?? 21,
                minute: components.minute ?? 0
            )
        }
    }

    /// The inverse of `init(kind:dailyTime:weekday:)`, for seeding edit
    /// controls from a stored plan. Every case carries a sensible time and
    /// weekday so switching the picker doesn't land on a random value.
    var editorComponents: (kind: ScheduleKind, dailyTime: Date, weekday: Int) {
        switch self {
        case .hourly:
            return (.hourly, Self.defaultDailyTime, Calendar.current.firstWeekday)
        case .daily(let hour, let minute):
            let time = Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: Date()
            ) ?? Self.defaultDailyTime
            return (.daily, time, Calendar.current.firstWeekday)
        case .weekly(let weekday, let hour, let minute):
            let time = Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: Date()
            ) ?? Self.defaultDailyTime
            return (.weekly, time, weekday)
        }
    }

    /// "Every hour" / "Every day at 21:00" / "Every week on Sunday at 21:00" —
    /// the same three words the frequency picker uses, so the row and the
    /// editor never describe one schedule two ways. Follows the user's locale
    /// and 12/24-hour preference.
    var displayText: String {
        switch self {
        case .hourly:
            return String(localized: "Every hour")
        case .daily:
            let time = editorComponents.dailyTime.formatted(date: .omitted, time: .shortened)
            return String(localized: "Every day at \(time)")
        case .weekly(let weekday, _, _):
            let time = editorComponents.dailyTime.formatted(date: .omitted, time: .shortened)
            let day = Self.weekdayName(weekday)
            return String(localized: "Every week on \(day) at \(time)")
        }
    }

    /// Localized weekday name for a Calendar weekday number (1 = Sunday).
    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "?" }
        return symbols[weekday - 1]
    }
}

/// The frequency picker + conditional time-of-day picker, extracted from the
/// wizard's schedule step so the Edit Plan window shows the identical controls.
struct ScheduleEditor: View {
    @Binding var kind: ScheduleKind
    @Binding var dailyTime: Date
    @Binding var weekday: Int

    /// The height of the tallest row (the weekly one, whose pop-up button is
    /// taller than a radio or a time field), applied to all three.
    private let rowHeight: CGFloat = 24

    /// Weekday numbers in the user's regional order (e.g. Monday-first in
    /// most of Europe and China), tagging the real Calendar weekday values.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        // A vertical radio list where each frequency's qualifying controls sit
        // on that frequency's own row, and only while it is the selected one.
        // Stacking them under the group made the section one row tall on
        // hourly, two on daily and three on weekly, so changing your mind slid
        // every section below it up or down; here it is always three rows, and
        // whatever is on screen reads as one sentence with the frequency it
        // belongs to.
        VStack(alignment: .leading, spacing: 8) {
            frequencyRow(.hourly) {
                // Hourly schedules need nothing more than the radio itself —
                // no time-of-day or weekday controls qualify it.
            }
            frequencyRow(.daily) {
                timePicker
            }
            frequencyRow(.weekly) {
                weekdayPicker
                timePicker
            }
        }
        // A radio per row means three one-option radio groups rather than one
        // group of three; containing them keeps VoiceOver reading the choices
        // for one setting as a single cluster.
        .accessibilityElement(children: .contain)
    }

    /// One radio and, when it is the chosen one, the controls that qualify it.
    private func frequencyRow(
        _ rowKind: ScheduleKind,
        @ViewBuilder controls: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            // One single-option picker per row, all three bound to the same
            // selection: it behaves as one radio group, but gives each radio a
            // row of its own to hang controls off. A single `.radioGroup`
            // Picker owns its whole layout and can only be stacked around.
            Picker("Frequency", selection: $kind) {
                Text(rowKind.localizedTitle).tag(rowKind)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if kind == rowKind {
                controls()
            }
        }
        // A row is as tall as whatever control it carries — a bare radio, a
        // time field, a pop-up button — so without a floor the section would
        // still breathe a couple of points as the frequency changed. The floor
        // is the tallest of the three.
        .frame(minHeight: rowHeight, alignment: .leading)
    }

    private var weekdayPicker: some View {
        Picker("On", selection: $weekday) {
            ForEach(orderedWeekdays, id: \.self) { day in
                Text(Schedule.weekdayName(day)).tag(day)
            }
        }
        .fixedSize()
    }

    private var timePicker: some View {
        DatePicker(
            "At",
            selection: $dailyTime,
            displayedComponents: .hourAndMinute
        )
        .fixedSize()
    }
}
