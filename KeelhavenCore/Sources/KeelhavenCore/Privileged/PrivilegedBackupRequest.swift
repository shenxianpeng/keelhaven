import Foundation

/// One backup (or preview) the app hands the privileged helper, as data.
///
/// Carries the secrets the helper needs to open the repository, because the
/// helper runs as root and cannot read the user's Keychain. They travel over
/// the XPC connection — never argv, never disk — and reach restic through its
/// environment, exactly as they do for a user-level run.
///
/// Who is asking is deliberately *not* in here: the helper takes the user from
/// the connection's audit token, which the caller cannot forge.
public struct PrivilegedBackupRequest: Codable, Equatable, Sendable {
    public var sources: [String]
    public var excludes: [String]
    public var performance: PerformanceOptions
    public var options: BackupOptions
    /// A `--dry-run` preview rather than a backup.
    public var isPreview: Bool
    public var destination: Destination
    public var repositoryPassword: String
    public var s3SecretAccessKey: String?
    public var restPassword: String?
    /// The user's ssh agent, so an SFTP destination authenticates exactly
    /// as it does when the app runs restic itself.
    public var sshAuthSocket: String?

    public init(plan: BackupPlan, credentials: RepoCredentials, isPreview: Bool, sshAuthSocket: String?) {
        sources = plan.sourcePaths
        excludes = plan.excludePatterns
        performance = plan.performance
        options = plan.backupOptions
        self.isPreview = isPreview
        destination = plan.destination
        repositoryPassword = credentials.repositoryPassword
        s3SecretAccessKey = credentials.s3SecretAccessKey
        restPassword = credentials.restPassword
        self.sshAuthSocket = sshAuthSocket
    }

    /// The restic command this request stands for. Built here, from the
    /// same `ResticCommand` cases a user-level run uses, so the two can
    /// never drift apart — and so the tag is always Keelhaven's own, which
    /// retention depends on.
    public var command: ResticCommand {
        isPreview
            ? .previewBackup(sources: sources, excludes: excludes, tag: ResticCommand.snapshotTag, performance: performance, options: options)
            : .backup(sources: sources, excludes: excludes, tag: ResticCommand.snapshotTag, performance: performance, options: options)
    }

    public var credentials: RepoCredentials {
        RepoCredentials(
            repositoryPassword: repositoryPassword,
            s3SecretAccessKey: s3SecretAccessKey,
            restPassword: restPassword
        )
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decodes and validates in one step, so the helper can never act on a
    /// request it has not checked.
    public static func decoded(from data: Data) throws -> PrivilegedBackupRequest {
        let request: PrivilegedBackupRequest
        do {
            request = try JSONDecoder().decode(PrivilegedBackupRequest.self, from: data)
        } catch {
            throw PrivilegedBackupError.invalidRequest("unreadable request")
        }
        try request.validate()
        return request
    }

    /// The checks that do not depend on who is asking: something to back
    /// up, every source an absolute path, and no NUL anywhere — a path with
    /// one in it would be cut short by the C APIs below restic.
    public func validate() throws {
        guard !sources.isEmpty else {
            throw PrivilegedBackupError.invalidRequest("no folders to back up")
        }
        for source in sources where !source.hasPrefix("/") {
            throw PrivilegedBackupError.invalidRequest("not an absolute path: \(source)")
        }
        let strings = sources + excludes + [destination.repositoryLocation, sshAuthSocket ?? ""]
        if strings.contains(where: { $0.contains("\0") }) {
            throw PrivilegedBackupError.invalidRequest("a path contains a NUL character")
        }
    }
}

/// Why the helper could not run restic for a request. Codable because it is
/// the helper's half of the reply: the app decodes it and puts it into words.
public enum PrivilegedBackupError: Error, Equatable, Codable {
    case invalidRequest(String)
    /// A value that cannot be quoted safely into restic's `sftp.command`.
    case unquotableSSHArgument(String)
    /// The bundled restic is missing, or its signature does not match the
    /// helper's own team — the helper will not run it as root.
    case resticUnavailable
    /// Anything else on the helper's side, described for a bug report.
    case helperFault(String)
}

extension PrivilegedBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return String(localized: "The administrator helper refused the backup: \(reason).", bundle: .module)
        case .unquotableSSHArgument(let value):
            return String(localized: "The SFTP settings contain a character the administrator helper cannot pass to ssh: \(value)", bundle: .module)
        case .resticUnavailable:
            return String(localized: "The administrator helper could not verify Keelhaven's backup engine, so it did not run it. Reinstalling Keelhaven restores it.", bundle: .module)
        case .helperFault(let reason):
            return String(localized: "The administrator helper could not run the backup: \(reason)", bundle: .module)
        }
    }
}
