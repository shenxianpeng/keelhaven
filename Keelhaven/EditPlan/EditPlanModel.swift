import Foundation
import KeelhavenCore
import Observation

/// Draft state for the Edit Plan window, seeded from the stored plan and
/// written back through `AppState.updatePlan` on Save.
@MainActor
@Observable
final class EditPlanModel {
    var name = ""
    var sourcePaths: [String] = []
    var excludePatterns: [String] = []
    var scheduleKind: ScheduleKind = .daily
    var dailyTime = Schedule.defaultDailyTime
    var weekday = Calendar.current.firstWeekday
    var checkCadence: CheckCadence = .weekly
    var retention: RetentionPolicy = .off
    /// Scratch field for the exclude-pattern TextField.
    var newExcludePattern = ""
    /// The Advanced knobs are held as text so an empty field can mean
    /// "restic's own default" — a number would have to invent one.
    var uploadLimitText = ""
    var readConcurrencyText = ""
    var packSizeText = ""

    func load(from plan: BackupPlan) {
        name = plan.name
        sourcePaths = plan.sourcePaths
        excludePatterns = plan.excludePatterns
        (scheduleKind, dailyTime, weekday) = plan.schedule.editorComponents
        checkCadence = plan.checkCadence
        retention = plan.retention
        newExcludePattern = ""
        uploadLimitText = Self.text(plan.performance.uploadLimitKiBPerSecond)
        readConcurrencyText = Self.text(plan.performance.readConcurrency)
        packSizeText = Self.text(plan.performance.packSizeMiB)
    }

    private static func text(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    /// Anything unparseable is treated as "unset" rather than rejected: the
    /// fields are optional, and `PerformanceOptions` clamps what does parse.
    func builtPerformance() -> PerformanceOptions {
        PerformanceOptions(
            uploadLimitKiBPerSecond: Int(uploadLimitText.trimmingCharacters(in: .whitespaces)),
            readConcurrency: Int(readConcurrencyText.trimmingCharacters(in: .whitespaces)),
            packSizeMiB: Int(packSizeText.trimmingCharacters(in: .whitespaces))
        )
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !sourcePaths.isEmpty
    }

    func builtSchedule() -> Schedule {
        Schedule(kind: scheduleKind, dailyTime: dailyTime, weekday: weekday)
    }

    func addExcludePattern() {
        let trimmed = newExcludePattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !excludePatterns.contains(trimmed) else { return }
        excludePatterns.append(trimmed)
        newExcludePattern = ""
    }

    func removeExcludePattern(_ pattern: String) {
        excludePatterns.removeAll { $0 == pattern }
    }
}
