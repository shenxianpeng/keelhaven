import XCTest
@testable import KeelhavenCore

/// End-to-end tests against a real restic binary. Skipped when restic is not
/// installed, so `swift test` stays green on bare CI machines.
final class ResticRunnerIntegrationTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testInitBackupSnapshotsAndErrorClassification() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        for index in 0..<20 {
            let file = sourceURL.appendingPathComponent("file\(index).txt")
            try Data("hello keelhaven \(index)\n".utf8).write(to: file)
        }

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)

        // init
        let initResult = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )
        XCTAssertEqual(initResult.messageType, "initialized")
        XCTAssertEqual(initResult.repository, repoURL.path)

        // streaming backup: must yield exactly one summary carrying a snapshot id
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

        // snapshots: sees exactly the snapshot the backup reported
        let snapshots = try await runner.run(
            .snapshots,
            destination: destination,
            credentials: credentials,
            decoding: [ResticSnapshot].self
        )
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, snapshotID)

        // cat config with the right password: how adoption verifies a repo
        let config = try await runner.run(
            .catConfig,
            destination: destination,
            credentials: credentials,
            decoding: ResticRepoConfig.self
        )
        XCTAssertEqual(config.version, 2)
        XCTAssertEqual(config.id.count, 64)

        // check: a healthy repository passes the integrity check the
        // scheduled-verification feature runs
        try await runner.runIgnoringOutput(
            .check,
            destination: destination,
            credentials: credentials
        )

        // forget --prune with a real keep policy: exits clean and keeps the
        // only snapshot (every preset keeps the three most recent)
        try await runner.runIgnoringOutput(
            .forget(retention: .month, performance: .off),
            destination: destination,
            credentials: credentials
        )
        let afterPrune = try await runner.run(
            .snapshots,
            destination: destination,
            credentials: credentials,
            decoding: [ResticSnapshot].self
        )
        XCTAssertEqual(afterPrune.count, 1)
        XCTAssertEqual(afterPrune[0].id, snapshotID)

        // restore the snapshot into a fresh target and verify the files
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

        // wrong password → typed error from the real exit code
        do {
            _ = try await runner.run(
                .snapshots,
                destination: destination,
                credentials: RepoCredentials(repositoryPassword: "wrong"),
                decoding: [ResticSnapshot].self
            )
            XCTFail("Expected wrongPassword error")
        } catch let error as ResticError {
            guard case .wrongPassword = error else {
                return XCTFail("Expected wrongPassword, got \(error)")
            }
        }

        // missing repository → typed error
        let missing = Destination.local(path: workDirectory.appendingPathComponent("nope").path)
        do {
            _ = try await runner.run(
                .snapshots,
                destination: missing,
                credentials: credentials,
                decoding: [ResticSnapshot].self
            )
            XCTFail("Expected repositoryDoesNotExist error")
        } catch let error as ResticError {
            guard case .repositoryDoesNotExist = error else {
                return XCTFail("Expected repositoryDoesNotExist, got \(error)")
            }
        }
    }

    /// The lock path, end to end against a real restic — the exact failure
    /// the menu bar's unlock button exists for.
    ///
    /// A backup killed outright (power cut, force quit) leaves its
    /// non-exclusive lock behind. Plain backups step around it, so the plan
    /// keeps looking healthy; `forget --prune` cannot, because it needs an
    /// exclusive lock, so retention fails with exit code 11 every week from
    /// then on and never reclaims a byte. `unlock` is what clears it.
    ///
    /// The lock is held by `backup --stdin` reading a pipe nothing writes to:
    /// it takes the lock immediately and holds it until EOF, so SIGKILL lands
    /// while the lock is definitely there. Backing up real files would race —
    /// it finishes, and releases the lock, before the kill.
    func testStaleLockBlocksPruneUntilUnlockClearsIt() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("lock test\n".utf8).write(to: sourceURL.appendingPathComponent("a.txt"))

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "lock-test-password")
        let runner = ResticRunner(binaryURL: binary)

        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )
        // A snapshot, so the retention pass below has something real to do.
        for try await _ in runner.backupStream(
            .backup(sources: [sourceURL.path], excludes: [], tag: "keelhaven-test", performance: .off, options: .off),
            destination: destination,
            credentials: credentials
        ) {}

        let holder = Process()
        holder.executableURL = binary
        holder.arguments = ["backup", "--stdin", "--stdin-filename", "held.txt"]
        holder.environment = [
            "RESTIC_REPOSITORY": repoURL.path,
            "RESTIC_PASSWORD": credentials.repositoryPassword,
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "TMPDIR": NSTemporaryDirectory(),
        ]
        let holderInput = Pipe()
        holder.standardInput = holderInput
        holder.standardOutput = FileHandle.nullDevice
        holder.standardError = FileHandle.nullDevice
        try holder.run()
        defer {
            try? holderInput.fileHandleForWriting.close()
            // No waitUntilExit here either — a wedged defer would hang
            // teardown (see the SIGKILL wait below).
            if holder.isRunning {
                holder.terminate()
            }
        }

        let locksURL = repoURL.appendingPathComponent("locks", isDirectory: true)
        func lockCount() -> Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: locksURL.path)) ?? []).count
        }
        var lockAppeared = false
        for _ in 0..<100 where !lockAppeared {
            if lockCount() == 0 {
                try await Task.sleep(nanoseconds: 50_000_000)
            } else {
                lockAppeared = true
            }
        }
        guard lockAppeared else {
            return XCTFail("The holder process never took a lock — test setup is broken")
        }

        // SIGKILL, not terminate: restic handles SIGTERM by releasing the
        // lock, which is precisely the case that needs no recovery.
        kill(holder.processIdentifier, SIGKILL)
        // Not waitUntilExit: Process can miss a SIGKILL'd child's death and
        // block forever (rare macOS race — it wedged both CI and local runs).
        // kill(pid, 0) asks the kernel directly: 0 while the pid exists,
        // ESRCH once it's gone. The lock file outlives the process either
        // way, so a bounded wait is all the assertion below needs.
        for _ in 0..<100 where kill(holder.processIdentifier, 0) == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(lockCount(), 1, "SIGKILL should have left the lock behind")

        // Backups are unaffected — the reason this failure hides so well.
        for try await _ in runner.backupStream(
            .backup(sources: [sourceURL.path], excludes: [], tag: "keelhaven-test", performance: .off, options: .off),
            destination: destination,
            credentials: credentials
        ) {}

        // Retention is not: exclusive lock, so exit code 11.
        do {
            try await runner.runIgnoringOutput(
                .forget(retention: .year, performance: .off),
                destination: destination,
                credentials: credentials
            )
            XCTFail("Expected the stale lock to block forget --prune")
        } catch let error as ResticError {
            guard case .repositoryLocked = error else {
                return XCTFail("Expected repositoryLocked, got \(error)")
            }
            XCTAssertTrue(error.isRepositoryLocked)
        }

        // The way out the unlock button takes.
        try await runner.runIgnoringOutput(
            .unlock,
            destination: destination,
            credentials: credentials
        )
        XCTAssertEqual(lockCount(), 0, "unlock left the stale lock behind")

        // Same command, now unblocked — the recovery actually recovers.
        try await runner.runIgnoringOutput(
            .forget(retention: .year, performance: .off),
            destination: destination,
            credentials: credentials
        )
    }

    func testMissingBinaryThrowsBinaryNotFound() async {
        let runner = ResticRunner(binaryURL: URL(fileURLWithPath: "/nonexistent/restic"))
        do {
            _ = try await runner.run(
                .snapshots,
                destination: .local(path: "/tmp"),
                credentials: RepoCredentials(repositoryPassword: "x"),
                decoding: [ResticSnapshot].self
            )
            XCTFail("Expected binaryNotFound")
        } catch let error as ResticError {
            XCTAssertEqual(error, .binaryNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// The performance flags are only useful if restic actually accepts them
    /// in the position we put them, and neither restic's docs nor a unit test
    /// can prove that — so a real run does. `--pack-size 8` and
    /// `--read-concurrency 1` are the smallest values restic allows, which
    /// keeps this as cheap as the other backups here.
    func testBackupAcceptsPerformanceFlags() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("perf-repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("perf-src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("hello keelhaven\n".utf8).write(to: sourceURL.appendingPathComponent("file.txt"))

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        let performance = PerformanceOptions(
            uploadLimitKiBPerSecond: 4096,
            readConcurrency: 1,
            packSizeMiB: 4
        )
        var summary: BackupSummary?
        let stream = runner.backupStream(
            .backup(sources: [sourceURL.path], excludes: [], tag: "keelhaven-test", performance: performance, options: .off),
            destination: destination,
            credentials: credentials
        )
        for try await event in stream {
            if case .summary(let value) = event {
                summary = value
            }
        }
        XCTAssertNotNil(summary?.snapshotID, "restic rejected the performance flags")

        // The same options on forget must be accepted too — this is where a
        // stray --read-concurrency would surface as a usage error.
        try await runner.runIgnoringOutput(
            .forget(retention: .year, performance: performance),
            destination: destination,
            credentials: credentials
        )
    }

    /// `--exclude-caches` against the real binary: a directory carrying a
    /// `CACHEDIR.TAG` must not reach the snapshot. Asserted by restoring the
    /// snapshot and looking, not by trusting the summary counts — the counts
    /// would also look right if restic silently ignored the flag.
    func testExcludeCachesSkipsTaggedDirectories() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        let cacheURL = sourceURL.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try Data("keep me\n".utf8).write(to: sourceURL.appendingPathComponent("keep.txt"))
        try Data("junk\n".utf8).write(to: cacheURL.appendingPathComponent("junk.bin"))
        // The exact marker the Cache Directory Tagging Standard defines.
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n".utf8)
            .write(to: cacheURL.appendingPathComponent("CACHEDIR.TAG"))

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        var summary: BackupSummary?
        let stream = runner.backupStream(
            .backup(
                sources: [sourceURL.path],
                excludes: [],
                tag: "keelhaven-test",
                performance: .off,
                options: BackupOptions(excludeCaches: true)
            ),
            destination: destination,
            credentials: credentials
        )
        for try await event in stream {
            if case .summary(let value) = event { summary = value }
        }
        let snapshotID = try XCTUnwrap(summary?.snapshotID)

        let targetURL = workDirectory.appendingPathComponent("restored", isDirectory: true)
        try await runner.runIgnoringOutput(
            .restore(snapshotID: snapshotID, target: targetURL.path),
            destination: destination,
            credentials: credentials
        )

        let restoredRoot = targetURL.appendingPathComponent(sourceURL.path)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: restoredRoot.appendingPathComponent("keep.txt").path),
            "The untagged file should have been backed up"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: restoredRoot.appendingPathComponent("Cache/junk.bin").path),
            "A CACHEDIR.TAG directory should have been excluded"
        )
    }

    /// `--skip-if-unchanged` against the real binary, twice over an untouched
    /// source. Pins the two things the app depends on: the second run creates
    /// no snapshot, and its summary omits `snapshot_id` — which is the only
    /// signal `AppState` has for reporting "nothing was stored" (issue #46).
    ///
    /// Not run from `workDirectory`. That lives under `$TMPDIR`, which macOS
    /// writes to constantly, and restic stores the **whole ancestor chain** in
    /// the snapshot tree — so one unrelated process creating a temp file makes
    /// the second snapshot differ even though no backed-up file did.
    /// Confirmed with `restic diff`: 0 files and 0 dirs changed, 5 tree blobs
    /// replaced, and `restic ls --long` showing only `$TMPDIR`'s own mtime
    /// moving. `/private/tmp` is quiet enough that this does not happen; if it
    /// does anyway, the test skips rather than failing on someone else's write.
    func testSkipIfUnchangedOmitsSnapshotIDOnTheSecondRun() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let root = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath()
            .appendingPathComponent("KeelhavenSkipIfUnchanged-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("unchanging\n".utf8).write(to: sourceURL.appendingPathComponent("a.txt"))

        let destination = Destination.local(path: root.appendingPathComponent("repo").path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        func backup() async throws -> BackupSummary? {
            var summary: BackupSummary?
            let stream = runner.backupStream(
                .backup(
                    sources: [sourceURL.path],
                    excludes: [],
                    tag: "keelhaven-test",
                    performance: .off,
                    options: BackupOptions(skipIfUnchanged: true)
                ),
                destination: destination,
                credentials: credentials
            )
            for try await event in stream {
                if case .summary(let value) = event { summary = value }
            }
            return summary
        }

        let firstSummary = try await backup()
        let first = try XCTUnwrap(firstSummary)
        XCTAssertNotNil(first.snapshotID, "The first run must create a snapshot")

        let secondSummary = try await backup()
        let second = try XCTUnwrap(secondSummary)

        // True whether or not a snapshot was written: nothing in the source
        // moved. A regression that stopped passing the flag, or broke exclude
        // handling, would fail here rather than reaching the skip below.
        XCTAssertEqual(second.filesNew, 0)
        XCTAssertEqual(second.filesChanged, 0)
        XCTAssertEqual(second.filesUnmodified, 1)

        if second.snapshotID != nil {
            throw XCTSkip(
                "A directory above the source changed while the test ran, so the "
                + "snapshot legitimately differed. Nothing in the source did."
            )
        }

        let snapshots = try await runner.run(
            .snapshots,
            destination: destination,
            credentials: credentials,
            decoding: [ResticSnapshot].self
        )
        XCTAssertEqual(snapshots.count, 1)
    }

    /// `--one-file-system` against the real binary, with a real second
    /// volume mounted inside the source — the only arrangement where the
    /// flag does anything at all.
    ///
    /// A disk image is created and attached under the source folder, so the
    /// backup has a genuine filesystem boundary to stop at. Asserted by
    /// listing the snapshot rather than by trusting the summary counts: a
    /// restic that silently ignored the flag would report plausible numbers.
    /// Skips, rather than fails, when `hdiutil` cannot create or attach the
    /// image — the same self-skipping rule the rest of this suite follows.
    func testOneFileSystemStopsAtAMountedVolume() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        let mountURL = sourceURL.appendingPathComponent("mounted", isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        try Data("on the main disk\n".utf8).write(to: sourceURL.appendingPathComponent("keep.txt"))

        let imageURL = workDirectory.appendingPathComponent("volume.dmg")
        guard Self.run("/usr/bin/hdiutil", [
            "create", "-size", "10m", "-fs", "HFS+", "-volname", "KeelhavenTest",
            "-quiet", imageURL.path,
        ]) else {
            throw XCTSkip("hdiutil could not create a disk image here")
        }
        guard Self.run("/usr/bin/hdiutil", [
            "attach", imageURL.path, "-mountpoint", mountURL.path, "-nobrowse", "-quiet",
        ]) else {
            throw XCTSkip("hdiutil could not attach a disk image here")
        }
        defer { _ = Self.run("/usr/bin/hdiutil", ["detach", mountURL.path, "-quiet"]) }

        try Data("on the other volume\n".utf8)
            .write(to: mountURL.appendingPathComponent("other.txt"))

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        func backup(oneFileSystem: Bool) async throws -> BackupSummary? {
            var summary: BackupSummary?
            let stream = runner.backupStream(
                .backup(
                    sources: [sourceURL.path],
                    excludes: [],
                    tag: "keelhaven-test",
                    performance: .off,
                    options: BackupOptions(oneFileSystem: oneFileSystem)
                ),
                destination: destination,
                credentials: credentials
            )
            for try await event in stream {
                if case .summary(let value) = event { summary = value }
            }
            return summary
        }

        // Without the flag, the mounted volume is followed into.
        let withoutSummary = try await backup(oneFileSystem: false)
        let withoutID = try XCTUnwrap(try XCTUnwrap(withoutSummary).snapshotID)
        let withoutFiles = try await Self.restoredFileNames(
            runner: runner,
            snapshotID: withoutID,
            destination: destination,
            credentials: credentials,
            sourcePath: sourceURL.path,
            target: workDirectory.appendingPathComponent("restored-without", isDirectory: true)
        )
        XCTAssertTrue(withoutFiles.contains("keep.txt"))
        XCTAssertTrue(
            withoutFiles.contains("mounted/other.txt"),
            "Without the flag restic should cross into the mounted volume"
        )

        // With it, the boundary is respected.
        let withSummary = try await backup(oneFileSystem: true)
        let withID = try XCTUnwrap(try XCTUnwrap(withSummary).snapshotID)
        let withFiles = try await Self.restoredFileNames(
            runner: runner,
            snapshotID: withID,
            destination: destination,
            credentials: credentials,
            sourcePath: sourceURL.path,
            target: workDirectory.appendingPathComponent("restored-with", isDirectory: true)
        )
        XCTAssertTrue(withFiles.contains("keep.txt"), "The folder's own files must still be backed up")
        XCTAssertFalse(
            withFiles.contains("mounted/other.txt"),
            "A file on a volume mounted inside the source should have been skipped"
        )
    }

    /// Restores a snapshot and returns the paths inside it, relative to the
    /// backed-up folder — the only way to see what restic actually stored.
    private static func restoredFileNames(
        runner: ResticRunner,
        snapshotID: String,
        destination: Destination,
        credentials: RepoCredentials,
        sourcePath: String,
        target: URL
    ) async throws -> Set<String> {
        try await runner.runIgnoringOutput(
            .restore(snapshotID: snapshotID, target: target.path),
            destination: destination,
            credentials: credentials
        )
        let root = target.appendingPathComponent(sourcePath)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var found: Set<String> = []
        for case let path as String in walker {
            var isDirectory: ObjCBool = false
            let full = root.appendingPathComponent(path).path
            if FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                found.insert(path)
            }
        }
        return found
    }

    /// Runs a command and reports whether it succeeded, so the caller can
    /// skip instead of failing when the environment will not cooperate.
    private static func run(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
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

    /// The guarantee the whole feature rests on: a preview reports what a
    /// backup would store and leaves the repository exactly as it found it
    /// (issue #43). Asserted against the real binary by counting snapshots
    /// before and after, not by trusting the summary.
    func testPreviewBackupReportsWorkWithoutWritingASnapshot() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        for index in 0..<5 {
            try Data("hello \(index)\n".utf8)
                .write(to: sourceURL.appendingPathComponent("file\(index).txt"))
        }

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        func snapshotCount() async throws -> Int {
            try await runner.run(
                .snapshots,
                destination: destination,
                credentials: credentials,
                decoding: [ResticSnapshot].self
            ).count
        }

        func preview() async throws -> BackupSummary? {
            var summary: BackupSummary?
            let stream = runner.backupStream(
                .previewBackup(
                    sources: [sourceURL.path],
                    excludes: [],
                    tag: "keelhaven-test",
                    performance: .off,
                    options: .off
                ),
                destination: destination,
                credentials: credentials
            )
            for try await event in stream {
                if case .summary(let value) = event { summary = value }
            }
            return summary
        }

        // Previewing an empty repository: everything is new, nothing is stored.
        let countBefore = try await snapshotCount()
        XCTAssertEqual(countBefore, 0)
        let firstSummary = try await preview()
        let first = try XCTUnwrap(firstSummary)
        XCTAssertEqual(first.filesNew, 5)
        XCTAssertEqual(first.dryRun, true)
        let countAfterPreview = try await snapshotCount()
        XCTAssertEqual(countAfterPreview, 0, "A preview must not create a snapshot")

        // And again after a real backup: now nothing is new, and the
        // repository still holds exactly the one snapshot the backup wrote.
        var backupSummary: BackupSummary?
        let backupStream = runner.backupStream(
            .backup(
                sources: [sourceURL.path], excludes: [], tag: "keelhaven-test",
                performance: .off, options: .off
            ),
            destination: destination,
            credentials: credentials
        )
        for try await event in backupStream {
            if case .summary(let value) = event { backupSummary = value }
        }
        XCTAssertNil(try XCTUnwrap(backupSummary).dryRun, "A real backup is not marked as a dry run")
        let countAfterBackup = try await snapshotCount()
        XCTAssertEqual(countAfterBackup, 1)

        let secondSummary = try await preview()
        let second = try XCTUnwrap(secondSummary)
        XCTAssertEqual(second.filesNew, 0)
        XCTAssertEqual(second.filesChanged, 0)
        let countAfterSecondPreview = try await snapshotCount()
        XCTAssertEqual(
            countAfterSecondPreview, 1,
            "A preview after a backup must still leave the snapshot count alone"
        )
    }

    /// `--no-scan` against the real binary. Two things must both hold, and
    /// they pull in opposite directions (issue #51): the progress fields the
    /// row needs really do go missing, and the backup itself is otherwise
    /// completely normal — the option must cost the estimate, not the data.
    func testNoScanDropsTheEstimateButNotTheBackup() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        // Enough bytes that restic emits status lines at all; a handful of
        // small files finishes before the first one is due.
        for index in 0..<40 {
            try Data(repeating: UInt8(index % 251), count: 2_000_000)
                .write(to: sourceURL.appendingPathComponent("file\(index).bin"))
        }

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        var statuses: [BackupStatusMessage] = []
        var summary: BackupSummary?
        let stream = runner.backupStream(
            .backup(
                sources: [sourceURL.path],
                excludes: [],
                tag: "keelhaven-test",
                performance: .off,
                options: BackupOptions(noScan: true)
            ),
            destination: destination,
            credentials: credentials
        )
        for try await event in stream {
            switch event {
            case .status(let status): statuses.append(status)
            case .summary(let value): summary = value
            }
        }

        // The backup is real: a snapshot exists and the summary is complete.
        let final = try XCTUnwrap(summary)
        XCTAssertEqual(final.filesNew, 40)
        XCTAssertNotNil(final.snapshotID)
        XCTAssertNotNil(final.dataAdded)
        let snapshots = try await runner.run(
            .snapshots,
            destination: destination,
            credentials: credentials,
            decoding: [ResticSnapshot].self
        )
        XCTAssertEqual(snapshots.count, 1)

        // And the estimate is gone, which is what the row has to handle.
        // Status lines are timing-dependent, so assert on them only if restic
        // emitted any — the summary assertions above carry the test otherwise.
        for status in statuses {
            XCTAssertNil(status.totalBytes, "--no-scan must not report a total")
            XCTAssertEqual(status.percentDone, 0, "--no-scan must not report progress")
        }
    }

    /// `keep the last N` against the real binary. A retention setting is the
    /// only thing in the app that deletes, so "it renders the right flag" is
    /// not enough — this makes five snapshots, keeps two, and counts what is
    /// left (issue #52).
    func testKeepLastActuallyLeavesOnlyThatManySnapshots() async throws {
        guard let binary = IntegrationTestSupport.locateRestic() else {
            throw XCTSkip("restic is not installed; run: brew install restic")
        }

        let repoURL = workDirectory.appendingPathComponent("repo", isDirectory: true)
        let sourceURL = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        let destination = Destination.local(path: repoURL.path)
        let credentials = RepoCredentials(repositoryPassword: "integration-test-password")
        let runner = ResticRunner(binaryURL: binary)
        _ = try await runner.run(
            .initRepository,
            destination: destination,
            credentials: credentials,
            decoding: ResticInitResult.self
        )

        // Five distinct snapshots: each run changes a file, so none is skipped.
        for index in 0..<5 {
            try Data("revision \(index)\n".utf8)
                .write(to: sourceURL.appendingPathComponent("a.txt"))
            let stream = runner.backupStream(
                .backup(
                    sources: [sourceURL.path], excludes: [], tag: "keelhaven-test",
                    performance: .off, options: .off
                ),
                destination: destination,
                credentials: credentials
            )
            for try await _ in stream {}
        }

        func snapshotCount() async throws -> Int {
            try await runner.run(
                .snapshots,
                destination: destination,
                credentials: credentials,
                decoding: [ResticSnapshot].self
            ).count
        }
        let before = try await snapshotCount()
        XCTAssertEqual(before, 5)

        try await runner.runIgnoringOutput(
            .forget(retention: .lastN(2), performance: .off),
            destination: destination,
            credentials: credentials
        )

        let after = try await snapshotCount()
        XCTAssertEqual(after, 2, "keep the last 2 must leave exactly two snapshots")

        // And the repository is still sound after the prune rewrote it.
        try await runner.runIgnoringOutput(
            .check,
            destination: destination,
            credentials: credentials
        )
    }
}

