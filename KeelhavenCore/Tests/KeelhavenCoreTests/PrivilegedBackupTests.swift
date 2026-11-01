import XCTest
@testable import KeelhavenCore

/// The pieces of the privileged helper that need no root and no daemon: the
/// request the app sends, the command line the helper builds from it, and the
/// code requirement each side checks the other against.
final class PrivilegedBackupTests: XCTestCase {
    private let user = RequestingUser(uid: 501, gid: 20, name: "matt", home: "/Users/matt")
    private let cache = "/Library/Caches/Keelhaven/Helper/501"

    private func plan(_ destination: Destination) -> BackupPlan {
        BackupPlan(
            name: "System",
            sourcePaths: ["/etc", "/Library/Preferences"],
            destination: destination,
            schedule: .hourly,
            performance: PerformanceOptions(uploadLimitKiBPerSecond: 500),
            backupOptions: BackupOptions(oneFileSystem: true, readsAsAdministrator: true)
        )
    }

    private func request(
        _ destination: Destination,
        isPreview: Bool = false,
        sshAuthSocket: String? = nil
    ) -> PrivilegedBackupRequest {
        PrivilegedBackupRequest(
            plan: plan(destination),
            credentials: RepoCredentials(repositoryPassword: "pw", s3SecretAccessKey: "secret", restPassword: "rest-pw"),
            isPreview: isPreview,
            sshAuthSocket: sshAuthSocket
        )
    }

    // MARK: - Code requirement

    func testRequirementPinsIdentifierAndTeam() {
        XCTAssertEqual(
            PrivilegedHelper.codeSigningRequirement(identifier: PrivilegedHelper.appIdentifier, teamID: "849VGKLAH8"),
            "anchor apple generic and identifier \"com.keelhaven.Keelhaven\" and certificate leaf[subject.OU] = \"849VGKLAH8\""
        )
    }

    /// An ad-hoc build has no team, and a malformed one must never be pasted
    /// into a requirement — either way, no helper rather than a weak one.
    func testNoRequirementWithoutAWellFormedTeam() {
        for team in [nil, "", "849VGKLAH", "849vgklah8", "849VGKLAH8\" or true", "ABCDEFGHIJK"] as [String?] {
            XCTAssertNil(PrivilegedHelper.codeSigningRequirement(identifier: "x", teamID: team), "\(String(describing: team))")
        }
    }

    func testSharedNamesAgree() {
        XCTAssertEqual(PrivilegedHelper.launchDaemonPlistName, PrivilegedHelper.machServiceName + ".plist")
        XCTAssertEqual(PrivilegedHelper.helperIdentifier, PrivilegedHelper.machServiceName)
        XCTAssertEqual(PrivilegedHelper.resticIdentifier, "restic")
    }

    // MARK: - Request

    func testRequestBuildsTheSameCommandAUserRunWould() {
        let plan = plan(.local(path: "/Volumes/Backup/repo"))
        let backup = request(.local(path: "/Volumes/Backup/repo"))
        XCTAssertEqual(backup.command, .backup(
            sources: plan.sourcePaths, excludes: plan.excludePatterns, tag: ResticCommand.snapshotTag,
            performance: plan.performance, options: plan.backupOptions
        ))
        let preview = request(.local(path: "/Volumes/Backup/repo"), isPreview: true)
        XCTAssertEqual(preview.command, .previewBackup(
            sources: plan.sourcePaths, excludes: plan.excludePatterns, tag: ResticCommand.snapshotTag,
            performance: plan.performance, options: plan.backupOptions
        ))
        XCTAssertFalse(preview.command.arguments.contains("--read-as-administrator"),
                       "readsAsAdministrator must never reach restic's argv")
    }

