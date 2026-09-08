import Foundation

/// Pure schedule math, kept free of timers and app state so it is fully
/// unit-testable. The app's timer asks `isDue` about once a minute.
public enum SchedulePolicy {
    public static func nextRun(
        for schedule: Schedule,
        after reference: Date,
        calendar: Calendar
    ) -> Date {
        switch schedule {
        case .hourly:
            return reference.addingTimeInterval(3600)
        case .daily(let hour, let minute):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: reference,
                matching: components,
                matchingPolicy: .nextTime
            ) ?? reference.addingTimeInterval(86400)
        case .weekly(let weekday, let hour, let minute):
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: reference,
                matching: components,
                matchingPolicy: .nextTime
            ) ?? reference.addingTimeInterval(7 * 86400)
        }
    }

    /// When this plan's next backup is expected, from one anchor rule:
    ///
    /// - it has run before → the first scheduled time after that run;
    /// - never run, created to start right away → `createdAt`, i.e. already
    ///   past, so it is due the moment the plan exists;
    /// - never run, created to wait → the first scheduled time after
    ///   `createdAt` (issue #42).
    ///
    /// `isDue` is defined in terms of this rather than repeating the anchor,
    /// so the menu bar's "Next backup:" line and the scheduler can never
    /// disagree about when a plan runs — they used to, for a fresh plan.
    public static func nextRun(
        for plan: BackupPlan,
        calendar: Calendar = .current
    ) -> Date {
        guard let lastRunDate = plan.lastRun?.date else {
            return plan.firstBackupStartsOnCreation
                ? plan.createdAt
                : nextRun(for: plan.schedule, after: plan.createdAt, calendar: calendar)
        }
        return nextRun(for: plan.schedule, after: lastRunDate, calendar: calendar)
    }

    /// A plan is due once its expected next run is in the past. Missed runs
    /// (Mac was asleep or the app wasn't running) therefore make the plan due
    /// immediately, and stay that way until it actually runs — so a plan whose
    /// creation-time backup was skipped because restic was busy is picked up
    /// by the next tick.
    public static func isDue(
        _ plan: BackupPlan,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        nextRun(for: plan, calendar: calendar) <= now
    }
}
