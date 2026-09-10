import AppKit
import Foundation
import Observation
import KeelhavenCore

enum PlanRunState: Equatable {
    case idle
    /// `progress` is nil when restic cannot say how far along it is —
    /// `--no-scan` omits `total_bytes`, so there is nothing to divide by
    /// (issue #51). `bytesDone` is what the row shows instead.
    case running(progress: Double?, bytesDone: Int64?)
    case checking
    /// A dry run: restic is walking the sources to report what a backup
    /// would store, writing nothing (issue #43).
    case previewing(progress: Double?)
    case pruning
    case unlocking
    case succeeded(Date)
    case failed(String)
    /// A failure restic blames on a repository lock (exit code 11). Separate
    /// from `failed` for one reason: it is a failure the row can offer a fix
    /// for, so it carries an unlock button instead of dead red text.
    case failedLocked(String)
    /// A run that could not read part of what it was asked to back up: restic
    /// exit code 3, or a source folder this process cannot open at all, which
    /// the pre-flight catches before restic is even spawned.
    ///
    /// Split off `failed` for the same reason as `failedLocked` — it is a
    /// failure with a fix, and the fix is a macOS setting rather than
    /// anything restic can retry. It carries the paths because "at least one
    /// source file could not be read" is not something a person can act on.
    case failedUnreadable(paths: [String], totalUnreadable: Int, message: String)

    /// A restic process is going for this plan right now. The four cases that
    /// hold the repository lock; everything else is a resting state.
    var isActive: Bool {
        switch self {
        case .running, .checking, .previewing, .pruning, .unlocking: return true
        default: return false
        }
    }
}

/// Root observable state: owns the plan list, run states, and all services.
/// Backups are serialized — one at a time in v1.
@MainActor
@Observable
final class AppState {
    var plans: [BackupPlan] = []
    var runStates: [UUID: PlanRunState] = [:]
    var resticBinaryURL: URL?
    var startupError: String?
    /// True once bootstrap confirmed there are no plans — the trigger for the
    /// first-run welcome window.
    var shouldOfferWelcome = false
    var availableUpdate: UpdateInfo?

    @ObservationIgnored private let keychain: KeychainStoring = KeychainStore()
    @ObservationIgnored private let planStore = PlanStore()
    @ObservationIgnored private let historyStore = RunHistoryStore()
    @ObservationIgnored private let scheduler = SchedulerService()
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init() {
        resticBinaryURL = ResticLocator.locate()
        Task {
            await self.bootstrap()
        }
    }

    private func bootstrap() async {
        if let binaryURL = resticBinaryURL {
            let meetsMinimum = await ResticLocator.meetsMinimumVersion(at: binaryURL)
            if !meetsMinimum {
                startupError = String(localized: "Keelhaven needs restic \(ResticLocator.minimumVersionText) or newer. Update it with: brew upgrade restic")
            }
        }

        var plansLoadedCleanly = false
        do {
            plans = try await planStore.load()
            plansLoadedCleanly = true
        } catch {
            startupError = String(localized: "Could not load backup plans: \(error.localizedDescription)")
        }
        for plan in plans {
            runStates[plan.id] = .idle
        }
        // Offer the welcome window only when we know for sure there are no
        // plans — never on a load failure, where plans might exist on disk.
        if plansLoadedCleanly && plans.isEmpty {
            shouldOfferWelcome = true
        }

        await NotificationService.requestAuthorization()

        scheduler.start { [weak self] in
            Task { @MainActor in
                self?.runDuePlans()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.runDuePlans()
            }
        }

        // Missed-run catch-up at launch.
        runDuePlans()

        await checkForUpdatesIfNeeded()
    }

    // MARK: - Updates

    private static let lastUpdateCheckDefaultsKey = "lastUpdateCheckDate"
    private static let updateCheckInterval: TimeInterval = 24 * 60 * 60

    /// At most once a day, so a launch doesn't hit keelhaven.app every time.
    private func checkForUpdatesIfNeeded() async {
        let defaults = UserDefaults.standard
        if let lastCheck = defaults.object(forKey: Self.lastUpdateCheckDefaultsKey) as? Date,
           Date().timeIntervalSince(lastCheck) < Self.updateCheckInterval {
            return
        }
        defaults.set(Date(), forKey: Self.lastUpdateCheckDefaultsKey)
        availableUpdate = await UpdateChecker.checkForUpdate()
    }

