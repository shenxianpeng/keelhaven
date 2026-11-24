import Foundation

/// Executes restic as a child process.
///
/// One-shot commands (`init`, `snapshots`, `stats`) collect stdout and decode
/// it in one go via `run(_:destination:credentials:decoding:)`. Backups stream
/// their JSON-lines progress through `backupStream(...)`.
public actor ResticRunner {
    public let binaryURL: URL

    public init(binaryURL: URL) {
        self.binaryURL = binaryURL
    }

    // MARK: - One-shot commands

    public func run<Output: Decodable>(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials,
        decoding type: Output.Type
    ) async throws -> Output {
        let result = try await execute(command, destination: destination, credentials: credentials)
        guard result.exitCode == 0 else {
            throw ResticError.classify(exitCode: result.exitCode, stderr: result.stderrText)
        }
        do {
            return try ResticJSON.decoder.decode(type, from: result.stdout)
        } catch {
            throw ResticError.outputDecodingFailed(message: String(describing: error))
        }
    }

    /// Like `run`, for commands whose output we don't need (e.g. `check`).
    public func runIgnoringOutput(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials
    ) async throws {
        let result = try await execute(command, destination: destination, credentials: credentials)
        guard result.exitCode == 0 else {
            throw ResticError.classify(exitCode: result.exitCode, stderr: result.stderrText)
        }
    }

    // MARK: - Streaming commands

    /// Runs `restic backup` and yields decoded progress events as they arrive.
    /// The stream finishes after the summary event on success, or throws a
    /// `ResticError` on failure. Cancelling the consuming task sends SIGINT to
    /// restic, which exits and unlocks the repository cleanly.
    ///
    /// A cancelled stream ends the way consumer cancellation always ends an
    /// `AsyncThrowingStream`: iteration simply stops — no summary, nothing
    /// thrown. A consumer that must not mistake a stop for a finished run
    /// checks `Task.isCancelled` after its loop.
    public nonisolated func backupStream(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials
    ) -> AsyncThrowingStream<BackupProgressEvent, Error> {
        eventStream(
            arguments: command.arguments,
            environment: credentials.environment(for: destination),
            failure: ResticError.classify(exitCode:stderr:),
            decodeLine: ResticJSON.decodeProgressEvent(fromLine:)
        )
    }

    /// Runs `restic restore` with the same lifecycle as `backupStream`.
    public nonisolated func restoreStream(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials
    ) -> AsyncThrowingStream<RestoreProgressEvent, Error> {
        eventStream(
            arguments: command.arguments,
            environment: credentials.environment(for: destination),
            failure: ResticError.classify(exitCode:stderr:),
            decodeLine: ResticJSON.decodeRestoreEvent(fromLine:)
        )
    }

    /// Runs `restic ls`, yielding the snapshot header and then one node per
    /// entry, with the same lifecycle as the other streams.
    ///
    /// A stream rather than a collected array because this is the slowest thing
    /// the app asks restic to do on a remote repository — measured at ~5.6 s
    /// for 60 000 files over SFTP at 60 ms RTT (`Scripts/bench-remote-ls.sh`) —
    /// so the window needs to show that it is working and let the user out.
    /// Cancelling sends SIGINT through the same path a cancelled backup uses.
    public nonisolated func listStream(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials
    ) -> AsyncThrowingStream<ResticLsEvent, Error> {
        eventStream(
            arguments: command.arguments,
            environment: credentials.environment(for: destination),
            failure: ResticError.classify(exitCode:stderr:),
            decodeLine: ResticJSON.decodeLsEvent(fromLine:)
        )
    }

    /// Runs restic with exactly these arguments and environment, yielding
    /// stdout a line at a time, undecoded. A non-zero exit throws
    /// `ResticProcessExit` carrying the code and stderr as they came.
    ///
    /// For the privileged helper, which runs restic as root on the app's
    /// behalf and hands the raw output back over XPC: the app decodes and
    /// classifies it there, with the same code every other stream uses, so
    /// a root backup can never report itself differently from a user one.
    /// Same lifecycle as the other streams — cancelling sends SIGINT.
    ///
    /// `interrupt` is the other way to stop it, for a caller that has to
    /// know when restic is really gone: SIGINT without ending the stream,
    /// which then runs on to restic's own exit. The helper needs that,
    /// because it hands a local repository's files back to the user only
    /// after restic has written its last one.
    public nonisolated func lineStream(
        arguments: [String],
        environment: [String: String],
        interrupt: ResticInterrupt? = nil
    ) -> AsyncThrowingStream<String, Error> {
        eventStream(
            arguments: arguments,
            environment: environment,
            interrupt: interrupt,
            failure: { ResticProcessExit(exitCode: $0, stderr: $1) },
            decodeLine: { $0 }
        )
    }

    /// Shared subprocess JSON-lines pipeline behind every stream.
    private nonisolated func eventStream<Event: Sendable>(
        arguments: [String],
        environment: [String: String],
        interrupt: ResticInterrupt? = nil,
        failure: @escaping @Sendable (Int32, String) -> Error,
        decodeLine: @escaping @Sendable (String) -> Event?
    ) -> AsyncThrowingStream<Event, Error> {
        let binaryURL = self.binaryURL
        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Install the termination bridge before launching so an early exit
            // can never be missed.
            let exitCodes = Self.exitCodeStream(for: process)

            let worker = Task {
                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: ResticError.binaryNotFound)
                    return
                }
                interrupt?.attach(process)

                // Both pipes are drained while the process runs, each on its
                // own thread — see `PipeReader` for what happens otherwise.
                async let stderrData = PipeReader.collect(stderrPipe.fileHandleForReading)

                for await line in PipeReader.lines(of: stdoutPipe.fileHandleForReading) {
                    if let event = decodeLine(line) {
                        continuation.yield(event)
                    }
                }

                var exitCode: Int32 = -1
                for await code in exitCodes {
                    exitCode = code
                }

                if exitCode == 0 {
                    continuation.finish()
                } else {
                    let stderrText = String(decoding: await stderrData, as: UTF8.self)
                    continuation.finish(throwing: failure(exitCode, stderrText))
                }
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                if process.isRunning {
                    process.interrupt() // SIGINT: restic unlocks and exits
                }
                worker.cancel()
            }
        }
    }

    // MARK: - Process plumbing

    private struct ExecutionResult {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data

        var stderrText: String {
            String(decoding: stderr, as: UTF8.self)
        }
    }

    private func execute(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials
    ) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = command.arguments
        process.environment = credentials.environment(for: destination)
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exitCodes = Self.exitCodeStream(for: process)

        do {
            try process.run()
        } catch {
            throw ResticError.binaryNotFound
        }

        // Read both pipes concurrently with the running process so a large
        // output can never fill the pipe buffer and deadlock the child. That
        // only holds if the two reads do not queue behind one another, which
        // is what `PipeReader` is for.
        async let stdoutData = PipeReader.collect(stdoutPipe.fileHandleForReading)
        async let stderrData = PipeReader.collect(stderrPipe.fileHandleForReading)

        var exitCode: Int32 = -1
        for await code in exitCodes {
            exitCode = code
        }

        return ExecutionResult(exitCode: exitCode, stdout: await stdoutData, stderr: await stderrData)
    }

    /// Bridges `Process`'s termination handler into an `AsyncStream` so the
    /// exit status can be awaited alongside output collection. Must be
    /// installed before `run()` so an early exit is never missed.
    private static func exitCodeStream(for process: Process) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }
    }
}

/// A stop button for one `lineStream` run that leaves the stream running
/// until restic has exited. Safe to press before restic has started (it is
/// sent the moment it does) and more than once.
public final class ResticInterrupt: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var requested = false

    public init() {}

    public func interrupt() {
        lock.withLock {
            requested = true
            if let process, process.isRunning {
                process.interrupt()
            }
        }
    }

    func attach(_ process: Process) {
        lock.withLock {
            self.process = process
            if requested {
                process.interrupt()
            }
        }
    }
}

/// How a `lineStream` run ended when restic exited non-zero: the code and
/// stderr exactly as restic left them, for the receiving side to classify
/// with `ResticError.classify`.
public struct ResticProcessExit: Error, Equatable, Sendable {
    public let exitCode: Int32
    public let stderr: String

    public init(exitCode: Int32, stderr: String) {
        self.exitCode = exitCode
        self.stderr = stderr
    }
}
