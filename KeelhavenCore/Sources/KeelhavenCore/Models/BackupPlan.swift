import Foundation

/// A configured backup: what to back up, where to, and when.
/// Secrets (repository password, S3 secret key) are stored in the Keychain,
/// keyed by this plan's `id` — never in this struct.
public struct BackupPlan: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Absolute paths of the folders to back up.
    public var sourcePaths: [String]
    public var destination: Destination
    public var schedule: Schedule
    public var excludePatterns: [String]
    public var checkCadence: CheckCadence
    public var retention: RetentionPolicy
    /// restic throughput knobs, all off by default. See `PerformanceOptions`.
    public var performance: PerformanceOptions
    /// Boolean `restic backup` switches, both off by default. See `BackupOptions`.
    public var backupOptions: BackupOptions
    /// Whether the very first backup starts the moment the plan is created,
    /// rather than waiting for the first scheduled time after `createdAt`.
    ///
    /// Persisted rather than kept in the wizard, because the alternative does
    /// not survive a relaunch: `SchedulePolicy` is asked once a minute and at
    /// every launch, so a plan that only *skipped* its creation-time run would
    /// be started by the very next tick (issue #42). Only consulted while
    /// `lastRun` is nil; after the first run the schedule anchors there.
    public var firstBackupStartsOnCreation: Bool
    public var createdAt: Date
    public var lastRun: BackupRunRecord?
    public var lastCheck: CheckRunRecord?
    public var lastPrune: PruneRunRecord?

    public static let defaultExcludePatterns: [String] = [
        ".DS_Store",
        ".Trash",
        "node_modules",
        "*.tmp",
    ]

    public init(
        id: UUID = UUID(),
        name: String,
        sourcePaths: [String],
        destination: Destination,
        schedule: Schedule,
        excludePatterns: [String] = BackupPlan.defaultExcludePatterns,
        checkCadence: CheckCadence = .weekly,
        retention: RetentionPolicy = .off,
        performance: PerformanceOptions = .off,
        backupOptions: BackupOptions = .off,
        firstBackupStartsOnCreation: Bool = true,
        createdAt: Date = Date(),
        lastRun: BackupRunRecord? = nil,
        lastCheck: CheckRunRecord? = nil,
        lastPrune: PruneRunRecord? = nil
    ) {
        self.id = id
        self.name = name
        self.sourcePaths = sourcePaths
        self.destination = destination
        self.schedule = schedule
        self.excludePatterns = excludePatterns
        self.checkCadence = checkCadence
        self.retention = retention
        self.performance = performance
        self.backupOptions = backupOptions
        self.firstBackupStartsOnCreation = firstBackupStartsOnCreation
        self.createdAt = createdAt
        self.lastRun = lastRun
        self.lastCheck = lastCheck
        self.lastPrune = lastPrune
    }

    /// Plans saved before scheduled checks, retention or the performance
    /// knobs existed lack those keys — decode them leniently so an upgrade
    /// can never lose the plan list. (`encode(to:)` and `CodingKeys` stay
    /// synthesized.)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourcePaths = try container.decode([String].self, forKey: .sourcePaths)
        destination = try container.decode(Destination.self, forKey: .destination)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        excludePatterns = try container.decode([String].self, forKey: .excludePatterns)
        checkCadence = try container.decodeIfPresent(CheckCadence.self, forKey: .checkCadence) ?? .weekly
        // `try?`, unlike its neighbours: retention is the one field whose
        // set of valid values can grow (issue #52 added `last:N`), so a plan
        // written by a newer build must degrade to "keep everything" here
        // rather than take the whole plan list down with it. Falling back to
        // `.off` is the safe direction — it never deletes anything.
        retention = (try? container.decodeIfPresent(RetentionPolicy.self, forKey: .retention)) ?? .off
        performance = try container.decodeIfPresent(PerformanceOptions.self, forKey: .performance) ?? .off
        backupOptions = try container.decodeIfPresent(BackupOptions.self, forKey: .backupOptions) ?? .off
        // Absent on every plan written before this flag existed — and those
        // all started their first backup on creation, so `true` is the value
        // that keeps them behaving exactly as they did.
        firstBackupStartsOnCreation = try container.decodeIfPresent(Bool.self, forKey: .firstBackupStartsOnCreation) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastRun = try container.decodeIfPresent(BackupRunRecord.self, forKey: .lastRun)
        lastCheck = try container.decodeIfPresent(CheckRunRecord.self, forKey: .lastCheck)
        lastPrune = try container.decodeIfPresent(PruneRunRecord.self, forKey: .lastPrune)
    }
}
