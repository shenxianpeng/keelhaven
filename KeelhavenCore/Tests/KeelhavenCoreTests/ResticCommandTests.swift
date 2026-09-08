import XCTest
@testable import KeelhavenCore

final class ResticCommandTests: XCTestCase {
    func testInitArguments() {
        XCTAssertEqual(ResticCommand.initRepository.arguments, ["init", "--json"])
    }

    func testBackupArguments() {
        let command = ResticCommand.backup(
            sources: ["/Users/me/Documents", "/Users/me/Photos"],
            excludes: [".DS_Store", "node_modules"],
            tag: "keelhaven",
            performance: .off,
            options: .off
        )
        XCTAssertEqual(command.arguments, [
            "backup", "--json",
            "--exclude", ".DS_Store",
            "--exclude", "node_modules",
            "--tag", "keelhaven",
            "/Users/me/Documents", "/Users/me/Photos",
        ])
    }

    func testBackupWithoutTagOrExcludes() {
        let command = ResticCommand.backup(sources: ["/tmp/data"], excludes: [], tag: nil, performance: .off, options: .off)
        XCTAssertEqual(command.arguments, ["backup", "--json", "/tmp/data"])
    }

    /// No `--remove-all`: that would also drop the exclusive locks
    /// `forget --prune` holds, turning a recovery into a way to corrupt a
    /// concurrent repack.
    func testUnlockArguments() {
        XCTAssertEqual(ResticCommand.unlock.arguments, ["unlock"])
    }

    func testCatConfigArguments() {
        XCTAssertEqual(ResticCommand.catConfig.arguments, ["cat", "config", "--json"])
    }

    func testForgetArguments() {
        XCTAssertEqual(ResticCommand.forget(retention: .year, performance: .off).arguments, [
            "forget", "--prune",
            "--keep-last", "3",
            "--keep-daily", "7",
            "--keep-weekly", "5",
            "--keep-monthly", "12",
        ])
        XCTAssertEqual(ResticCommand.forget(retention: .month, performance: .off).arguments, [
            "forget", "--prune",
            "--keep-last", "3",
            "--keep-daily", "7",
            "--keep-weekly", "4",
        ])
        // Never issued by the app — PrunePolicy.isDue is false for .off —
        // and restic rejects the bare command rather than deleting anything.
        XCTAssertEqual(ResticCommand.forget(retention: .off, performance: .off).arguments, ["forget", "--prune"])
    }

    // MARK: - Performance options

    /// The whole point of `.off`: a plan that never touches the Advanced
    /// section produces the exact argument list it did before these knobs
    /// existed. Asserted separately from the tests above so a future default
    /// creeping in fails here loudly.
    func testDefaultPerformanceOptionsAddNothing() {
        XCTAssertTrue(PerformanceOptions.off.isDefault)
        XCTAssertEqual(PerformanceOptions.off.arguments(includingReadConcurrency: true), [])
        XCTAssertEqual(PerformanceOptions.off.arguments(includingReadConcurrency: false), [])
    }

    func testBackupCarriesEveryPerformanceFlag() {
        let command = ResticCommand.backup(
            sources: ["/tmp/data"],
            excludes: [],
            tag: nil,
            performance: PerformanceOptions(
                uploadLimitKiBPerSecond: 500,
                readConcurrency: 8,
                packSizeMiB: 64
            ),
            options: .off
        )
        // Flags come before the sources: restic accepts them either way, but
        // a path is a positional argument and reads as one here.
        XCTAssertEqual(command.arguments, [
            "backup", "--json",
            "--limit-upload", "500",
            "--read-concurrency", "8",
            "--pack-size", "64",
            "/tmp/data",
        ])
    }

