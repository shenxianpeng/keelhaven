import Foundation

/// The account a privileged backup is run on behalf of, as the helper found
/// it from the connection — never as the app described it.
public struct RequestingUser: Equatable, Sendable {
    public let uid: UInt32
    public let gid: UInt32
    public let name: String
    public let home: String

    public init(uid: UInt32, gid: UInt32, name: String, home: String) {
        self.uid = uid
        self.gid = gid
        self.name = name
        self.home = home
    }
}

/// Exactly what the helper executes for one request: restic's arguments and
/// its complete environment.
///
/// restic runs as root so it can *read* everything; what it *writes to* has to
/// keep working as the user afterwards, because restore, check and retention
/// all stay in the app. Per destination:
///
/// - **S3 / REST**: network only. Nothing changes except that root gets a
///   cache of its own (`RESTIC_CACHE_DIR`), so it never writes into the
///   user's.
/// - **SFTP**: root's ssh has none of the user's keys, agent, config or
///   known_hosts. So only the ssh transport runs as the user — through
///   `sftp.command`, which this type builds — while restic stays root.
/// - **Local / mounted share**: restic writes the repository as root. On an
///   SMB share the server keeps the files the user's; on a local disk the
///   helper hands them back afterwards (`RepositoryOwnership`).
public struct PrivilegedInvocation: Equatable, Sendable {
    public let arguments: [String]
    public let environment: [String: String]

    public init(request: PrivilegedBackupRequest, user: RequestingUser, cacheDirectory: String) throws {
        var arguments = request.command.arguments
        if case .sftp(let config) = request.destination {
            let option = try Self.sftpCommandOption(config: config, user: user, sshAuthSocket: request.sshAuthSocket)
            arguments = ["-o", option] + arguments
        }
        self.arguments = arguments

        // Root's own environment is a launchd daemon's: nothing restic should
        // inherit. HOME points at root's home so nothing lands in the user's.
        let base = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/var/root",
            "RESTIC_CACHE_DIR": cacheDirectory,
        ]
        environment = request.credentials.environment(for: request.destination, base: base)
    }

    /// `-o sftp.command=…`: the ssh restic would have started, run as the
    /// user instead of root.
    ///
    /// `launchctl asuser` puts ssh in the user's login session, where their
    /// Keychain-held key passphrases are reachable; `sudo -n -u` drops it to
    /// their account (root needs no password for that, and `-n` makes sure
    /// it never waits for one). The agent socket comes from the app,
    /// because a daemon has no agent of its own. `--` keeps a host name from
    /// ever being read as an ssh option.
    ///
    /// Two layers of quoting, both verified against restic 0.19.1: restic
    /// splits the command into words, honouring double quotes; and before
    /// that, `-o` values are read as CSV, so the whole value is wrapped in
    /// quotes with its own quotes doubled. Neither layer has an escape for
    /// a quote *inside* a word, so a value containing one is refused rather
    /// than guessed at — no real user, host or path needs one.
    static func sftpCommandOption(config: SFTPConfig, user: RequestingUser, sshAuthSocket: String?) throws -> String {
        var words = [
            "/bin/launchctl", "asuser", String(user.uid),
            "/usr/bin/sudo", "-n", "-u", user.name,
            "/usr/bin/env", "HOME=\(user.home)",
        ]
        if let sshAuthSocket {
            words.append("SSH_AUTH_SOCK=\(sshAuthSocket)")
        }
        words += ["/usr/bin/ssh", "-p", String(config.port), "-l", config.user, "-s", "--", config.host, "sftp"]
        return try sftpCommandOption(words: words)
    }

    /// The quoting on its own, so a test can hand restic arbitrary words.
    static func sftpCommandOption(words: [String]) throws -> String {
        for word in words where word.contains("\"") || word.contains("\n") {
            throw PrivilegedBackupError.unquotableSSHArgument(word)
        }
        let command = words.map { "\"\($0)\"" }.joined(separator: " ")
        let value = "sftp.command=" + command
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
