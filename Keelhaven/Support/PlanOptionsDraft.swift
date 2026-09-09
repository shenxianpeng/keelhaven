import Foundation
import Observation
import KeelhavenCore

/// The retention choice as the picker sees it: which of the four, with the
/// count held separately. Same split as `ScheduleKind` and `builtSchedule()`
/// — a parameterised choice edits badly when the parameter lives inside the
/// selection (issue #52).
enum RetentionKind: String, CaseIterable, Identifiable {
    case off
    case year
    case month
    case lastN

    var id: String { rawValue }
}

/// The four plan settings that are neither "what / where / when" nor a
/// secret: verification cadence, retention, exclude patterns and restic's
/// throughput knobs.
///
/// Shared by the wizard's Options step and the Edit Plan window, because the
/// wizard used to omit all four (issue #39). A plan's first backup starts the
/// moment it is created, so settings only reachable afterwards were settings
/// that arrived one full backup too late — the excludes in particular.
@MainActor
@Observable
final class PlanOptionsDraft {
    var excludePatterns: [String]
    var checkCadence: CheckCadence
    var retentionKind: RetentionKind
    /// Held as text like the Advanced knobs, so a half-typed number never
    /// snaps back under the cursor. Only read when `retentionKind` is
    /// `.lastN`.
    var keepLastText = ""
    /// The floor `RetentionPolicy` clamps to, used when the field is empty
    /// or unparseable — never zero, which would mean "delete everything".
    private static let defaultKeepLast = 10
    /// The boolean `restic backup` switches (issues #46, #50). Off by
    /// default, like every other advanced setting here.
    var excludeCaches = false
    var oneFileSystem = false
    var noScan = false
    var skipIfUnchanged = false
    /// Scratch field for the exclude-pattern TextField.
    var newExcludePattern = ""
    /// The Advanced knobs are held as text so an empty field can mean
    /// "restic's own default" — a number would have to invent one.
    var uploadLimitText = ""
    var readConcurrencyText = ""
    var packSizeText = ""

    /// Defaults deliberately mirror `BackupPlan.init`'s, so a wizard run that
    /// never opens this step produces exactly the plan it produced before the
    /// step existed.
    init(
        excludePatterns: [String] = BackupPlan.defaultExcludePatterns,
        checkCadence: CheckCadence = .weekly,
        retention: RetentionPolicy = .off
    ) {
        self.excludePatterns = excludePatterns
        self.checkCadence = checkCadence
        (self.retentionKind, self.keepLastText) = Self.editorComponents(for: retention)
    }

    /// The inverse of `builtRetention()`, for seeding the picker from a
    /// stored plan — mirroring `Schedule.editorComponents`.
    private static func editorComponents(for policy: RetentionPolicy) -> (RetentionKind, String) {
        switch policy {
        case .off: return (.off, String(defaultKeepLast))
        case .year: return (.year, String(defaultKeepLast))
        case .month: return (.month, String(defaultKeepLast))
        case .lastN: return (.lastN, String(policy.keepLastCount ?? defaultKeepLast))
        }
    }

    /// Anything unparseable falls back to the default count rather than to
    /// zero: `RetentionPolicy` clamps too, but a policy that silently became
    /// "keep nothing" is the one outcome worth guarding twice.
    func builtRetention() -> RetentionPolicy {
        switch retentionKind {
        case .off: return .off
        case .year: return .year
        case .month: return .month
        case .lastN:
            let typed = Int(keepLastText.trimmingCharacters(in: .whitespaces))
            return .lastN(typed ?? Self.defaultKeepLast)
        }
    }

    func load(from plan: BackupPlan) {
        excludePatterns = plan.excludePatterns
        checkCadence = plan.checkCadence
        (retentionKind, keepLastText) = Self.editorComponents(for: plan.retention)
        excludeCaches = plan.backupOptions.excludeCaches
        oneFileSystem = plan.backupOptions.oneFileSystem
        noScan = plan.backupOptions.noScan
        skipIfUnchanged = plan.backupOptions.skipIfUnchanged
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

    func builtBackupOptions() -> BackupOptions {
        BackupOptions(
            excludeCaches: excludeCaches,
            oneFileSystem: oneFileSystem,
            noScan: noScan,
            skipIfUnchanged: skipIfUnchanged
        )
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
