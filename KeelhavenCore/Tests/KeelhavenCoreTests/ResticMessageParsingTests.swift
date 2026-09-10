import XCTest
@testable import KeelhavenCore

/// All fixtures are unmodified output captured from restic 0.19.1 on macOS.
final class ResticMessageParsingTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
            "Missing fixture \(name)"
        )
        return try Data(contentsOf: url)
    }

    private func fixtureLines(_ name: String) throws -> [String] {
        let text = String(decoding: try fixtureData(name), as: UTF8.self)
        return text.split(separator: "\n").map(String.init)
    }

    func testDecodeInitResult() throws {
        let result = try ResticJSON.decoder.decode(ResticInitResult.self, from: fixtureData("init.json"))
        XCTAssertEqual(result.messageType, "initialized")
        XCTAssertEqual(result.id.count, 64)
        XCTAssertTrue(result.repository.hasSuffix("/repo"))
    }

    /// The `--skip-if-unchanged` run that stored nothing. Captured from real
    /// restic 0.19.1 by backing the same unchanged source up twice; this is
    /// the second run.
    ///
    /// The point of the fixture is the *absence* of `snapshot_id` — restic's
    /// scripting docs say it "is omitted if snapshot creation was skipped",
    /// and this pins that we decode that shape without losing the rest of the
    /// summary, which is what the run record and the notification read.
    func testDecodeSkippedSnapshotSummary() throws {
        let lines = try fixtureLines("backup-skip-if-unchanged.jsonl")
        XCTAssertEqual(lines.count, 1)

        let event = try XCTUnwrap(ResticJSON.decodeProgressEvent(fromLine: lines[0]))
        guard case .summary(let summary) = event else {
            return XCTFail("Expected a summary event")
        }
        XCTAssertNil(summary.snapshotID)
        XCTAssertEqual(summary.filesNew, 0)
        XCTAssertEqual(summary.filesChanged, 0)
        XCTAssertEqual(summary.filesUnmodified, 2)
        XCTAssertEqual(summary.dataAdded, 0)
        XCTAssertEqual(summary.totalFilesProcessed, 2)
        XCTAssertNotNil(summary.totalDuration)
        XCTAssertNotNil(summary.backupStart)
    }

    /// The same summary shape when a snapshot *was* written, so the two
    /// fixtures together show that `snapshot_id` is the only difference —
    /// which is what `AppState` keys its "nothing was stored" reporting on.
    func testSnapshotIDIsThePresentDifferenceFromASkippedRun() throws {
        let skipped = try fixtureLines("backup-skip-if-unchanged.jsonl")[0]
        let stored = try fixtureLines("backup-incremental.jsonl")[0]

        guard case .summary(let skippedSummary)? = ResticJSON.decodeProgressEvent(fromLine: skipped),
              case .summary(let storedSummary)? = ResticJSON.decodeProgressEvent(fromLine: stored)
        else {
            return XCTFail("Expected both fixtures to decode as summaries")
        }
        XCTAssertNil(skippedSummary.snapshotID)
        XCTAssertNotNil(storedSummary.snapshotID)
    }

    /// Unmodified `restic backup --dry-run --json` output from restic
    /// 0.19.1: a previously backed-up source with files added and one
    /// changed. Every line must decode, and the summary must carry the
    /// counts the preview reports.
    func testDecodeEveryDryRunLine() throws {
        let lines = try fixtureLines("backup-dry-run.jsonl")
        XCTAssertEqual(lines.count, 8)

        var statusCount = 0
        var summary: BackupSummary?
        for line in lines {
            switch try XCTUnwrap(ResticJSON.decodeProgressEvent(fromLine: line)) {
            case .status(let status):
                statusCount += 1
                XCTAssertGreaterThanOrEqual(status.percentDone, 0)
            case .summary(let value):
                summary = value
            }
        }
        XCTAssertEqual(statusCount, 7)

        let final = try XCTUnwrap(summary)
        XCTAssertEqual(final.filesNew, 2540)
        XCTAssertEqual(final.filesChanged, 1)
        XCTAssertEqual(final.dataAdded, 757_442_803)
    }

    /// The one field that tells a preview's summary from a real backup's.
    ///
    /// A dry run still reports a `snapshot_id` — restic computes one and
    /// throws it away — so "no snapshot id" is *not* the signal here, unlike
    /// the skipped run in `backup-skip-if-unchanged.jsonl` (issue #43).
    func testDryRunSummaryIsMarkedAsSuchAndStillCarriesASnapshotID() throws {
        let lines = try fixtureLines("backup-dry-run.jsonl")
        guard case .summary(let dryRun)? = ResticJSON.decodeProgressEvent(fromLine: try XCTUnwrap(lines.last)) else {
            return XCTFail("Expected the last line to be a summary")
        }
        XCTAssertEqual(dryRun.dryRun, true)
        XCTAssertNotNil(dryRun.snapshotID, "restic reports a snapshot id even for a dry run")

        // A real backup's summary has no such marker.
        let stored = try fixtureLines("backup-incremental.jsonl")[0]
        guard case .summary(let real)? = ResticJSON.decodeProgressEvent(fromLine: stored) else {
            return XCTFail("Expected a summary")
        }
        XCTAssertNil(real.dryRun)
    }

    /// Unmodified `restic backup --json --no-scan` output from restic 0.19.1.
    ///
    /// This fixture exists to pin the exact shape the progress row has to cope
    /// with (issue #51): `percent_done` never moves off 0 and `total_bytes` is
    /// gone, so no percentage can be computed — but `bytes_done` keeps
    /// climbing, which is what the row shows instead.
    func testDecodeEveryNoScanLine() throws {
        let lines = try fixtureLines("backup-no-scan.jsonl")
        XCTAssertEqual(lines.count, 17)

        var statusCount = 0
        var lastBytesDone: Int64 = 0
        var summary: BackupSummary?
        for line in lines {
            switch try XCTUnwrap(ResticJSON.decodeProgressEvent(fromLine: line)) {
            case .status(let status):
                statusCount += 1
                XCTAssertEqual(status.percentDone, 0, "--no-scan never reports progress")
                XCTAssertNil(status.totalBytes, "--no-scan omits the total it could not measure")
                XCTAssertNil(status.totalFiles)
                let bytesDone = try XCTUnwrap(status.bytesDone)
                XCTAssertGreaterThan(bytesDone, lastBytesDone, "bytes_done must keep climbing")
                lastBytesDone = bytesDone
            case .summary(let value):
                summary = value
            }
        }
        XCTAssertEqual(statusCount, 16)

        // The summary is untouched, which is why the run record, the
        // notification and the history are unaffected by the option.
        let final = try XCTUnwrap(summary)
        XCTAssertEqual(final.filesNew, 2500)
        XCTAssertEqual(final.dataAdded, 751_137_658)
        XCTAssertNotNil(final.snapshotID)
        XCTAssertNil(final.dryRun)
    }

    /// The contrast that makes the fallback necessary: an ordinary backup
    /// reports both the total and a moving percentage.
    func testAnOrdinaryBackupReportsTheTotalNoScanOmits() throws {
        let lines = try fixtureLines("backup-progress.jsonl")
        var sawTotal = false
        for line in lines {
            if case .status(let status)? = ResticJSON.decodeProgressEvent(fromLine: line),
               status.totalBytes != nil {
                sawTotal = true
            }
        }
        XCTAssertTrue(sawTotal, "A scanned backup must carry the total a --no-scan run lacks")
    }

    func testDecodeEveryBackupProgressLine() throws {
        let lines = try fixtureLines("backup-progress.jsonl")
        XCTAssertEqual(lines.count, 10)

        var statusCount = 0
        var summaryCount = 0
        for line in lines {
            let event = try XCTUnwrap(
                ResticJSON.decodeProgressEvent(fromLine: line),
                "Line failed to decode: \(line.prefix(120))"
            )
            switch event {
            case .status(let status):
                statusCount += 1
                XCTAssertGreaterThanOrEqual(status.percentDone, 0)
                XCTAssertLessThanOrEqual(status.percentDone, 1)
            case .summary(let summary):
                summaryCount += 1
                XCTAssertEqual(summary.filesNew, 308)
                XCTAssertEqual(summary.snapshotID?.count, 64)
                XCTAssertNotNil(summary.totalDuration)
                XCTAssertNotNil(summary.backupStart)
                XCTAssertNotNil(summary.backupEnd)
            }
        }
        XCTAssertEqual(statusCount, 9)
        XCTAssertEqual(summaryCount, 1)
    }

    func testStatusFieldOptionality() throws {
        let lines = try fixtureLines("backup-progress.jsonl")
        // The final status line (percent_done == 1) has no current_files;
        // seconds_remaining appears on only some lines.
        let events = lines.compactMap(ResticJSON.decodeProgressEvent(fromLine:))
        let statuses: [BackupStatusMessage] = events.compactMap {
            if case .status(let status) = $0 { return status }
            return nil
        }
        XCTAssertTrue(statuses.contains { $0.currentFiles == nil })
        XCTAssertTrue(statuses.contains { $0.currentFiles != nil })
        XCTAssertTrue(statuses.contains { $0.secondsRemaining != nil })
        XCTAssertTrue(statuses.contains { $0.secondsRemaining == nil })
    }

    func testDecodeIncrementalBackupSummary() throws {
        let lines = try fixtureLines("backup-incremental.jsonl")
        let events = lines.compactMap(ResticJSON.decodeProgressEvent(fromLine:))
        let summaries: [BackupSummary] = events.compactMap {
            if case .summary(let summary) = $0 { return summary }
            return nil
        }
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].filesNew, 1)
        XCTAssertEqual(summaries[0].filesUnmodified, 308)
    }

    func testDecodeSnapshots() throws {
        let snapshots = try ResticJSON.decoder.decode([ResticSnapshot].self, from: fixtureData("snapshots.json"))
        XCTAssertEqual(snapshots.count, 2)

        // First snapshot has no parent; second references the first.
        XCTAssertNil(snapshots[0].parent)
        XCTAssertEqual(snapshots[1].parent, snapshots[0].id)
        XCTAssertEqual(snapshots[0].shortID, String(snapshots[0].id.prefix(8)))
        XCTAssertEqual(snapshots[0].paths.count, 1)

        // Nested summaries lack total_duration and snapshot_id but carry counts.
        let nested = try XCTUnwrap(snapshots[0].summary)
        XCTAssertEqual(nested.filesNew, 308)
        XCTAssertNil(nested.totalDuration)
        XCTAssertNil(nested.snapshotID)

        // Timestamps with fractional seconds and zone offset parse correctly.
        XCTAssertLessThan(snapshots[0].time, snapshots[1].time)
    }

    func testDecodeEveryRestoreProgressLine() throws {
        // Captured from a real `restic restore --json` run.
        let lines = try fixtureLines("restore-progress.jsonl")
        XCTAssertEqual(lines.count, 6)

        var statusCount = 0
        var summary: RestoreSummary?
        for line in lines {
            let event = try XCTUnwrap(
                ResticJSON.decodeRestoreEvent(fromLine: line),
                "Line failed to decode: \(line.prefix(120))"
            )
            switch event {
            case .status(let status):
                statusCount += 1
                XCTAssertGreaterThanOrEqual(status.percentDone, 0)
                XCTAssertLessThanOrEqual(status.percentDone, 1)
            case .summary(let value):
                XCTAssertNil(summary, "More than one summary event")
                summary = value
            }
        }
        XCTAssertEqual(statusCount, 5)
        let final = try XCTUnwrap(summary)
        XCTAssertEqual(final.filesRestored, 316)
        XCTAssertEqual(final.totalFiles, 316)
        XCTAssertEqual(final.bytesRestored, 400_614_400)
    }

    func testNonRestoreLinesAreIgnored() {
        XCTAssertNil(ResticJSON.decodeRestoreEvent(fromLine: ""))
        XCTAssertNil(ResticJSON.decodeRestoreEvent(fromLine: "not json"))
        XCTAssertNil(ResticJSON.decodeRestoreEvent(fromLine: #"{"message_type":"verbose_status"}"#))
    }

    func testDecodeRepoConfig() throws {
        // Captured from `restic cat config --json`; a successful decode is
        // how adopting an existing repository verifies its password.
        let config = try ResticJSON.decoder.decode(ResticRepoConfig.self, from: fixtureData("cat-config.json"))
        XCTAssertEqual(config.version, 2)
        XCTAssertEqual(config.id.count, 64)
    }

    func testDecodeStats() throws {
        let stats = try ResticJSON.decoder.decode(ResticStats.self, from: fixtureData("stats.json"))
        XCTAssertEqual(stats.snapshotsCount, 2)
        XCTAssertEqual(stats.totalFileCount, 633)
        XCTAssertGreaterThan(stats.totalSize, 0)
    }

    func testClassifyWrongPasswordFromRealStderr() throws {
        let stderr = String(decoding: try fixtureData("error-wrong-password.json"), as: UTF8.self)
        // Exit code 12 observed from restic 0.19.1 for wrong password.
        let error = ResticError.classify(exitCode: 12, stderr: stderr)
        guard case .wrongPassword(let message) = error else {
            return XCTFail("Expected wrongPassword, got \(error)")
        }
        XCTAssertTrue(message.contains("wrong password"))
        XCTAssertFalse(message.contains("message_type"), "Should surface the inner message, not raw JSON")
    }

    func testClassifyMissingRepositoryFromRealStderr() throws {
        let stderr = String(decoding: try fixtureData("error-no-repo.json"), as: UTF8.self)
        // Exit code 10 observed from restic 0.19.1 for missing repository.
        let error = ResticError.classify(exitCode: 10, stderr: stderr)
        guard case .repositoryDoesNotExist(let message) = error else {
            return XCTFail("Expected repositoryDoesNotExist, got \(error)")
        }
        XCTAssertTrue(message.contains("repository does not exist"))
    }

    func testClassifyRepositoryAlreadyExistsFromRealStderr() throws {
        // Captured from `restic init` against a folder already holding a repo
        // (exit code 1). Note restic's own doubled "Fatal: Fatal:" prefix.
        let stderr = String(decoding: try fixtureData("error-repo-exists.json"), as: UTF8.self)
        let error = ResticError.classify(exitCode: 1, stderr: stderr)
        guard case .repositoryAlreadyExists(let message) = error else {
            return XCTFail("Expected repositoryAlreadyExists, got \(error)")
        }
        XCTAssertFalse(message.hasPrefix("Fatal:"), "Fatal: prefixes should be stripped")
        XCTAssertTrue(message.contains("config file already exists"))
    }

    func testClassifyStripsFatalPrefixes() throws {
        let stderr = String(decoding: try fixtureData("error-wrong-password.json"), as: UTF8.self)
        let error = ResticError.classify(exitCode: 12, stderr: stderr)
        guard case .wrongPassword(let message) = error else {
            return XCTFail("Expected wrongPassword, got \(error)")
        }
        XCTAssertEqual(message, "wrong password or no key found")
    }

    func testClassifyUnknownExitCodeFallsBack() {
        let error = ResticError.classify(exitCode: 1, stderr: "some plain text failure")
        XCTAssertEqual(error, .commandFailed(exitCode: 1, message: "some plain text failure"))
    }

    func testNonProgressLinesAreIgnored() {
        XCTAssertNil(ResticJSON.decodeProgressEvent(fromLine: ""))
        XCTAssertNil(ResticJSON.decodeProgressEvent(fromLine: "not json"))
        XCTAssertNil(ResticJSON.decodeProgressEvent(fromLine: #"{"message_type":"verbose_status","action":"scan"}"#))
    }

    /// Unmodified `restic backup --json` stdout from restic 0.19.1 against a
    /// source tree holding two files with mode 000. The run ends on exit code
    /// 3, yet this summary proves restic wrote a snapshot anyway: one file
    /// archived, and `snapshot_id` present. That combination — a real snapshot
    /// missing whatever could not be read — is why exit code 3 gets its own
    /// case instead of a generic "command failed".
    func testPermissionDeniedRunStillWritesASnapshot() throws {
        let lines = try fixtureLines("backup-permission-denied.jsonl")
        XCTAssertEqual(lines.count, 1)

        let event = try XCTUnwrap(ResticJSON.decodeProgressEvent(fromLine: lines[0]))
        guard case .summary(let summary) = event else {
            return XCTFail("Expected a summary event")
        }
        XCTAssertEqual(summary.totalFilesProcessed, 1)
        XCTAssertNotNil(summary.snapshotID, "restic stores what it could read, then exits 3")
    }

    /// The stderr half of the same run: one `message_type: "error"` line per
    /// unreadable file, then the `exit_error` summary. This is the only place
    /// restic names the files, so it is what `unreadableItems` exists for.
    func testUnreadableItemsComeFromThePerFileErrorLines() throws {
        let stderr = String(decoding: try fixtureData("backup-permission-denied.stderr.jsonl"), as: UTF8.self)

        let items = ResticJSON.unreadableItems(inStderr: stderr)
        XCTAssertEqual(
            items,
            ["/tmp/keelhaven-fixture/src/b.txt", "/tmp/keelhaven-fixture/src/sub/c.txt"],
            "One item per unreadable file, in restic's own order"
        )
    }

    /// The closing `exit_error` line is not an item, and a human-readable
    /// `warning:` line (what the same run prints without `--json`) must not
    /// turn into a phantom path either.
    func testUnreadableItemsIgnoreEverythingThatIsNotAnErrorLine() {
        let stderr = """
        {"message_type":"exit_error","code":3,"message":"Warning: at least one source file could not be read"}
        warning: open /tmp/x.txt: permission denied
        not json at all
        """
        XCTAssertEqual(ResticJSON.unreadableItems(inStderr: stderr), [])
    }

    /// Some restic errors carry no `item`; the nested sentence is then the
    /// fallback, because a caller showing nothing is worse than showing a
    /// slightly wordy line.
    func testUnreadableItemFallsBackToTheErrorMessage() {
        let line = #"{"message_type":"error","error":{"message":"open /tmp/gone.txt: permission denied"}}"#
        let error = try? ResticJSON.decoder.decode(ResticSourceErrorMessage.self, from: Data(line.utf8))
        XCTAssertEqual(error?.unreadableItem, "open /tmp/gone.txt: permission denied")
    }
    func testClassifyExitCode3FromRealStderr() throws {
        let stderr = String(decoding: try fixtureData("backup-permission-denied.stderr.jsonl"), as: UTF8.self)

        let error = ResticError.classify(exitCode: 3, stderr: stderr)
        guard case .someSourcesUnreadable(let paths, let totalUnreadable, let message) = error else {
            return XCTFail("Expected someSourcesUnreadable, got \(error)")
        }
        XCTAssertEqual(paths, ["/tmp/keelhaven-fixture/src/b.txt", "/tmp/keelhaven-fixture/src/sub/c.txt"])
        XCTAssertEqual(totalUnreadable, 2)
        XCTAssertEqual(message, "Warning: at least one source file could not be read")
    }

    /// A denied folder yields one line per file, so the error payload is
    /// capped — but the count stays honest, which is what the row turns into
    /// "…and N more".
    func testClassifyCapsReportedPathsButNotTheCount() {
        let lines = (0..<50).map {
            #"{"message_type":"error","error":{"message":"open /tmp/f\#($0): permission denied"},"item":"/tmp/f\#($0)"}"#
        }
        let stderr = lines.joined(separator: "\n")

        let error = ResticError.classify(exitCode: 3, stderr: stderr)
        guard case .someSourcesUnreadable(let paths, let totalUnreadable, _) = error else {
            return XCTFail("Expected someSourcesUnreadable, got \(error)")
        }
        XCTAssertEqual(paths.count, ResticError.maxReportedUnreadablePaths)
        XCTAssertEqual(totalUnreadable, 50)
    }

    /// Exit code 3 with nothing parseable on stderr still has to be reported
    /// as what it is. `ResticRunnerProcessTests` covers the same shape through
    /// a fake binary that prints a non-JSON fatal line.
    func testClassifyExitCode3WithoutParseableItems() {
        let error = ResticError.classify(exitCode: 3, stderr: "Fatal: something went wrong")
        XCTAssertEqual(
            error,
            .someSourcesUnreadable(paths: [], totalUnreadable: 0, message: "something went wrong")
        )
    }
}