    // MARK: - Menu bar

    /// What the menu bar shows. Idle is the Keelhaven mark (a template image in
    /// the asset catalog, so macOS tints it for light/dark and for the
    /// highlighted menu); the two transient states borrow SF Symbols, which
    /// already read as "working" and "something went wrong".
    enum MenuBarIcon: Equatable {
        case idle
        case symbol(String)
    }

    var menuBarIcon: MenuBarIcon {
        let states = runStates.values
        if states.contains(where: \.isActive) {
            return .symbol("arrow.triangle.2.circlepath")
        }
        if states.contains(where: {
            switch $0 {
            case .failed, .failedLocked, .failedUnreadable: return true
            default: return false
            }
        }) {
            return .symbol("exclamationmark.triangle")
        }
        return .idle
    }

    // MARK: - Plan lifecycle

    var planManager: PlanManager {
        PlanManager(keychain: keychain, resticBinaryURL: resticBinaryURL)
    }

    func createPlan(from draft: PlanDraft) async throws {
        let plan = try await planManager.createPlan(draft)
        plans.append(plan)
        runStates[plan.id] = .idle
        try await planStore.save(plans)
        // Kick the scheduler now instead of waiting up to 60s for its tick.
        // Whether that actually starts a backup is `SchedulePolicy.isDue`'s
        // call: a plan created with "Start the first backup now" unchecked is
        // not due yet, so this is a no-op for it (issue #42). Deliberately not
        // an `if` here — the flag has to hold across relaunches too, and only
        // the policy is asked on every tick and at launch.
        runDuePlans()
    }

