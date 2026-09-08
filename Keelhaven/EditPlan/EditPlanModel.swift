import Foundation
import KeelhavenCore
import Observation

/// Draft state for the Edit Plan window, seeded from the stored plan and
/// written back through `AppState.updatePlan` on Save. The four settings the
/// wizard also collects live in `options`, so both windows edit one model.
@MainActor
@Observable
final class EditPlanModel {
    var name = ""
    var sourcePaths: [String] = []
    var scheduleKind: ScheduleKind = .daily
    var dailyTime = Schedule.defaultDailyTime
    var weekday = Calendar.current.firstWeekday
    var options = PlanOptionsDraft()

    func load(from plan: BackupPlan) {
        name = plan.name
        sourcePaths = plan.sourcePaths
        (scheduleKind, dailyTime, weekday) = plan.schedule.editorComponents
        options.load(from: plan)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !sourcePaths.isEmpty
    }

    func builtSchedule() -> Schedule {
        Schedule(kind: scheduleKind, dailyTime: dailyTime, weekday: weekday)
    }
}
