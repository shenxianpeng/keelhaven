import Foundation

/// A restic subcommand plus its arguments. The repository location and all
/// secrets travel via environment variables, never argv (argv is visible to
/// every process on the machine).
public enum ResticCommand: Equatable, Sendable {
    case initRepository
    case backup(sources: [String], excludes: [String], tag: String?, performance: PerformanceOptions, options: BackupOptions)
    /// Everything `backup` does except the writing: restic walks the sources,
    /// reports what it would store, and leaves the repository untouched
    /// (issue #43).
    ///
    /// A separate case rather than a flag on `backup`, because it is a
    /// different intent, not a plan setting — nothing about a preview should
    /// ever be persisted, and no call site that means "back up" can reach it
    /// by getting a boolean wrong.
    case previewBackup(sources: [String], excludes: [String], tag: String?, performance: PerformanceOptions, options: BackupOptions)
    case snapshots
    case stats
    case check
    /// Applies a retention policy and compacts the repository
    /// (`forget --prune`). No `--json`: the output is progress text we don't
    /// parse — the exit code decides, exactly like `check`.
    /// `--read-concurrency` is deliberately not passed on: it is a `backup`
    /// flag, and restic exits with a usage error when it appears here.
    case forget(retention: RetentionPolicy, performance: PerformanceOptions)
    /// Reads the repository config — the cheapest command that proves a
    /// password opens an existing repository (used when adopting one).
    case catConfig
    /// Lists a snapshot's contents: the snapshot header, then one node per
    /// entry, in the order restic walked it (issue #61).
    ///
    /// One call for the whole snapshot rather than one per directory. That is
    /// a measured decision, not a preference: see `SnapshotTree`.
    case ls(snapshotID: String)
    /// Restores a snapshot into the target folder.
    ///
    /// `includes` narrows the restore to selected paths — absolute, exactly as
    /// `ls` reports them (verified against restic 0.19.1: an included file
    /// lands alone under the target, an included directory lands with its
    /// subtree). An empty list restores the whole snapshot, the way this
    /// command behaved before the list existed.
    case restore(snapshotID: String, target: String, includes: [String])
    /// Clears stale locks so retention passes can run again.
    ///
    /// Deliberately without `--remove-all`. Verified against restic 0.19.1:
    /// the plain command removes only locks whose owning process is gone,
    /// and leaves a lock another machine is actively holding exactly where it
    /// is — so it can never cut short a backup running elsewhere against the
    /// same repository. `--remove-all` does tear those out, which is why it
    /// stays out of the app entirely.
    case unlock

    public var arguments: [String] {
        switch self {
        case .initRepository:
            return ["init", "--json"]
        case .backup(let sources, let excludes, let tag, let performance, let options):
            return Self.backupArguments(
                dryRun: false, sources: sources, excludes: excludes,
                tag: tag, performance: performance, options: options
            )
        case .previewBackup(let sources, let excludes, let tag, let performance, let options):
            return Self.backupArguments(
                dryRun: true, sources: sources, excludes: excludes,
                tag: tag, performance: performance, options: options
            )
        case .snapshots:
            return ["snapshots", "--json"]
        case .stats:
            return ["stats", "--json"]
        case .check:
            return ["check"]
        case .forget(let retention, let performance):
            // A prune rewrites and re-uploads pack files, so the upload cap
            // and pack size matter here for the same reasons they do during
            // a backup.
            return ["forget", "--prune"]
                + performance.arguments(includingReadConcurrency: false)
                + retention.keepArguments
        case .catConfig:
            return ["cat", "config", "--json"]
        case .ls(let snapshotID):
            return ["ls", snapshotID, "--json"]
        case .restore(let snapshotID, let target, let includes):
            return ["restore", snapshotID, "--target", target, "--json"]
                + includes.flatMap { ["--include", $0] }
        case .unlock:
            return ["unlock"]
        }
    }

    /// One place that knows the shape of a backup command line, so a preview
    /// can never drift from the real thing in excludes, tag or throughput —
    /// which would make it a preview of a backup nobody is going to run.
    private static func backupArguments(
        dryRun: Bool,
        sources: [String],
        excludes: [String],
        tag: String?,
        performance: PerformanceOptions,
        options: BackupOptions
    ) -> [String] {
        var args = ["backup", "--json"]
        if dryRun {
            args.append("--dry-run")
        }
        args.append(contentsOf: performance.arguments(includingReadConcurrency: true))
        args.append(contentsOf: options.arguments)
        for pattern in excludes {
            args.append("--exclude")
            args.append(pattern)
        }
        if let tag, !tag.isEmpty {
            args.append("--tag")
            args.append(tag)
        }
        args.append(contentsOf: sources)
        return args
    }
}
