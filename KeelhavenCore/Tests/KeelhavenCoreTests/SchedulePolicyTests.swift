import XCTest
@testable import KeelhavenCore

final class SchedulePolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    /// `createdAt` defaults to a fixed instant before every `now` the tests
    /// use, so a never-run plan's anchor is deterministic rather than the
    /// real clock.
    private func makePlan(
        schedule: Schedule,
        lastRun: Date?,
        firstBackupStartsOnCreation: Bool = true,
        createdAt: Date? = nil
    ) -> BackupPlan {
        BackupPlan(
            name: "Test",
            sourcePaths: ["/tmp/src"],
            destination: .local(path: "/tmp/repo"),
            schedule: schedule,
            firstBackupStartsOnCreation: firstBackupStartsOnCreation,
            createdAt: createdAt ?? utcDate(2026, 8, 1, 0, 0),
            lastRun: lastRun.map { BackupRunRecord(date: $0, success: true) }
        )
    }

    func testHourlyNextRun() {
        let reference = utcDate(2026, 8, 14, 10, 30)
        let next = SchedulePolicy.nextRun(for: .hourly, after: reference, calendar: calendar)
        XCTAssertEqual(next, utcDate(2026, 8, 14, 11, 30))
    }

    func testDailyNextRunLaterSameDay() {
        let reference = utcDate(2026, 8, 14, 10, 0)
        let next = SchedulePolicy.nextRun(for: .daily(hour: 21, minute: 30), after: reference, calendar: calendar)
        XCTAssertEqual(next, utcDate(2026, 8, 14, 21, 30))
    }

    func testDailyNextRunRollsToTomorrow() {
        let reference = utcDate(2026, 8, 14, 22, 0)
        let next = SchedulePolicy.nextRun(for: .daily(hour: 21, minute: 30), after: reference, calendar: calendar)
        XCTAssertEqual(next, utcDate(2026, 8, 15, 21, 30))
    }

    func testNeverRanPlanIsDue() {
        let plan = makePlan(schedule: .hourly, lastRun: nil)
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 0, 0), calendar: calendar))
    }

    // MARK: - First run (issue #42)

    /// The whole point of the flag: skipping the creation-time run is not
    /// enough, because the scheduler asks again every minute. A plan created
    /// to wait must actually report "not due".
    func testPlanCreatedToWaitIsNotDueBeforeItsFirstScheduledTime() {
        let plan = makePlan(
            schedule: .daily(hour: 21, minute: 0),
            lastRun: nil,
            firstBackupStartsOnCreation: false,
            createdAt: utcDate(2026, 8, 14, 10, 0)
        )
        XCTAssertFalse(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 10, 1), calendar: calendar))
        XCTAssertFalse(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 20, 59), calendar: calendar))
    }

    func testPlanCreatedToWaitBecomesDueAtItsFirstScheduledTime() {
        let plan = makePlan(
            schedule: .daily(hour: 21, minute: 0),
            lastRun: nil,
            firstBackupStartsOnCreation: false,
            createdAt: utcDate(2026, 8, 14, 10, 0)
        )
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 21, 0), calendar: calendar))
    }

    /// A plan created to wait, whose first scheduled time passed while the Mac
    /// was off, still catches up — it does not silently skip a window.
    func testPlanCreatedToWaitCatchesUpAfterAMissedFirstWindow() {
        let plan = makePlan(
            schedule: .daily(hour: 21, minute: 0),
            lastRun: nil,
            firstBackupStartsOnCreation: false,
            createdAt: utcDate(2026, 8, 14, 10, 0)
        )
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 20, 9, 0), calendar: calendar))
    }

    func testNextRunOfPlanCreatedToStartNowIsItsCreationTime() {
        let created = utcDate(2026, 8, 14, 10, 0)
        let plan = makePlan(schedule: .daily(hour: 21, minute: 0), lastRun: nil, createdAt: created)
        XCTAssertEqual(SchedulePolicy.nextRun(for: plan, calendar: calendar), created)
    }

    func testNextRunOfPlanCreatedToWaitIsTheFirstScheduledTimeAfterCreation() {
        let plan = makePlan(
            schedule: .daily(hour: 21, minute: 0),
            lastRun: nil,
            firstBackupStartsOnCreation: false,
            createdAt: utcDate(2026, 8, 14, 10, 0)
        )
        XCTAssertEqual(
            SchedulePolicy.nextRun(for: plan, calendar: calendar),
            utcDate(2026, 8, 14, 21, 0)
        )
    }

    /// Once it has run, the flag stops mattering — the anchor is the last run.
    func testNextRunOfPlanThatHasRunAnchorsOnTheLastRun() {
        let plan = makePlan(
            schedule: .daily(hour: 21, minute: 0),
            lastRun: utcDate(2026, 8, 14, 21, 0),
            firstBackupStartsOnCreation: false,
            createdAt: utcDate(2026, 8, 1, 0, 0)
        )
        XCTAssertEqual(
            SchedulePolicy.nextRun(for: plan, calendar: calendar),
            utcDate(2026, 8, 15, 21, 0)
        )
    }

    func testNextRunForPlanUsesCurrentCalendarByDefault() {
        let plan = makePlan(schedule: .hourly, lastRun: nil, createdAt: utcDate(2026, 8, 14, 10, 0))
        XCTAssertEqual(SchedulePolicy.nextRun(for: plan), utcDate(2026, 8, 14, 10, 0))
    }

    func testHourlyPlanNotDueBeforeInterval() {
        let plan = makePlan(schedule: .hourly, lastRun: utcDate(2026, 8, 14, 10, 0))
        XCTAssertFalse(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 10, 59), calendar: calendar))
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 11, 0), calendar: calendar))
    }

    func testMissedDailyRunIsDueImmediately() {
        // Last ran Monday 21:30; Mac was asleep Tuesday; Wednesday morning it's overdue.
        let plan = makePlan(schedule: .daily(hour: 21, minute: 30), lastRun: utcDate(2026, 8, 10, 21, 30))
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 12, 9, 0), calendar: calendar))
    }

    func testDailyRunNotDueTwiceInSameWindow() {
        let plan = makePlan(schedule: .daily(hour: 21, minute: 30), lastRun: utcDate(2026, 8, 14, 21, 30))
        XCTAssertFalse(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 14, 23, 0), calendar: calendar))
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 15, 21, 30), calendar: calendar))
    }

    func testDailyNextRunFallsBackWhenCalendarCannotMatch() {
        // An unmatchable hour makes Calendar.nextDate return nil; the policy
        // falls back to +24h rather than crashing.
        let reference = utcDate(2026, 8, 14, 10, 0)
        let next = SchedulePolicy.nextRun(
            for: .daily(hour: 99, minute: 0), after: reference, calendar: calendar
        )
        XCTAssertEqual(next, reference.addingTimeInterval(86400))
    }

    // 2026-08-14 is a Friday; Calendar weekdays are 1 = Sunday … 7 = Saturday.

    func testWeeklyNextRunLaterSameWeek() {
        let reference = utcDate(2026, 8, 14, 10, 0)
        let next = SchedulePolicy.nextRun(
            for: .weekly(weekday: 7, hour: 9, minute: 0), after: reference, calendar: calendar
        )
        XCTAssertEqual(next, utcDate(2026, 8, 15, 9, 0))
    }

    func testWeeklyNextRunRollsToNextWeek() {
        // Friday 10:00, scheduled Fridays 09:00 — this week's slot has passed.
        let reference = utcDate(2026, 8, 14, 10, 0)
        let next = SchedulePolicy.nextRun(
            for: .weekly(weekday: 6, hour: 9, minute: 0), after: reference, calendar: calendar
        )
        XCTAssertEqual(next, utcDate(2026, 8, 21, 9, 0))
    }

    func testMissedWeeklyRunIsDueImmediately() {
        // Last ran Sunday Aug 2; the Mac slept through Sunday Aug 9 — overdue.
        let plan = makePlan(
            schedule: .weekly(weekday: 1, hour: 21, minute: 0),
            lastRun: utcDate(2026, 8, 2, 21, 0)
        )
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 11, 9, 0), calendar: calendar))
    }

    func testWeeklyRunNotDueTwiceInSameWeek() {
        let plan = makePlan(
            schedule: .weekly(weekday: 1, hour: 21, minute: 0),
            lastRun: utcDate(2026, 8, 9, 21, 0)
        )
        XCTAssertFalse(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 12, 9, 0), calendar: calendar))
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: utcDate(2026, 8, 16, 21, 0), calendar: calendar))
    }

    func testWeeklyNextRunFallsBackWhenCalendarCannotMatch() {
        // Same guard as the daily variant: an unmatchable weekday must fall
        // back to +7 days rather than crash.
        let reference = utcDate(2026, 8, 14, 10, 0)
        let next = SchedulePolicy.nextRun(
            for: .weekly(weekday: 99, hour: 9, minute: 0), after: reference, calendar: calendar
        )
        XCTAssertEqual(next, reference.addingTimeInterval(7 * 86400))
    }

    func testDefaultCalendarParameter() {
        // Hourly math is calendar-independent, so the `.current` default is
        // safe to exercise regardless of the machine's timezone.
        let reference = utcDate(2026, 8, 14, 10, 0)
        let plan = makePlan(schedule: .hourly, lastRun: reference)
        XCTAssertTrue(SchedulePolicy.isDue(plan, now: reference.addingTimeInterval(7200)))
    }
}
