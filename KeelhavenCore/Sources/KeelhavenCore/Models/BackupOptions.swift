import Foundation

/// Boolean switches handed to `restic backup`. Both are `false` by default,
/// which leaves the command line exactly as it was before this type existed.
///
/// Separate from `PerformanceOptions` on purpose: that type is scoped, in its
/// own doc comment, to throughput knobs, and all three of its fields are
/// `Int?`. These change *what gets backed up* and *whether a snapshot is
/// written* — different question, different type (issue #46).
///
/// Every field here must be a flag that leaves restic's `--json` event stream
/// intact, since the progress UI and every run record are parsed from it.
/// `--no-scan` is the counter-example and is deliberately not here: it holds
/// `percent_done` at 0 for the whole run (issue #51).
public struct BackupOptions: Codable, Hashable, Sendable {
    /// `--exclude-caches`: skip directories tagged with `CACHEDIR.TAG`.
    public var excludeCaches: Bool
    /// `--one-file-system`: stop at the boundary of the disk each source
    /// folder lives on, instead of following into anything mounted below it.
    ///
    /// Picking a folder is a directory choice, but what gets read is whatever
    /// is *mounted* underneath — on a Mac routinely an external drive or a
    /// network share sitting inside the source tree (issue #50).
    public var oneFileSystem: Bool
    /// `--skip-if-unchanged`: write no snapshot when the content is identical
    /// to the parent snapshot.
    ///
    /// Callers must handle the consequence: restic then omits `snapshot_id`
    /// from its summary, and reporting that run as an ordinary success would
    /// tell someone a backup was stored when none was.
    public var skipIfUnchanged: Bool

    /// Every switch off — restic's own behaviour.
    public static let off = BackupOptions()

    public init(
        excludeCaches: Bool = false,
        oneFileSystem: Bool = false,
        skipIfUnchanged: Bool = false
    ) {
        self.excludeCaches = excludeCaches
        self.oneFileSystem = oneFileSystem
        self.skipIfUnchanged = skipIfUnchanged
    }

    /// Each field decoded independently with a `false` fallback, so a
    /// `plans.json` written before any one of them existed still loads. The
    /// whole-struct fallback lives in `BackupPlan.init(from:)`; this is the
    /// per-field one, and it is what lets a fourth switch be added later
    /// without a migration. (`encode(to:)` and `CodingKeys` stay synthesized.)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            excludeCaches: try container.decodeIfPresent(Bool.self, forKey: .excludeCaches) ?? false,
            oneFileSystem: try container.decodeIfPresent(Bool.self, forKey: .oneFileSystem) ?? false,
            skipIfUnchanged: try container.decodeIfPresent(Bool.self, forKey: .skipIfUnchanged) ?? false
        )
    }

    /// True when restic is left entirely to its own behaviour.
    public var isDefault: Bool {
        !excludeCaches && !oneFileSystem && !skipIfUnchanged
    }

    /// The flags for this configuration, empty when nothing is set.
    /// Both belong to `backup` alone — restic exits with a usage error if
    /// either appears on `forget`, which is why there is no
    /// `includingX:`-style parameter here the way `PerformanceOptions` needs.
    public var arguments: [String] {
        var args: [String] = []
        if excludeCaches {
            args.append("--exclude-caches")
        }
        // Next to `--exclude-caches` because it is the same kind of thing —
        // a rule about what not to read — and the UI groups them together.
        if oneFileSystem {
            args.append("--one-file-system")
        }
        if skipIfUnchanged {
            args.append("--skip-if-unchanged")
        }
        return args
    }
}
