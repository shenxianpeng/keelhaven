import Foundation

/// Typed failures from the restic layer.
///
/// Exit codes verified against restic 0.19.1 (see Tests/…/Fixtures):
///   3 = some source files could not be read, 10 = repository does not exist,
///   11 = repository already locked (reproduced end to end in
///   ResticRunnerIntegrationTests, which races two real restic processes),
///   12 = wrong password.
public enum ResticError: Error, Equatable, Sendable {
    case binaryNotFound
    case repositoryDoesNotExist(message: String)
    case repositoryAlreadyExists(message: String)
    case repositoryLocked(message: String)
    case wrongPassword(message: String)
    /// restic exit code 3: the run is over and a snapshot may well have been
    /// written, but at least one source item could not be read.
    ///
    /// On macOS this is nearly always TCC rather than file permissions:
    /// `~/Desktop`, `~/Documents`, `~/Downloads`, iCloud Drive and the
    /// protected corners of `~/Library` are closed to any process the user
    /// has not granted access to. A command-line tool cannot ask for that
    /// access — the workaround is handing Full Disk Access to the terminal
    /// that runs it — so an app bundle is the shape that gets it granted
    /// without opening a much larger door. It is also the failure a
    /// first-time user is most likely to meet, because those are exactly the
    /// folders a person puts in their first plan.
    ///
    /// `paths` is capped at `maxReportedUnreadablePaths`, because a denied
    /// home folder produces one of these per file; `totalUnreadable` is the
    /// honest count. `message` is restic's own closing line, and is empty
    /// when Keelhaven reached this conclusion itself, before spawning restic.
    case someSourcesUnreadable(paths: [String], totalUnreadable: Int, message: String)
    case commandFailed(exitCode: Int, message: String)
    case outputDecodingFailed(message: String)

    /// Long enough to be useful in a tooltip, short enough that a denied
    /// home folder cannot hand the UI a hundred thousand paths.
    public static let maxReportedUnreadablePaths = 20

    /// True for a failure the app can offer a way out of. Two things produce
    /// it: a stale lock from an interrupted run, which `unlock` clears, and a
    /// live lock from another machine backing up to the same repository,
    /// which simply needs waiting out. Everything else needs the user to
    /// change something.
    public var isRepositoryLocked: Bool {
        if case .repositoryLocked = self { return true }
        return false
    }

    public static func classify(exitCode: Int32, stderr: String) -> ResticError {
        // restic ≥0.17 writes a {"message_type":"exit_error","code":…,"message":…}
        // JSON line to stderr; prefer its message over raw stderr.
        var message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in stderr.split(separator: "\n").reversed() {
            if let data = line.data(using: .utf8),
               let exitError = try? ResticJSON.decoder.decode(ResticExitError.self, from: data) {
                message = exitError.message
                break
            }
        }
        // restic sometimes stacks "Fatal: Fatal: …"; our own descriptions
        // provide the framing, so drop the prefixes entirely.
        while message.hasPrefix("Fatal: ") {
            message = String(message.dropFirst("Fatal: ".count))
        }

        switch exitCode {
        case 3:
            // The per-file lines live alongside the exit_error line on the
            // same stderr stream, and are the whole reason this is a case of
            // its own: "at least one source file could not be read" without
            // the names is not something a person can act on.
            let items = ResticJSON.unreadableItems(inStderr: stderr)
            return .someSourcesUnreadable(
                paths: Array(items.prefix(maxReportedUnreadablePaths)),
                totalUnreadable: items.count,
                message: message
            )
        case 10:
            return .repositoryDoesNotExist(message: message)
        case 11:
            return .repositoryLocked(message: message)
        case 12:
            return .wrongPassword(message: message)
        default:
            // `restic init` against a non-empty destination; only generic
            // exit code 1 exists for this, so match on the message.
            if message.contains("config file already exists") {
                return .repositoryAlreadyExists(message: message)
            }
            return .commandFailed(exitCode: Int(exitCode), message: message)
        }
    }
}

extension ResticError: LocalizedError {
    // Note: the interpolated `message` payloads are raw restic output and
    // stay English; only Keelhaven's framing sentences localize.
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return String(localized: "Keelhaven's backup engine is missing from the app. Reinstalling Keelhaven from keelhaven.app restores it.", bundle: .module)
        case .repositoryDoesNotExist(let message):
            return String(localized: "The backup repository was not found. \(message)", bundle: .module)
        case .repositoryAlreadyExists:
            return String(localized: "This destination already contains a backup repository. Each plan needs its own empty destination folder.", bundle: .module)
        case .repositoryLocked(let message):
            return String(localized: "The backup repository is locked by another process. \(message)", bundle: .module)
        case .wrongPassword(let message):
            return String(localized: "The repository password is incorrect. \(message)", bundle: .module)
        case .someSourcesUnreadable:
            // Deliberately does not interpolate restic's "at least one source
            // file could not be read": it names no file, and the count and the
            // names are carried separately, in `paths` / `totalUnreadable`,
            // where the row can lay them out. This sentence is what survives
            // into the run record and the notification, so it has to carry the
            // one thing restic never says — how to fix it.
            return String(localized: "Keelhaven could not read some of the files in this plan's folders. Open System Settings › Privacy & Security › Full Disk Access, turn on Keelhaven, then run the backup again.", bundle: .module)
        case .commandFailed(let exitCode, let message):
            return String(localized: "Backup command failed (exit code \(exitCode)). \(message)", bundle: .module)
        case .outputDecodingFailed(let message):
            return String(localized: "Could not understand restic's output. \(message)", bundle: .module)
        }
    }
}