    /// A preview must be the same command as the backup it previews, plus
    /// `--dry-run` — otherwise it answers a question about a backup nobody
    /// is going to run (issue #43).
    func testPreviewBackupIsTheBackupCommandPlusDryRun() {
        let sources = ["/Users/me/Documents"]
        let excludes = ["*.log"]
        let performance = PerformanceOptions(uploadLimitKiBPerSecond: 500, packSizeMiB: 64)
        let options = BackupOptions(excludeCaches: true, oneFileSystem: true, skipIfUnchanged: true)

        let backup = ResticCommand.backup(
            sources: sources, excludes: excludes, tag: "keelhaven",
            performance: performance, options: options
        )
        let preview = ResticCommand.previewBackup(
            sources: sources, excludes: excludes, tag: "keelhaven",
            performance: performance, options: options
        )

        XCTAssertEqual(preview.arguments.first, "backup")
        XCTAssertTrue(preview.arguments.contains("--dry-run"))
        XCTAssertFalse(backup.arguments.contains("--dry-run"))

        // Identical once the flag is removed: same excludes, same tag, same
        // throughput knobs, same sources, same order.
        var withoutDryRun = preview.arguments
        withoutDryRun.removeAll { $0 == "--dry-run" }
        XCTAssertEqual(withoutDryRun, backup.arguments)
    }

    func testPreviewBackupArgumentOrder() {
        let command = ResticCommand.previewBackup(
            sources: ["/tmp/data"], excludes: [], tag: nil,
            performance: .off, options: .off
        )
        // `--dry-run` immediately after `--json`, before anything optional,
        // so it can never end up after a positional source path.
        XCTAssertEqual(command.arguments, ["backup", "--json", "--dry-run", "/tmp/data"])
    }

    func testBackupOptionsArguments() {
        XCTAssertEqual(BackupOptions.off.arguments, [])
        XCTAssertTrue(BackupOptions.off.isDefault)
        XCTAssertEqual(BackupOptions(excludeCaches: true).arguments, ["--exclude-caches"])
        XCTAssertEqual(BackupOptions(oneFileSystem: true).arguments, ["--one-file-system"])
        XCTAssertEqual(BackupOptions(skipIfUnchanged: true).arguments, ["--skip-if-unchanged"])
        XCTAssertFalse(BackupOptions(excludeCaches: true).isDefault)
        XCTAssertFalse(BackupOptions(oneFileSystem: true).isDefault)
        XCTAssertFalse(BackupOptions(skipIfUnchanged: true).isDefault)
    }

    /// Both switches land between the throughput flags and the excludes, and
    /// ahead of the positional sources — the order this test exists to pin.
    func testBackupCarriesEveryBackupOption() {
        let command = ResticCommand.backup(
            sources: ["/tmp/data"],
            excludes: ["*.log"],
            tag: "keelhaven",
            performance: PerformanceOptions(packSizeMiB: 64),
            options: BackupOptions(excludeCaches: true, oneFileSystem: true, skipIfUnchanged: true)
        )
        XCTAssertEqual(command.arguments, [
            "backup", "--json",
            "--pack-size", "64",
            "--exclude-caches",
            "--one-file-system",
            "--skip-if-unchanged",
            "--exclude", "*.log",
            "--tag", "keelhaven",
            "/tmp/data",
        ])
    }

    /// Neither switch may reach `forget`: restic exits with a usage error on
    /// an unknown flag, which would break every retention pass. `.forget`
    /// takes no `BackupOptions` at all, so this pins that it stays that way.
    func testForgetCarriesNoBackupOptions() {
        let command = ResticCommand.forget(retention: .month, performance: .off)
        XCTAssertFalse(command.arguments.contains("--exclude-caches"))
        XCTAssertFalse(command.arguments.contains("--one-file-system"))
        XCTAssertFalse(command.arguments.contains("--skip-if-unchanged"))
    }

    /// `--read-concurrency` is a `backup` flag. Passing it to `forget` makes
    /// restic exit with a usage error, which would break every retention pass
    /// for anyone who set it — so it must never reach this command.
    func testForgetTakesTheGlobalFlagsButNotReadConcurrency() {
        let command = ResticCommand.forget(
            retention: .month,
            performance: PerformanceOptions(
                uploadLimitKiBPerSecond: 500,
                readConcurrency: 8,
                packSizeMiB: 64
            )
        )
        XCTAssertEqual(command.arguments, [
            "forget", "--prune",
            "--limit-upload", "500",
            "--pack-size", "64",
            "--keep-last", "3",
            "--keep-daily", "7",
            "--keep-weekly", "4",
        ])
    }

