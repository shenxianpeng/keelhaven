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

    /// Weekday numbers in the user's regional order (e.g. Monday-first in
    /// most of Europe and China), tagging the real Calendar weekday values.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        // The weekday and time-of-day controls sit in a column beside the
        // radios rather than stacked under them. That saves a row — two in
        // weekly mode — and, more usefully, keeps this section exactly three
        // rows tall at every frequency, so changing the frequency no longer
        // makes everything below it jump.
        HStack(alignment: .center, spacing: 20) {
            Picker("Frequency", selection: $kind) {
                ForEach(ScheduleKind.allCases) { kind in
                    Text(kind.localizedTitle).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            // Hourly needs neither control, and they are removed from the
            // hierarchy rather than disabled — so whenever this column is on
            // screen, the frequency it qualifies is the one that is selected.
            if kind != .hourly {
                VStack(alignment: .leading, spacing: 8) {
                    if kind == .weekly {
                        Picker("On", selection: $weekday) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                Text(Schedule.weekdayName(day)).tag(day)
                            }
                        }
                    }

                    DatePicker(
                        "At",
                        selection: $dailyTime,
                        displayedComponents: .hourAndMinute
                    )
                }
                .fixedSize()
            }
        }
    }
}
