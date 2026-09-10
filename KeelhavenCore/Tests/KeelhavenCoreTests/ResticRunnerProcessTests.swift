import XCTest
@testable import KeelhavenCore

/// Exercises `ResticRunner`'s process plumbing and failure paths with small
/// fake executables instead of restic, so they run everywhere deterministically
/// (the happy paths against the real binary live in
/// `ResticRunnerIntegrationTests`).
final class ResticRunnerProcessTests: XCTestCase {
    private var workDirectory: URL!

    private let destination = Destination.local(path: "/tmp/unused-repo")
    private let credentials = RepoCredentials(repositoryPassword: "pw", s3SecretAccessKey: nil)

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenFakeBinary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Writes an executable shell script standing in for restic.
    private func fakeBinary(script: String) throws -> URL {
        let url = workDirectory.appendingPathComponent("fake-restic")
        try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    // MARK: - One-shot commands

    func testRunThrowsOutputDecodingFailedOnGarbageStdout() async throws {
        let binary = try fakeBinary(script: "echo 'not json'; exit 0")
        let runner = ResticRunner(binaryURL: binary)
        do {
            _ = try await runner.run(
                .snapshots, destination: destination, credentials: credentials,
                decoding: [ResticSnapshot].self
            )
            XCTFail("Expected outputDecodingFailed")
        } catch let error as ResticError {
            guard case .outputDecodingFailed = error else {
                return XCTFail("Expected outputDecodingFailed, got \(error)")
            }
        }
    }

    func testRunIgnoringOutputSucceedsOnExitZero() async throws {
        let binary = try fakeBinary(script: "exit 0")
        let runner = ResticRunner(binaryURL: binary)
        try await runner.runIgnoringOutput(
            .check, destination: destination, credentials: credentials
        )
    }

    func testRunIgnoringOutputClassifiesNonZeroExit() async throws {
        let binary = try fakeBinary(script: "echo 'Fatal: boom' >&2; exit 1")
        let runner = ResticRunner(binaryURL: binary)
        do {
            try await runner.runIgnoringOutput(
                .check, destination: destination, credentials: credentials
            )
            XCTFail("Expected commandFailed")
        } catch let error as ResticError {
            XCTAssertEqual(error, .commandFailed(exitCode: 1, message: "boom"))
        }
    }

    func testRunThrowsBinaryNotFoundForMissingExecutable() async {
        let runner = ResticRunner(
            binaryURL: workDirectory.appendingPathComponent("does-not-exist")
        )
        do {
            _ = try await runner.run(
                .snapshots, destination: destination, credentials: credentials,
                decoding: [ResticSnapshot].self
            )
            XCTFail("Expected binaryNotFound")
        } catch let error as ResticError {
            XCTAssertEqual(error, .binaryNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Streaming backup

    func testBackupStreamThrowsBinaryNotFoundForMissingExecutable() async {
        let runner = ResticRunner(
            binaryURL: workDirectory.appendingPathComponent("does-not-exist")
        )
        let stream = runner.backupStream(
            .backup(sources: ["/tmp"], excludes: [], tag: nil, performance: .off, options: .off),
            destination: destination, credentials: credentials
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected binaryNotFound")
        } catch let error as ResticError {
            XCTAssertEqual(error, .binaryNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBackupStreamYieldsEventsThenClassifiesFailure() async throws {
        let statusLine = #"{"message_type":"status","percent_done":0.5}"#
        let binary = try fakeBinary(script: """
        echo '\(statusLine)'
        echo 'Fatal: disk gone' >&2
        exit 3
        """)
        let runner = ResticRunner(binaryURL: binary)
        let stream = runner.backupStream(
            .backup(sources: ["/tmp"], excludes: [], tag: nil, performance: .off, options: .off),
            destination: destination, credentials: credentials
        )

        var events: [BackupProgressEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
            XCTFail("Expected someSourcesUnreadable")
        } catch let error as ResticError {
            // Exit code 3 with nothing parseable on stderr is still reported as
            // an unreadable-source failure, just with no names to show.
            XCTAssertEqual(
                error,
                .someSourcesUnreadable(paths: [], totalUnreadable: 0, message: "disk gone")
            )
        }
        XCTAssertEqual(events.count, 1)
    }

    /// The same exit code through the real streaming path, this time with the
    /// per-file `message_type: "error"` lines restic actually writes — the
    /// ones the UI turns into "these files could not be read".
    func testBackupStreamCarriesUnreadableItemsThroughFromStderr() async throws {
        let binary = try fakeBinary(script: """
        echo '{"message_type":"summary","files_new":0,"files_changed":0,"files_unmodified":0,"snapshot_id":"abc"}'
        echo '{"message_type":"error","error":{"message":"open /tmp/b.txt: permission denied"},"item":"/tmp/b.txt"}' >&2
        echo '{"message_type":"exit_error","code":3,"message":"Warning: at least one source file could not be read"}' >&2
        exit 3
        """)
        let runner = ResticRunner(binaryURL: binary)
        let stream = runner.backupStream(
            .backup(sources: ["/tmp"], excludes: [], tag: nil, performance: .off, options: .off),
            destination: destination, credentials: credentials
        )

        var events: [BackupProgressEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
            XCTFail("Expected someSourcesUnreadable")
        } catch let error as ResticError {
            guard case .someSourcesUnreadable(let paths, let total, let message) = error else {
                return XCTFail("Expected someSourcesUnreadable, got \(error)")
            }
            XCTAssertEqual(paths, ["/tmp/b.txt"])
            XCTAssertEqual(total, 1)
            XCTAssertEqual(message, "Warning: at least one source file could not be read")
        }
        // The summary reaches the consumer before the process fails, which is
        // what lets a failed run record the incomplete snapshot it left behind.
        XCTAssertEqual(events.count, 1)
    }

    func testBackupStreamCancellationInterruptsProcess() async throws {
        let statusLine = #"{"message_type":"status","percent_done":0.1}"#
        // Streams one event, then blocks — only cancellation can end this run.
        // `exec` so SIGINT hits the sleeping process itself, closing the pipes.
        let binary = try fakeBinary(script: """
        echo '\(statusLine)'
        exec /bin/sleep 30
        """)
        let runner = ResticRunner(binaryURL: binary)

        let consumer = Task {
            let stream = runner.backupStream(
                .backup(sources: ["/tmp"], excludes: [], tag: nil, performance: .off, options: .off),
                destination: destination, credentials: credentials
            )
            var count = 0
            do {
                for try await _ in stream {
                    count += 1
                    // Got the first event; cancel from within.
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            } catch {}
            return count
        }

        let started = Date()
        let received = await consumer.value
        XCTAssertGreaterThanOrEqual(received, 1)
        // SIGINT must end the run promptly — nowhere near the 30s sleep.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testBackupStreamCancellationEndsEvenIfChildIgnoresSigint() async throws {
        let statusLine = #"{"message_type":"status","percent_done":0.1}"#
        // A child that shrugs off SIGINT but keeps streaming: the readers must
        // unwind via task cancellation, observed at the next data boundary
        // (partial output is kept for error reporting). Continuous output —
        // a reader blocked in a pipe read cannot see cancellation until data
        // arrives, and a silent child would wedge the shared reader queue.
        let binary = try fakeBinary(script: """
        trap '' INT
        while :; do
          echo '\(statusLine)'
          echo noise >&2
          sleep 0.1
        done
        """)
        let runner = ResticRunner(binaryURL: binary)

        let consumer = Task {
            let stream = runner.backupStream(
                .backup(sources: ["/tmp"], excludes: [], tag: nil, performance: .off, options: .off),
                destination: destination, credentials: credentials
            )
            var count = 0
            do {
                for try await _ in stream {
                    count += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            } catch {}
            return count
        }

        let started = Date()
        let received = await consumer.value
        XCTAssertGreaterThanOrEqual(received, 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        // Reap the deliberately SIGINT-immune child so nothing outlives the test.
        let reaper = try Process.run(
            URL(fileURLWithPath: "/usr/bin/pkill"),
            arguments: ["-9", "-f", workDirectory.path]
        )
        reaper.waitUntilExit()
    }
}
