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
    public nonisolated func backupStream(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials
    ) -> AsyncThrowingStream<BackupProgressEvent, Error> {
        eventStream(
            command,
            destination: destination,
            credentials: credentials,
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
            command,
            destination: destination,
            credentials: credentials,
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
            command,
            destination: destination,
            credentials: credentials,
            decodeLine: ResticJSON.decodeLsEvent(fromLine:)
        )
    }

    /// Shared subprocess JSON-lines pipeline behind both streams.
    private nonisolated func eventStream<Event: Sendable>(
        _ command: ResticCommand,
        destination: Destination,
        credentials: RepoCredentials,
        decodeLine: @escaping @Sendable (String) -> Event?
    ) -> AsyncThrowingStream<Event, Error> {
        let binaryURL = self.binaryURL
        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = command.arguments
            process.environment = credentials.environment(for: destination)
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

                async let stderrData = ResticRunner.collect(stderrPipe.fileHandleForReading)

                // A stdout read failure just ends the loop; the exit code decides.
                var lines = stdoutPipe.fileHandleForReading.bytes.lines.makeAsyncIterator()
                while let line = (try? await lines.next()) ?? nil {
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
                    continuation.finish(throwing: ResticError.classify(exitCode: exitCode, stderr: stderrText))
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
        // output can never fill the pipe buffer and deadlock the child.
        async let stdoutData = ResticRunner.collect(stdoutPipe.fileHandleForReading)
        async let stderrData = ResticRunner.collect(stderrPipe.fileHandleForReading)

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

    private static func collect(_ handle: FileHandle) async -> Data {
        var data = Data()
        // A read failure just ends collection early — partial output is
        // still useful for error reporting.
        var bytes = handle.bytes.makeAsyncIterator()
        while let byte = (try? await bytes.next()) ?? nil {
            data.append(byte)
        }
        return data
    }
}