    func testEachPerformanceKnobIsIndependent() {
        XCTAssertEqual(
            PerformanceOptions(uploadLimitKiBPerSecond: 100).arguments(includingReadConcurrency: true),
            ["--limit-upload", "100"]
        )
        XCTAssertEqual(
            PerformanceOptions(readConcurrency: 4).arguments(includingReadConcurrency: true),
            ["--read-concurrency", "4"]
        )
        XCTAssertEqual(
            PerformanceOptions(packSizeMiB: 32).arguments(includingReadConcurrency: true),
            ["--pack-size", "32"]
        )
    }

    /// Clamping lives in Core because the Edit Plan window is in the UI
    /// target, which has no tests — and because a hand-edited plans.json
    /// would otherwise produce a command restic refuses on every run.
    func testOutOfRangeValuesAreClamped() {
        let tooLow = PerformanceOptions(readConcurrency: 0, packSizeMiB: 1)
        XCTAssertEqual(tooLow.readConcurrency, 1)
        XCTAssertEqual(tooLow.packSizeMiB, 4)

        let tooHigh = PerformanceOptions(readConcurrency: 99, packSizeMiB: 999)
        XCTAssertEqual(tooHigh.readConcurrency, 32)
        XCTAssertEqual(tooHigh.packSizeMiB, 128)
    }

    /// Zero and negative are how the UI says "no limit" when the field is
    /// cleared: they collapse to nil rather than becoming `--limit-upload 0`,
    /// which restic reads as a real cap of zero.
    func testNonPositiveUploadLimitMeansUnlimited() {
        XCTAssertNil(PerformanceOptions(uploadLimitKiBPerSecond: 0).uploadLimitKiBPerSecond)
        XCTAssertNil(PerformanceOptions(uploadLimitKiBPerSecond: -5).uploadLimitKiBPerSecond)
        XCTAssertTrue(PerformanceOptions(uploadLimitKiBPerSecond: 0).isDefault)
    }

    func testAnyKnobSetIsNotDefault() {
        XCTAssertFalse(PerformanceOptions(uploadLimitKiBPerSecond: 1).isDefault)
        XCTAssertFalse(PerformanceOptions(readConcurrency: 1).isDefault)
        XCTAssertFalse(PerformanceOptions(packSizeMiB: 4).isDefault)
    }

    func testRestoreArguments() {
        let command = ResticCommand.restore(snapshotID: "c4e6a708", target: "/tmp/restored")
        XCTAssertEqual(command.arguments, ["restore", "c4e6a708", "--target", "/tmp/restored", "--json"])
    }

    func testLocalRepositoryLocation() {
        let destination = Destination.local(path: "/Volumes/Backup/keelhaven")
        XCTAssertEqual(destination.repositoryLocation, "/Volumes/Backup/keelhaven")
    }

    func testS3RepositoryLocationAddsSchemeAndTrimsPrefix() {
        let bare = Destination.s3(S3Config(
            endpoint: "s3.eu-central-1.amazonaws.com",
            bucket: "my-backups",
            pathPrefix: "/mac/",
            accessKeyID: "AKIAEXAMPLE"
        ))
        XCTAssertEqual(
            bare.repositoryLocation,
            "s3:https://s3.eu-central-1.amazonaws.com/my-backups/mac"
        )

        let withScheme = Destination.s3(S3Config(
            endpoint: "http://minio.local:9000",
            bucket: "backups",
            pathPrefix: "",
            accessKeyID: "minio"
        ))
        XCTAssertEqual(withScheme.repositoryLocation, "s3:http://minio.local:9000/backups")
    }

    func testSFTPRepositoryLocation() {
        let standardPort = Destination.sftp(SFTPConfig(user: "sxp", host: "nas.local", port: 22, path: "/backups/mac"))
        XCTAssertEqual(standardPort.repositoryLocation, "sftp:sxp@nas.local:/backups/mac")

        let customPort = Destination.sftp(SFTPConfig(user: "sxp", host: "nas.local", port: 2222, path: "/backups/mac"))
        XCTAssertEqual(customPort.repositoryLocation, "sftp://sxp@nas.local:2222//backups/mac")
    }

