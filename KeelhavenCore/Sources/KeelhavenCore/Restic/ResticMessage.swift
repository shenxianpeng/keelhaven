import Foundation

/// Minimal envelope used to dispatch a restic `--json` line to its concrete type.
public struct ResticMessageEnvelope: Decodable {
    public let messageType: String

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
    }
}

/// `restic init --json` output.
public struct ResticInitResult: Decodable, Sendable {
    public let messageType: String
    public let id: String
    public let repository: String

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case id
        case repository
    }
}

/// A `message_type: "status"` line from `restic backup --json`.
/// Every field except `percentDone` was observed to be absent in at least
/// one captured line, so they are all optional.
public struct BackupStatusMessage: Decodable, Sendable {
    public let percentDone: Double
    public let totalFiles: Int?
    public let filesDone: Int?
    public let totalBytes: Int64?
    public let bytesDone: Int64?
    public let secondsRemaining: Int?
    public let currentFiles: [String]?

    enum CodingKeys: String, CodingKey {
        case percentDone = "percent_done"
        case totalFiles = "total_files"
        case filesDone = "files_done"
        case totalBytes = "total_bytes"
        case bytesDone = "bytes_done"
        case secondsRemaining = "seconds_remaining"
        case currentFiles = "current_files"
    }
}

/// The `message_type: "summary"` line from `restic backup --json`, and the
/// nested `summary` object inside `restic snapshots --json` entries. The
/// nested form lacks `total_duration` and `snapshot_id`, hence those are optional.
public struct BackupSummary: Decodable, Sendable {
    public let filesNew: Int
    public let filesChanged: Int
    public let filesUnmodified: Int
    public let dirsNew: Int?
    public let dirsChanged: Int?
    public let dirsUnmodified: Int?
    public let dataAdded: Int64?
    public let dataAddedPacked: Int64?
    public let totalFilesProcessed: Int?
    public let totalBytesProcessed: Int64?
    public let totalDuration: Double?
    public let backupStart: Date?
    public let backupEnd: Date?
    public let snapshotID: String?
    /// `true` on the summary of a `--dry-run` backup. Absent otherwise.
    ///
    /// Note that a dry run still reports a `snapshot_id` — one is computed
    /// and thrown away — so this is the only field that distinguishes a
    /// preview's summary from a real backup's (issue #43).
    public let dryRun: Bool?

    enum CodingKeys: String, CodingKey {
        case filesNew = "files_new"
        case filesChanged = "files_changed"
        case filesUnmodified = "files_unmodified"
        case dirsNew = "dirs_new"
        case dirsChanged = "dirs_changed"
        case dirsUnmodified = "dirs_unmodified"
        case dataAdded = "data_added"
        case dataAddedPacked = "data_added_packed"
        case totalFilesProcessed = "total_files_processed"
        case totalBytesProcessed = "total_bytes_processed"
        case totalDuration = "total_duration"
        case backupStart = "backup_start"
        case backupEnd = "backup_end"
        case snapshotID = "snapshot_id"
        case dryRun = "dry_run"
    }
}

/// One entry of `restic snapshots --json`.
public struct ResticSnapshot: Decodable, Identifiable, Sendable {
    public let id: String
    public let shortID: String?
    public let time: Date
    public let parent: String?
    public let tree: String?
    public let paths: [String]
    public let hostname: String?
    public let username: String?
    public let programVersion: String?
    public let summary: BackupSummary?

    enum CodingKeys: String, CodingKey {
        case id
        case shortID = "short_id"
        case time
        case parent
        case tree
        case paths
        case hostname
        case username
        case programVersion = "program_version"
        case summary
    }
}

/// A `message_type: "status"` line from `restic restore --json`.
public struct RestoreStatusMessage: Decodable, Sendable {
    public let percentDone: Double
    public let totalFiles: Int?
    public let filesRestored: Int?
    public let totalBytes: Int64?
    public let bytesRestored: Int64?
    public let secondsRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case percentDone = "percent_done"
        case totalFiles = "total_files"
        case filesRestored = "files_restored"
        case totalBytes = "total_bytes"
        case bytesRestored = "bytes_restored"
        case secondsRemaining = "seconds_remaining"
    }
}

/// The final `message_type: "summary"` line from `restic restore --json`.
/// Note: `total_files` counts directories too, not just files.
public struct RestoreSummary: Decodable, Sendable {
    public let totalFiles: Int?
    public let filesRestored: Int
    public let totalBytes: Int64?
    public let bytesRestored: Int64?

    enum CodingKeys: String, CodingKey {
        case totalFiles = "total_files"
        case filesRestored = "files_restored"
        case totalBytes = "total_bytes"
        case bytesRestored = "bytes_restored"
    }
}

/// A decoded event from the `restic restore --json` stream.
public enum RestoreProgressEvent: Sendable {
    case status(RestoreStatusMessage)
    case summary(RestoreSummary)
}

/// `restic cat config --json` output — decoding it successfully proves the
/// supplied password opens the repository.
public struct ResticRepoConfig: Decodable, Sendable {
    public let version: Int
    public let id: String

    enum CodingKeys: String, CodingKey {
        case version
        case id
    }
}

/// `restic stats --json` output.
public struct ResticStats: Decodable, Sendable {
    public let totalSize: Int64
    public let totalFileCount: Int
    public let snapshotsCount: Int

    enum CodingKeys: String, CodingKey {
        case totalSize = "total_size"
        case totalFileCount = "total_file_count"
        case snapshotsCount = "snapshots_count"
    }
}

/// The `message_type: "exit_error"` JSON line restic ≥0.17 writes to stderr on fatal errors.
public struct ResticExitError: Decodable, Sendable {
    public let code: Int
    public let message: String

    enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

/// A decoded event from the `restic backup --json` stream.
public enum BackupProgressEvent: Sendable {
    case status(BackupStatusMessage)
    case summary(BackupSummary)
}

/// Shared JSON decoding configuration for restic output.
public enum ResticJSON {
    /// restic emits ISO 8601 timestamps with fractional seconds and a zone
    /// offset (e.g. "2026-08-14T22:20:53.835558+03:00"), which the stock
    /// `.iso8601` strategy cannot parse.
    public static let decoder: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized restic date: \(string)"
            )
        }
        return decoder
    }()

    /// Decode one line of the `restic restore --json` stream.
    /// Returns nil for lines that are not progress events.
    public static func decodeRestoreEvent(fromLine line: String) -> RestoreProgressEvent? {
        guard let data = line.data(using: .utf8),
              let envelope = try? decoder.decode(ResticMessageEnvelope.self, from: data)
        else { return nil }

        switch envelope.messageType {
        case "status":
            return (try? decoder.decode(RestoreStatusMessage.self, from: data)).map { .status($0) }
        case "summary":
            return (try? decoder.decode(RestoreSummary.self, from: data)).map { .summary($0) }
        default:
            return nil
        }
    }

    /// Decode one line of the `restic backup --json` stream.
    /// Returns nil for lines that are not progress events (e.g. verbose messages).
    public static func decodeProgressEvent(fromLine line: String) -> BackupProgressEvent? {
        guard let data = line.data(using: .utf8),
              let envelope = try? decoder.decode(ResticMessageEnvelope.self, from: data)
        else { return nil }

        switch envelope.messageType {
        case "status":
            return (try? decoder.decode(BackupStatusMessage.self, from: data)).map { .status($0) }
        case "summary":
            return (try? decoder.decode(BackupSummary.self, from: data)).map { .summary($0) }
        default:
            return nil
        }
    }
}