    func testRequestRoundTripsThroughData() throws {
        let original = request(.s3(S3Config(endpoint: "s3.example.com", bucket: "b", pathPrefix: "", accessKeyID: "AK")), sshAuthSocket: "/tmp/agent")
        let decoded = try PrivilegedBackupRequest.decoded(from: original.encoded())
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.credentials.repositoryPassword, "pw")
        XCTAssertEqual(decoded.credentials.s3SecretAccessKey, "secret")
        XCTAssertEqual(decoded.credentials.restPassword, "rest-pw")
    }

    func testGarbageIsRefused() {
        XCTAssertThrowsError(try PrivilegedBackupRequest.decoded(from: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? PrivilegedBackupError, .invalidRequest("unreadable request"))
        }
    }

    func testValidationRefusesEmptyRelativeAndNULPaths() throws {
        var empty = request(.local(path: "/r"))
        empty.sources = []
        XCTAssertThrowsError(try PrivilegedBackupRequest.decoded(from: empty.encoded())) { error in
            XCTAssertEqual(error as? PrivilegedBackupError, .invalidRequest("no folders to back up"))
        }

        var relative = request(.local(path: "/r"))
        relative.sources = ["etc"]
        XCTAssertThrowsError(try relative.validate()) { error in
            XCTAssertEqual(error as? PrivilegedBackupError, .invalidRequest("not an absolute path: etc"))
        }

        var nul = request(.local(path: "/r"))
        nul.excludes = ["a\0b"]
        XCTAssertThrowsError(try nul.validate()) { error in
            XCTAssertEqual(error as? PrivilegedBackupError, .invalidRequest("a path contains a NUL character"))
        }
        XCTAssertNoThrow(try request(.local(path: "/r")).validate())
    }

    /// Every failure crosses the XPC connection as JSON and is put into
    /// words on the app's side.
    func testErrorsRoundTripAndDescribeThemselves() throws {
        let errors: [PrivilegedBackupError] = [
            .invalidRequest("why"), .unquotableSSHArgument("a\"b"), .resticUnavailable, .helperFault("disk full"),
        ]
        for error in errors {
            let decoded = try JSONDecoder().decode(PrivilegedBackupError.self, from: JSONEncoder().encode(error))
            XCTAssertEqual(decoded, error)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertTrue(PrivilegedBackupError.invalidRequest("why").localizedDescription.contains("why"))
        XCTAssertTrue(PrivilegedBackupError.helperFault("disk full").localizedDescription.contains("disk full"))
    }

    // MARK: - Invocation

    /// Root's environment is built from nothing: none of the daemon's own
    /// variables, the user's secrets and a cache of root's own.
    func testLocalInvocationRunsTheCommandWithAMinimalRootEnvironment() throws {
        let request = request(.local(path: "/Volumes/ResticBackup/repo"))
        let invocation = try PrivilegedInvocation(request: request, user: user, cacheDirectory: cache)
        XCTAssertEqual(invocation.arguments, request.command.arguments)
        XCTAssertEqual(invocation.environment, [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/var/root",
            "RESTIC_CACHE_DIR": cache,
            "RESTIC_REPOSITORY": "/Volumes/ResticBackup/repo",
            "RESTIC_PASSWORD": "pw",
        ])
    }

    func testS3InvocationCarriesItsKeysInTheEnvironmentOnly() throws {
        let request = request(.s3(S3Config(endpoint: "s3.example.com", bucket: "b", pathPrefix: "", accessKeyID: "AK")))
        let invocation = try PrivilegedInvocation(request: request, user: user, cacheDirectory: cache)
        XCTAssertEqual(invocation.environment["AWS_ACCESS_KEY_ID"], "AK")
        XCTAssertEqual(invocation.environment["AWS_SECRET_ACCESS_KEY"], "secret")
        XCTAssertFalse(invocation.arguments.contains { $0.contains("secret") || $0.contains("pw") })
    }

    func testSFTPInvocationRunsSSHAsTheUser() throws {
        let request = request(.sftp(SFTPConfig(user: "backup", host: "nas.local", port: 2222, path: "/srv/repo")), sshAuthSocket: "/private/tmp/agent.sock")
        let invocation = try PrivilegedInvocation(request: request, user: user, cacheDirectory: cache)
        XCTAssertEqual(Array(invocation.arguments.dropFirst(2)), request.command.arguments)
        XCTAssertEqual(invocation.arguments.first, "-o")
        XCTAssertEqual(
            invocation.arguments[1],
            #""sftp.command=""/bin/launchctl"" ""asuser"" ""501"" ""/usr/bin/sudo"" ""-n"" ""-u"" ""matt"" ""/usr/bin/env"" ""HOME=/Users/matt"" ""SSH_AUTH_SOCK=/private/tmp/agent.sock"" ""/usr/bin/ssh"" ""-p"" ""2222"" ""-l"" ""backup"" ""-s"" ""--"" ""nas.local"" ""sftp""""#
        )
        XCTAssertNil(invocation.environment["SSH_AUTH_SOCK"], "ssh gets the agent; restic does not need it")
    }

    func testSFTPWithoutAnAgentLeavesTheSocketOut() throws {
        let request = request(.sftp(SFTPConfig(user: "backup", host: "nas.local", path: "/srv/repo")))
        let invocation = try PrivilegedInvocation(request: request, user: user, cacheDirectory: cache)
        XCTAssertFalse(invocation.arguments[1].contains("SSH_AUTH_SOCK"))
    }

    func testSFTPRefusesAQuoteItCannotEscape() {
        let request = request(.sftp(SFTPConfig(user: "back\"up", host: "nas.local", path: "/srv/repo")))
        XCTAssertThrowsError(try PrivilegedInvocation(request: request, user: user, cacheDirectory: cache)) { error in
            XCTAssertEqual(error as? PrivilegedBackupError, .unquotableSSHArgument("back\"up"))
        }
        XCTAssertThrowsError(try PrivilegedInvocation.sftpCommandOption(words: ["a\nb"]))
    }

    /// The quoting checked against the real binary rather than a reading of
    /// its parsers: restic starts the command it decoded from the option,
    /// and a stand-in ssh writes down the words it was given.
    func testRealResticSplitsTheOptionBackIntoTheSameWords() async throws {
        guard let restic = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic not installed")
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenSFTPQuoting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let out = work.appendingPathComponent("words.txt")
        let fakeSSH = work.appendingPathComponent("fake ssh")
        try "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > \"\(out.path)\"\nexit 1\n"
            .write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)

        let words = ["HOME=/Users/Jane Doe", "a,b", "it's", "--", "nas.local", "sftp"]
        let option = try PrivilegedInvocation.sftpCommandOption(words: [fakeSSH.path] + words)
        let runner = ResticRunner(binaryURL: restic)
        let stream = runner.lineStream(
            arguments: ["-o", option, "snapshots", "--json"],
            environment: ["RESTIC_REPOSITORY": "sftp:u@h:/repo", "RESTIC_PASSWORD": "x", "PATH": "/usr/bin:/bin"]
        )
        do {
            for try await _ in stream {}
            XCTFail("the stand-in ssh exits 1, so restic must fail")
        } catch is ResticProcessExit {}

        let recorded = try String(contentsOf: out, encoding: .utf8)
        XCTAssertEqual(recorded, words.joined(separator: "\n") + "\n")
    }

    // MARK: - Raw line stream

    private func fakeBinary(_ script: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("fake-restic")
        try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testLineStreamYieldsRawLinesAndTheExitAsItCame() async throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenLineStream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let ok = ResticRunner(binaryURL: try fakeBinary("echo \"$1\"; echo \"$FOO\"", in: work))
        var lines: [String] = []
        for try await line in ok.lineStream(arguments: ["first"], environment: ["FOO": "second"]) {
            lines.append(line)
        }
        XCTAssertEqual(lines, ["first", "second"])

        let failing = ResticRunner(binaryURL: try fakeBinary("echo out; echo 'it broke' >&2; exit 3", in: work))
        lines = []
        do {
            for try await line in failing.lineStream(arguments: [], environment: [:]) {
                lines.append(line)
            }
            XCTFail("expected ResticProcessExit")
        } catch let exit as ResticProcessExit {
            XCTAssertEqual(exit, ResticProcessExit(exitCode: 3, stderr: "it broke\n"))
        }
        XCTAssertEqual(lines, ["out"])
    }

    /// The helper's stop: SIGINT reaches restic, and the stream keeps going
    /// until restic has actually exited, with whatever it said on the way out.
    func testInterruptStopsResticButLetsTheStreamRunToItsExit() async throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenInterrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let runner = ResticRunner(binaryURL: try fakeBinary(
            "trap 'echo unlocked; exit 130' INT; echo started; while :; do sleep 0.05; done", in: work
        ))

        let interrupt = ResticInterrupt()
        var lines: [String] = []
        do {
            for try await line in runner.lineStream(arguments: [], environment: [:], interrupt: interrupt) {
                lines.append(line)
                if line == "started" {
                    interrupt.interrupt()
                    interrupt.interrupt()
                }
            }
            XCTFail("expected ResticProcessExit")
        } catch let exit as ResticProcessExit {
            XCTAssertEqual(exit.exitCode, 130)
        }
        XCTAssertEqual(lines, ["started", "unlocked"])

        // Pressed before restic starts: delivered the moment it does — early
        // enough here that the shell dies of the signal before its trap is
        // set, which reports as status 2 rather than the trap's 130.
        let early = ResticInterrupt()
        early.interrupt()
        do {
            for try await _ in runner.lineStream(arguments: [], environment: [:], interrupt: early) {}
            XCTFail("expected ResticProcessExit")
        } catch let exit as ResticProcessExit {
            XCTAssertNotEqual(exit.exitCode, 0)
        }
    }

    // MARK: - BackupOptions

    func testReadsAsAdministratorRoundTripsAndAddsNoFlag() throws {
        let options = BackupOptions(readsAsAdministrator: true)
        XCTAssertFalse(options.isDefault)
        XCTAssertEqual(options.arguments, [])
        let decoded = try JSONDecoder().decode(BackupOptions.self, from: JSONEncoder().encode(options))
        XCTAssertTrue(decoded.readsAsAdministrator)
        XCTAssertFalse(try JSONDecoder().decode(BackupOptions.self, from: Data("{}".utf8)).readsAsAdministrator)
    }
}