    func testRESTRepositoryLocationNeverEmbedsCredentials() {
        let destination = Destination.rest(RESTConfig(url: "http://nas.local:8000/mac/", username: "sxp"))
        // The URL is passed through as-is: neither the username here nor any
        // password ever appears in it, so restic must pick both up from
        // RESTIC_REST_USERNAME/RESTIC_REST_PASSWORD instead (verified against
        // restic's rest backend: it only reads those env vars when the URL
        // itself has no embedded user/password).
        XCTAssertEqual(destination.repositoryLocation, "rest:http://nas.local:8000/mac/")
    }

    func testRESTURLEmbedsCredentialsDetection() {
        // restic's docs teach "rest:https://user:pass@host:8000/" — the wizard
        // must catch that form before the URL reaches plans.json.
        XCTAssertTrue(RESTConfig(url: "https://user:pass@host:8000/").urlEmbedsCredentials)
        XCTAssertTrue(RESTConfig(url: "http://user@host:8000/").urlEmbedsCredentials)
        XCTAssertFalse(RESTConfig(url: "http://127.0.0.1:8000/").urlEmbedsCredentials)
        // Unparseable URLs can't be inspected; restic rejects them itself.
        XCTAssertFalse(RESTConfig(url: "not a url").urlEmbedsCredentials)
    }

    func testEnvironmentContainsSecretsAndCleanBase() {
        let destination = Destination.s3(S3Config(
            endpoint: "s3.amazonaws.com",
            bucket: "bucket",
            pathPrefix: "",
            accessKeyID: "AKIAEXAMPLE"
        ))
        let credentials = RepoCredentials(repositoryPassword: "hunter22", s3SecretAccessKey: "sekrit")
        let env = credentials.environment(for: destination)

        XCTAssertEqual(env["RESTIC_PASSWORD"], "hunter22")
        XCTAssertEqual(env["RESTIC_REPOSITORY"], "s3:https://s3.amazonaws.com/bucket")
        XCTAssertEqual(env["AWS_ACCESS_KEY_ID"], "AKIAEXAMPLE")
        XCTAssertEqual(env["AWS_SECRET_ACCESS_KEY"], "sekrit")
        XCTAssertNotNil(env["PATH"], "restic needs PATH to find ssh for sftp")

        // The app's own environment must not leak wholesale into the child.
        let allowedKeys: Set<String> = [
            "PATH", "HOME", "TMPDIR", "SSH_AUTH_SOCK",
            "RESTIC_REPOSITORY", "RESTIC_PASSWORD",
            "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
        ]
        XCTAssertTrue(Set(env.keys).isSubset(of: allowedKeys), "Unexpected keys: \(Set(env.keys).subtracting(allowedKeys))")
    }

    func testLocalDestinationOmitsAWSVariables() {
        let credentials = RepoCredentials(repositoryPassword: "pw")
        let env = credentials.environment(for: .local(path: "/tmp/repo"))
        XCTAssertNil(env["AWS_ACCESS_KEY_ID"])
        XCTAssertNil(env["AWS_SECRET_ACCESS_KEY"])
    }

    func testRESTDestinationSetsUsernameAndPasswordWhenAuthenticated() {
        let destination = Destination.rest(RESTConfig(url: "http://127.0.0.1:8000/", username: "restic"))
        let credentials = RepoCredentials(repositoryPassword: "hunter22", restPassword: "rest-secret")
        let env = credentials.environment(for: destination)

        XCTAssertEqual(env["RESTIC_REPOSITORY"], "rest:http://127.0.0.1:8000/")
        XCTAssertEqual(env["RESTIC_REST_USERNAME"], "restic")
        XCTAssertEqual(env["RESTIC_REST_PASSWORD"], "rest-secret")
    }

    /// The default rest-server setup (no --private-repos, no --append-only,
    /// no TLS) is commonly also run with --no-auth — the client must send no
    /// basic-auth headers at all in that case, not empty-string credentials.
    func testRESTDestinationOmitsAuthVariablesWhenUsernameEmpty() {
        let destination = Destination.rest(RESTConfig(url: "http://127.0.0.1:8000/"))
        let credentials = RepoCredentials(repositoryPassword: "hunter22")
        let env = credentials.environment(for: destination)

        XCTAssertNil(env["RESTIC_REST_USERNAME"])
        XCTAssertNil(env["RESTIC_REST_PASSWORD"])
    }
}
