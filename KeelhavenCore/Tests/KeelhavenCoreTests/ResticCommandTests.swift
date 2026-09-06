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
            tag: "keelhaven"
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
        let command = ResticCommand.backup(sources: ["/tmp/data"], excludes: [], tag: nil)
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
        XCTAssertEqual(ResticCommand.forget(retention: .year).arguments, [
            "forget", "--prune",
            "--keep-last", "3",
            "--keep-daily", "7",
            "--keep-weekly", "5",
            "--keep-monthly", "12",
        ])
        XCTAssertEqual(ResticCommand.forget(retention: .month).arguments, [
            "forget", "--prune",
            "--keep-last", "3",
            "--keep-daily", "7",
            "--keep-weekly", "4",
        ])
        // Never issued by the app — PrunePolicy.isDue is false for .off —
        // and restic rejects the bare command rather than deleting anything.
        XCTAssertEqual(ResticCommand.forget(retention: .off).arguments, ["forget", "--prune"])
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
