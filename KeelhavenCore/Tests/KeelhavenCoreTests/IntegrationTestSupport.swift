import XCTest
@testable import KeelhavenCore

/// Shared plumbing for the integration suites that run the real restic binary
/// against real backends: local disk (ResticRunnerIntegrationTests), an
/// S3-compatible server (ResticS3IntegrationTests), and an sshd
/// (ResticSFTPIntegrationTests). Each suite self-skips when its backend is
/// unavailable, so `swift test` stays green on bare machines.
enum IntegrationTestSupport {
    static func locateRestic() -> URL? {
        for path in ["/opt/homebrew/bin/restic", "/usr/local/bin/restic"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Reads an override from the test process environment, treating unset and
    /// empty as "use the default".
    static func environmentValue(_ key: String, default defaultValue: String) -> String {
        let value = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? defaultValue : value
    }

    /// True when anything speaking HTTP answers at `endpoint` (an error status
    /// still counts — MinIO returns 403 at its root). Transport failure means
    /// no server, so the S3 suite should skip.
    static func httpEndpointIsReachable(_ endpoint: String) async -> Bool {
        guard let url = URL(string: endpoint) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    /// True when ssh reaches user@host:port without any prompt — the exact
    /// precondition restic's sftp backend has, because it shells out to ssh
    /// with no TTY to answer host-key or passphrase questions.
    static func sshIsReachable(user: String, host: String, port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=3",
            "-p", String(port),
            "\(user)@\(host)", "true",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The canonical loop every backend must survive: init a repository, back
    /// up 20 known files, list the snapshot, restore it, and byte-compare the
    /// result. Fails the calling test on any mismatch.
    static func runFullBackupCycle(
        binary: URL,
        destination: Destination,
        credentials: RepoCredentials,
        workDirectory: URL
    ) async throws {
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        for index in 0..<20 {
            let file = sourceURL.appendingPathComponent("file\(index).txt")
            try Data("hello keelhaven \(index)\n".utf8).write(to: file)
        }

        let runner = ResticRunner(binaryURL: binary)

        let initResult = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )
        XCTAssertEqual(initResult.messageType, "initialized")

        var summary: BackupSummary?
        let stream = runner.backupStream(
            .backup(sources: [sourceURL.path], excludes: [".DS_Store"], tag: "keelhaven-test", performance: .off, options: .off),
            destination: destination,
            credentials: credentials
        )
        for try await event in stream {
            if case .summary(let value) = event {
                XCTAssertNil(summary, "More than one summary event")
                summary = value
            }
        }
        let snapshotID = try XCTUnwrap(summary?.snapshotID)
        XCTAssertEqual(summary?.filesNew, 20)

        let snapshots = try await runner.run(
            .snapshots,
            destination: destination,
            credentials: credentials,
            decoding: [ResticSnapshot].self
        )
        XCTAssertEqual(snapshots.map(\.id), [snapshotID])

        let restoreTarget = workDirectory.appendingPathComponent("restored", isDirectory: true)
        var restoreSummary: RestoreSummary?
        let restoreEvents = runner.restoreStream(
            .restore(snapshotID: snapshotID, target: restoreTarget.path),
            destination: destination,
            credentials: credentials
        )
        for try await event in restoreEvents {
            if case .summary(let value) = event {
                restoreSummary = value
            }
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(restoreSummary).filesRestored, 20)
        // restic recreates the absolute source path inside the target
        let restoredFile = restoreTarget.appendingPathComponent(sourceURL.path)
            .appendingPathComponent("file0.txt")
        XCTAssertEqual(
            try String(contentsOf: restoredFile, encoding: .utf8),
            "hello keelhaven 0\n"
        )
    }
}
