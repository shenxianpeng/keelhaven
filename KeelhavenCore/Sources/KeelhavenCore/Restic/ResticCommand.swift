import Foundation

/// A restic subcommand plus its arguments. The repository location and all
/// secrets travel via environment variables, never argv (argv is visible to
/// every process on the machine).
public enum ResticCommand: Equatable, Sendable {
    case initRepository
    case backup(sources: [String], excludes: [String], tag: String?, performance: PerformanceOptions)
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
    /// Restores a whole snapshot into the target folder.
    case restore(snapshotID: String, target: String)
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
        case .backup(let sources, let excludes, let tag, let performance):
            var args = ["backup", "--json"]
            args.append(contentsOf: performance.arguments(includingReadConcurrency: true))
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
        case .restore(let snapshotID, let target):
            return ["restore", snapshotID, "--target", target, "--json"]
        case .unlock:
            return ["unlock"]
        }
    }
}