    func renamePlan(_ plan: BackupPlan, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index].name = trimmed
        Task {
            try? await planStore.save(plans)
        }
    }

    /// Applies an Edit Plan save. Mutates the five editable fields in place —
    /// never replaces the whole struct, so a backup finishing concurrently
    /// keeps its `lastRun` write (`finishRun` mutates the same array slot).
    func updatePlan(
        id: UUID,
        name: String,
        sourcePaths: [String],
        excludePatterns: [String],
        schedule: Schedule,
        checkCadence: CheckCadence,
        retention: RetentionPolicy,
        performance: PerformanceOptions,
        backupOptions: BackupOptions
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !sourcePaths.isEmpty,
              let index = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[index].name = trimmed
        plans[index].sourcePaths = sourcePaths
        plans[index].excludePatterns = excludePatterns
        plans[index].schedule = schedule
        plans[index].checkCadence = checkCadence
        plans[index].retention = retention
        plans[index].performance = performance
        plans[index].backupOptions = backupOptions
        Task {
            try? await planStore.save(plans)
        }
    }

    /// Why `deletePlan` declined, so the caller can say so. It used to
    /// `guard !isResticBusy else { return }` — and a delete the user had just
    /// confirmed and authenticated with Touch ID would then do nothing at all,
    /// which on screen is indistinguishable from the list failing to refresh.
    /// The window was easy to hit: a scheduled `restic check` chains straight
    /// off a finished backup, so "Back Up Now, then delete" landed inside it.
    enum DeleteRefusal: Equatable {
        /// This plan's own backup, check, prune or unlock is mid-flight.
        case planIsActive
    }

    /// Removes a plan, its run states, its Keychain secrets and its history.
    /// Declines only while *this* plan's restic is running: that process holds
    /// the repository and its credentials, and pulling them out from under it
    /// is the one thing here that could leave the destination inconsistent.
    /// Another plan's run is unrelated (its secrets and process are its own),
    /// and the scheduler never starts a second restic while one is going, so
    /// deleting under it is safe.
    @discardableResult
    func deletePlan(_ plan: BackupPlan) -> DeleteRefusal? {
        if (runStates[plan.id] ?? .idle).isActive { return .planIsActive }
        plans.removeAll { $0.id == plan.id }
        runStates.removeValue(forKey: plan.id)
        planManager.removeSecrets(planID: plan.id)
        Task {
            try? await planStore.save(plans)
            try? await historyStore.deleteHistory(for: plan.id)
        }
        return nil
    }

    /// How far along restic says it is, or nil when it cannot say.
    ///
    /// Keyed on `total_bytes` rather than on the plan's `noScan` setting: that
    /// field's absence is what actually makes a percentage uncomputable, so
    /// the row stays honest even if restic changes when it omits it. A zero
    /// total is treated the same way — an empty source has no percentage to
    /// report either, and dividing by it would be worse.
    private static func progress(from status: BackupStatusMessage) -> Double? {
        guard let totalBytes = status.totalBytes, totalBytes > 0 else { return nil }
        return status.percentDone
    }

    // MARK: - Running backups

    /// True while any plan has a restic process going — a backup, a
    /// repository check, a retention pass, or an unlock. One restic at a time,
    /// app-wide: two invocations would contend for the repository lock.
    var isResticBusy: Bool {
        runStates.values.contains(where: \.isActive)
    }

    private func runDuePlans() {
        guard !isResticBusy else { return }
        let now = Date()
        if let due = plans.first(where: { SchedulePolicy.isDue($0, now: now) }) {
            runBackup(due)
        }
    }

    func runBackup(_ plan: BackupPlan) {
        guard !isResticBusy else { return }
        guard let binaryURL = resticBinaryURL else {
            runStates[plan.id] = .failed(ResticError.binaryNotFound.localizedDescription)
            return
        }

        runStates[plan.id] = .running(progress: nil, bytesDone: nil)
        Task {
            await self.performBackup(plan, binaryURL: binaryURL)
        }
    }

    private func performBackup(_ plan: BackupPlan, binaryURL: URL) async {
        let startedAt = Date()
        // Declared outside the `do` so a run that fails *after* restic has
        // already stored something can still say which snapshot it left
        // behind. Exit code 3 is exactly that shape: the summary arrives, and
        // only then does restic report that some files were unreadable.
        var summary: BackupSummary?
        do {
            // Pre-flight. A source folder this process cannot open is the one
            // failure the app can see coming without spending minutes inside
            // restic, so failing here costs a second instead of a whole
            // backup.
            //
            // What it can and cannot see: `SourceAccess` asks the filesystem
            // (`access(2)`), which reliably catches a folder whose POSIX mode
            // or ACLs shut this process out. TCC is enforced nearer `open(2)`,
            // so a folder the user has not granted access to may well pass
            // this check and only fail inside restic. Exit code 3 stays the
            // authoritative report; this is a head start, not the answer.
            let unreadableSources = SourceAccess.unreadableExistingPaths(plan.sourcePaths)
            guard unreadableSources.isEmpty else {
                throw ResticError.someSourcesUnreadable(
                    paths: Array(unreadableSources.prefix(ResticError.maxReportedUnreadablePaths)),
                    totalUnreadable: unreadableSources.count,
                    // Nothing came from restic: it was never spawned.
                    message: ""
                )
            }

            let credentials = try credentials(for: plan)
            let runner = ResticRunner(binaryURL: binaryURL)
            let stream = runner.backupStream(
                .backup(
                    sources: plan.sourcePaths,
                    excludes: plan.excludePatterns,
                    tag: "keelhaven",
                    performance: plan.performance,
                    options: plan.backupOptions
                ),
                destination: plan.destination,
                credentials: credentials
            )

            for try await event in stream {
                switch event {
                case .status(let status):
                    runStates[plan.id] = .running(
                        progress: Self.progress(from: status),
                        bytesDone: status.bytesDone
                    )
                case .summary(let value):
                    summary = value
                }
            }

            // restic omits `snapshot_id` from its summary when
            // `--skip-if-unchanged` finds nothing to store. Only trust that
            // when we asked for it: the same field is also absent from the
            // nested summary inside `restic snapshots --json`, so a bare nil
            // check is ambiguous everywhere else (issue #46).
            let skippedUnchanged = plan.backupOptions.skipIfUnchanged
                && summary != nil
                && summary?.snapshotID == nil
            let record = BackupRunRecord(
                date: startedAt,
                success: true,
                snapshotID: summary?.snapshotID,
                filesNew: summary?.filesNew,
                filesChanged: summary?.filesChanged,
                dataAddedBytes: summary?.dataAdded,
                duration: summary?.totalDuration,
                skippedUnchanged: skippedUnchanged
            )
            await finishRun(plan, record: record)
            runStates[plan.id] = .succeeded(Date())
            if skippedUnchanged {
                await NotificationService.postBackupUnchanged(planName: plan.name)
            } else {
                await NotificationService.postBackupFinished(planName: plan.name, summary: summary)
            }
            // Verification rides on the tail of a successful backup: the
            // destination is provably reachable and restic is already
            // serialized, so a due check can never fire a false alarm about
            // an unplugged drive or overlap another invocation.
            if let current = plans.first(where: { $0.id == plan.id }),
               CheckPolicy.isDue(current, now: Date()) {
                await performCheck(current, binaryURL: binaryURL)
            }
            // Retention rides the same tail, after any due check and only
            // when the repository didn't just fail verification — compacting
            // a repository restic reports as damaged could repack away the
            // redundant copies a repair needs.
            if let current = plans.first(where: { $0.id == plan.id }),
               PrunePolicy.isDue(current, now: Date()),
               current.lastCheck?.success != false {
                await performPrune(current, binaryURL: binaryURL)
            }
        } catch {
            let resticError = error as? ResticError
            let message = resticError?.localizedDescription ?? error.localizedDescription
            let record = BackupRunRecord(
                date: startedAt,
                success: false,
                // Only non-nil when restic stored a snapshot and *then* failed —
                // the exit-code-3 shape. An incomplete snapshot is a real point
                // in time that is missing files, so its id is what lets the
                // restore window warn instead of offering it as an ordinary one.
                snapshotID: summary?.snapshotID,
                errorMessage: message
            )
            await finishRun(plan, record: record)
            if case .someSourcesUnreadable(let paths, let total, let detail)? = resticError {
                runStates[plan.id] = .failedUnreadable(
                    paths: paths,
                    totalUnreadable: total,
                    message: detail
                )
            } else {
                runStates[plan.id] = resticError?.isRepositoryLocked == true
                    ? .failedLocked(message)
                    : .failed(message)
            }
            await NotificationService.postBackupFailed(planName: plan.name, message: message)
        }
    }

    private func finishRun(_ plan: BackupPlan, record: BackupRunRecord) async {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index].lastRun = record
        }
        try? await planStore.save(plans)
        try? await historyStore.append(record, planID: plan.id)
    }

    // MARK: - Repository checks

    /// The "Verify Backup Now" action. Scheduled checks don't come through
    /// here — they chain off `performBackup` so the destination is known
    /// reachable.
    func runCheck(_ plan: BackupPlan) {
        guard !isResticBusy else { return }
        guard let binaryURL = resticBinaryURL else {
            runStates[plan.id] = .failed(ResticError.binaryNotFound.localizedDescription)
            return
        }
        Task {
            await self.performCheck(plan, binaryURL: binaryURL)
        }
    }

    private func performCheck(_ plan: BackupPlan, binaryURL: URL) async {
        let stateBefore = runStates[plan.id] ?? .idle
        runStates[plan.id] = .checking
        let startedAt = Date()
        do {
            let credentials = try credentials(for: plan)
            let runner = ResticRunner(binaryURL: binaryURL)
            try await runner.runIgnoringOutput(
                .check,
                destination: plan.destination,
                credentials: credentials
            )
            await finishCheck(plan, record: CheckRunRecord(
                date: startedAt,
                success: true,
                duration: Date().timeIntervalSince(startedAt)
            ))
            runStates[plan.id] = stateBefore
            // Success is silent — the plan row's "Verified" line is enough.
        } catch {
            let message = (error as? ResticError)?.localizedDescription ?? error.localizedDescription
            await finishCheck(plan, record: CheckRunRecord(
                date: startedAt,
                success: false,
                duration: Date().timeIntervalSince(startedAt),
                errorMessage: message
            ))
            // Back to idle, not `stateBefore`: a post-backup `.succeeded`
            // would keep the health dot green while the persistent
            // failed-check line (read in the idle branch) must turn it red.
            runStates[plan.id] = .idle
            await NotificationService.postCheckFailed(planName: plan.name, message: message)
        }
    }

    private func finishCheck(_ plan: BackupPlan, record: CheckRunRecord) async {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index].lastCheck = record
        }
        try? await planStore.save(plans)
    }

    // MARK: - Preview (dry run)

    /// What a preview came back with. Deliberately not a `BackupRunRecord`:
    /// a dry run is not a run, and must never reach `lastRun`, the health
    /// dot, the check/prune chain or a "backup complete" notification
    /// (issue #43).
    enum PreviewOutcome {
        case summary(BackupSummary)
        case failed(String)
        /// restic was busy or missing, so nothing was attempted.
        case unavailable(String)
    }

    /// Runs `restic backup --dry-run` and hands the summary back to the
    /// caller, which shows it. Nothing here writes to the plan or the
    /// repository — the only lasting effect is the run state, which is put
    /// back exactly as it was found.
    func previewBackup(_ plan: BackupPlan) async -> PreviewOutcome {
        guard !isResticBusy else {
            return .unavailable(String(localized: "Another backup is running right now. Try again when it finishes."))
        }
        guard let binaryURL = resticBinaryURL else {
            return .unavailable(ResticError.binaryNotFound.localizedDescription)
        }

        let stateBefore = runStates[plan.id] ?? .idle
        runStates[plan.id] = .previewing(progress: nil)
        defer { runStates[plan.id] = stateBefore }

        do {
            let credentials = try credentials(for: plan)
            let runner = ResticRunner(binaryURL: binaryURL)
            let stream = runner.backupStream(
                .previewBackup(
                    sources: plan.sourcePaths,
                    excludes: plan.excludePatterns,
                    tag: "keelhaven",
                    performance: plan.performance,
                    options: plan.backupOptions
                ),
                destination: plan.destination,
                credentials: credentials
            )
            var summary: BackupSummary?
            for try await event in stream {
                switch event {
                case .status(let status):
                    runStates[plan.id] = .previewing(progress: Self.progress(from: status))
                case .summary(let value):
                    summary = value
                }
            }
            guard let summary else {
                return .failed(String(localized: "restic finished without reporting what it would back up."))
            }
            return .summary(summary)
        } catch {
            let message = (error as? ResticError)?.localizedDescription ?? error.localizedDescription
            return .failed(message)
        }
    }

    // MARK: - Repository locks

    /// Clears stale locks, then runs the backup they were blocking.
    ///
    /// Safe by construction: `restic unlock` (no `--remove-all`) removes only
    /// locks whose owner is gone, so another Mac genuinely mid-backup keeps
    /// its lock and its run. That also bounds what this can fix — against a
    /// live lock it succeeds and changes nothing, and the plan stays blocked
    /// until the other backup finishes, which is the correct outcome.
    ///
    /// The backup follows because clearing a lock is never the goal in
    /// itself; it also re-runs the retention pass, which is what the lock was
    /// really holding up.
    func unlockRepository(_ plan: BackupPlan) {
        guard !isResticBusy else { return }
        guard let binaryURL = resticBinaryURL else {
            runStates[plan.id] = .failed(ResticError.binaryNotFound.localizedDescription)
            return
        }
        runStates[plan.id] = .unlocking
        Task {
            do {
                let credentials = try credentials(for: plan)
                let runner = ResticRunner(binaryURL: binaryURL)
                try await runner.runIgnoringOutput(
                    .unlock,
                    destination: plan.destination,
                    credentials: credentials
                )
                runStates[plan.id] = .idle
                runBackup(plan)
            } catch {
                let resticError = error as? ResticError
                let message = resticError?.localizedDescription ?? error.localizedDescription
                // A lock that survives its own removal is not something the
                // button can fix twice — fall back to plain `failed` so the
                // row stops offering the same dead end.
                runStates[plan.id] = .failed(message)
            }
        }
    }

    // MARK: - Retention

    /// Scheduled-only, chained off `performBackup` like checks — there is no
    /// manual "prune now" action; enabling retention on an old plan makes the
    /// first pass due at the very next backup.
    private func performPrune(_ plan: BackupPlan, binaryURL: URL) async {
        let stateBefore = runStates[plan.id] ?? .idle
        runStates[plan.id] = .pruning
        let startedAt = Date()
        do {
            let credentials = try credentials(for: plan)
            let runner = ResticRunner(binaryURL: binaryURL)
            try await runner.runIgnoringOutput(
                .forget(retention: plan.retention, performance: plan.performance),
                destination: plan.destination,
                credentials: credentials
            )
            await finishPrune(plan, record: PruneRunRecord(
                date: startedAt,
                success: true,
                duration: Date().timeIntervalSince(startedAt)
            ))
            runStates[plan.id] = stateBefore
            // Success is silent — space quietly reclaimed is the feature.
        } catch {
            let resticError = error as? ResticError
            let message = resticError?.localizedDescription ?? error.localizedDescription
            let blockedByLock = resticError?.isRepositoryLocked == true
            await finishPrune(plan, record: PruneRunRecord(
                date: startedAt,
                success: false,
                duration: Date().timeIntervalSince(startedAt),
                errorMessage: message,
                blockedByLock: blockedByLock
            ))
            // Unlike a failed check, a failed prune keeps `stateBefore`: the
            // backups themselves are intact, only the cleanup is late — the
            // notification carries the details and the clock retries in a
            // week.
            //
            // A lock is the exception, and the reason `blockedByLock` exists.
            // `forget --prune` needs an exclusive lock, so one stale lock
            // blocks it every week from here on while backups keep succeeding
            // — a plan that looks healthy and quietly never reclaims a byte.
            // The row surfaces that one and offers the unlock; retrying on a
            // weekly timer would never have cleared it.
            runStates[plan.id] = stateBefore
            await NotificationService.postPruneFailed(planName: plan.name, message: message)
        }
    }

    private func finishPrune(_ plan: BackupPlan, record: PruneRunRecord) async {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index].lastPrune = record
        }
        try? await planStore.save(plans)
    }

    /// For the Touch ID–gated "Copy Repository Password" action only.
    /// Callers must authenticate via BiometricAuthService first.
    func repositoryPassword(for plan: BackupPlan) -> String? {
        try? keychain.secret(account: KeychainAccount.repositoryPassword(planID: plan.id))
    }

    // MARK: - Restore

    /// The plan the restore window operates on, set before opening it.
    var restorePlanID: UUID?

    /// Which plan the Edit Plan window is editing — same handoff as restore.
    var editPlanID: UUID?

    /// The plan a Duplicate window copies, set by the plan's Duplicate Plan…
    /// action before opening it — same handoff as editPlanID (issue #62).
    var duplicatePlanID: UUID?

    func restoreCredentials(for plan: BackupPlan) throws -> RepoCredentials {
        try credentials(for: plan)
    }

    /// The snapshot ids of runs that failed *after* restic stored something.
    ///
    /// Only exit code 3 leaves that particular trap: the repository holds a
    /// snapshot, it looks like every other point in time, and it is missing
    /// whatever restic could not read. A history file the app cannot read
    /// means no warnings rather than a restore window that refuses to open,
    /// so a decode failure is swallowed here.
    func incompleteSnapshotIDs(for planID: UUID) async -> Set<String> {
        let records = (try? await historyStore.history(for: planID)) ?? []
        return Set(records.filter { !$0.success }.compactMap(\.snapshotID))
    }

    private func credentials(for plan: BackupPlan) throws -> RepoCredentials {
        guard let password = try keychain.secret(
            account: KeychainAccount.repositoryPassword(planID: plan.id)
        ) else {
            throw ResticError.wrongPassword(message: "No password stored for this plan in the Keychain.")
        }
        var s3Secret: String?
        if case .s3 = plan.destination {
            s3Secret = try keychain.secret(account: KeychainAccount.s3SecretKey(planID: plan.id))
        }
        var restSecret: String?
        if case .rest = plan.destination {
            restSecret = try keychain.secret(account: KeychainAccount.restPassword(planID: plan.id))
        }
        return RepoCredentials(repositoryPassword: password, s3SecretAccessKey: s3Secret, restPassword: restSecret)
    }
}
