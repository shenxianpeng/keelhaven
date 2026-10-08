import XCTest
@testable import KeelhavenCore

/// How the runner reads a child's output, tested with a stand-in for restic: a
/// shell script that writes exactly what each case calls for. No backup makes
/// restic print a megabyte on demand, and these are about the plumbing, not
/// about restic — so they also run where restic is not installed.
///
/// What they guard against did ship: stdout and stderr were both read through
/// `FileHandle.bytes`, whose readers queue behind one another, and a process
/// that wrote more than a pipe holds (64 KB) on one while saying nothing on
/// the other was never read again. It blocked on its next write for good —
/// see `PipeReader`. A regression here shows up as a test that does not
/// finish rather than one that fails; the streaming tests turn that back into
/// a failure by giving up after a while.
final class ResticRunnerPipeTests: XCTestCase {
    private var workDirectory: URL!
    private let destination = Destination.local(path: "unused-by-the-stand-in")
    private let credentials = RepoCredentials(repositoryPassword: "unused-by-the-stand-in")

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenPipes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    /// A runner whose "restic" is this script. It ignores its arguments.
    private func runner(printing script: String) throws -> ResticRunner {
        let url = workDirectory.appendingPathComponent("restic-stand-in")
        try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return ResticRunner(binaryURL: url)
    }

    /// Fails instead of hanging. Cancelling the stream interrupts the child,
    /// so a starved run is cut short rather than left behind.
    private func finishing<T: Sendable>(
        within seconds: Double = 30,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return try XCTUnwrap(first, "Still running after \(seconds) s: a pipe was left unread")
        }
    }

    private static let status = #"{"message_type":"status","percent_done":0.5,"total_files":10,"files_done":5,"total_bytes":100,"bytes_done":50}"#
    private static let summary = #"{"message_type":"summary","files_new":1,"files_changed":0,"files_unmodified":0,"dirs_new":0,"dirs_changed":0,"dirs_unmodified":0,"data_blobs":1,"tree_blobs":1,"data_added":10,"data_added_packed":10,"total_files_processed":1,"total_bytes_processed":10,"total_duration":1.5,"snapshot_id":"ff1faf7d6242b9b5e2e4584214fc4287f25d627b5d22cf5a691ee00a6f752f34"}"#

    /// The case that hung: far more progress than a pipe holds, and a silent
    /// stderr. 4 000 status lines are about 440 KB — a backup that runs for a
    /// quarter of an hour.
    func testAStreamKeepsUpWithMoreOutputThanAPipeHolds() async throws {
        let runner = try runner(printing: """
        /usr/bin/awk 'BEGIN { for (i = 0; i < 4000; i++) print "\(Self.status.replacingOccurrences(of: "\"", with: "\\\""))" }'
        echo '\(Self.summary)'
        """)
        let destination = destination
        let credentials = credentials

        let counts = try await finishing {
            var statuses = 0
            var summaries = 0
            let stream = runner.backupStream(
                .backup(sources: ["src"], excludes: [], tag: nil, performance: .off, options: .off),
                destination: destination,
                credentials: credentials
            )
            for try await event in stream {
                switch event {
                case .status: statuses += 1
                case .summary: summaries += 1
                }
            }
            return [statuses, summaries]
        }
        XCTAssertEqual(counts, [4000, 1])
    }

    /// Progress is only progress if it arrives while the work is going on.
    /// With the readers queued behind one another, everything after the first
    /// piece turned up in one go when the process exited — a bar that jumped
    /// once and then sat still until the end.
    func testProgressArrivesWhileTheProcessIsStillRunning() async throws {
        let runner = try runner(printing: """
        echo '\(Self.status)'
        sleep 1
        echo '\(Self.status)'
        sleep 1
        echo '\(Self.summary)'
        """)
        let destination = destination
        let credentials = credentials

        let arrivals = try await finishing {
            var arrivals: [Date] = []
            let stream = runner.backupStream(
                .backup(sources: ["src"], excludes: [], tag: nil, performance: .off, options: .off),
                destination: destination,
                credentials: credentials
            )
            for try await _ in stream {
                arrivals.append(Date())
            }
            return arrivals + [Date()]
        }
        XCTAssertEqual(arrivals.count, 4, "two status events, the summary, and the end")
        // The second status is written a second before the script exits.
        // Measured against the end rather than the start, so a slow launch
        // on a busy machine cannot fail it.
        XCTAssertGreaterThan(arrivals[3].timeIntervalSince(arrivals[1]), 0.5)
    }

    /// A process that exits without ending its last line has still said it.
    func testALastLineWithoutANewlineStillArrives() async throws {
        let runner = try runner(printing: "printf '%s' '\(Self.summary)'")
        let destination = destination
        let credentials = credentials

        let summaries = try await finishing {
            var summaries = 0
            let stream = runner.backupStream(
                .backup(sources: ["src"], excludes: [], tag: nil, performance: .off, options: .off),
                destination: destination,
                credentials: credentials
            )
            for try await event in stream {
                if case .summary = event { summaries += 1 }
            }
            return summaries
        }
        XCTAssertEqual(summaries, 1)
    }

    /// The same trap the other way round: a run that complains at length on
    /// stderr and has nothing for stdout. That is what a first backup of a
    /// folder macOS will not let the app read looks like — one line per file.
    func testAFailureThatFillsStderrStillReportsWhatWentWrong() async throws {
        let runner = try runner(printing: """
        /usr/bin/awk 'BEGIN { for (i = 0; i < 4000; i++) print "could not read file number " i " of the many in this folder" > "/dev/stderr" }'
        echo '{"message_type":"exit_error","code":1,"message":"Fatal: the last word"}' >&2
        exit 1
        """)

        do {
            try await runner.runIgnoringOutput(.check, destination: destination, credentials: credentials)
            XCTFail("Expected the run to fail")
        } catch let error as ResticError {
            XCTAssertEqual(error, .commandFailed(exitCode: 1, message: "the last word"))
        }
    }

    /// The command that collects its output instead of streaming it has the
    /// same two pipes. 400 snapshots are about 80 KB of JSON: a plan that has
    /// backed up hourly for a little over two weeks.
    func testACollectedResultCanBeLargerThanAPipeHolds() async throws {
        let runner = try runner(printing: """
        /usr/bin/awk 'BEGIN {
            printf "["
            for (i = 0; i < 400; i++) {
                if (i > 0) printf ","
                printf "{\\"id\\":\\"%064d\\",\\"time\\":\\"2026-09-10T23:00:51.62282+03:00\\",\\"paths\\":[\\"src\\"],\\"hostname\\":\\"Mac\\",\\"username\\":\\"me\\",\\"tree\\":\\"%064d\\"}", i, i
            }
            print "]"
        }'
        """)

        let snapshots = try await runner.run(
            .snapshots,
            destination: destination,
            credentials: credentials,
            decoding: [ResticSnapshot].self
        )
        XCTAssertEqual(snapshots.count, 400)
        XCTAssertEqual(Set(snapshots.map(\.id)).count, 400)
    }
}
