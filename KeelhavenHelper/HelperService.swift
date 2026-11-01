import Foundation
import KeelhavenCore
import os

/// One connection's worth of the helper: runs the backups that app asks for.
final class HelperService: NSObject, PrivilegedHelperXPC {
    private let log = Logger(subsystem: PrivilegedHelper.machServiceName, category: "backup")
    private weak var connection: NSXPCConnection?
    private let lock = NSLock()
    private var interrupts: [String: ResticInterrupt] = [:]

    private static let activeRuns = OSAllocatedUnfairLock(initialState: 0)
    static var anyRunActive: Bool { activeRuns.withLock { $0 > 0 } }

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func runBackup(_ request: Data, runID: String, reply: @escaping (Int32, Data, Data?) -> Void) {
        guard let connection else { return }
        let uid = connection.effectiveUserIdentifier
        let client = connection.remoteObjectProxyWithErrorHandler { _ in } as? PrivilegedHelperClientXPC
        let interrupt = ResticInterrupt()
        lock.withLock { interrupts[runID] = interrupt }
        Self.activeRuns.withLock { $0 += 1 }

        Task {
            let outcome = await self.perform(request, uid: uid, interrupt: interrupt) { line in
                client?.receiveOutputLine(line, runID: runID)
            }
            self.lock.withLock { _ = self.interrupts.removeValue(forKey: runID) }
            Self.activeRuns.withLock { $0 -= 1 }
            switch outcome {
            case .exited(let code, let stderr):
                reply(code, Data(stderr.utf8), nil)
            case .refused(let error):
                self.log.error("Backup refused: \(String(describing: error), privacy: .public)")
                reply(-1, Data(), try? JSONEncoder().encode(error))
            }
        }
    }

    func cancelBackup(runID: String) {
        lock.withLock { interrupts[runID] }?.interrupt()
    }

    func interruptAll() {
        lock.withLock { Array(interrupts.values) }.forEach { $0.interrupt() }
    }

    // MARK: - One run

    private enum Outcome {
        case exited(Int32, String)
        case refused(PrivilegedBackupError)
    }

    private func perform(
        _ data: Data,
        uid: uid_t,
        interrupt: ResticInterrupt,
        send: @escaping (String) -> Void
    ) async -> Outcome {
        let request: PrivilegedBackupRequest
        let user: RequestingUser
        let restic: URL
        let invocation: PrivilegedInvocation
        do {
            request = try PrivilegedBackupRequest.decoded(from: data)
            user = try UserAccounts.user(uid: uid)
            restic = try HelperFiles.verifiedResticCopy()
            invocation = try PrivilegedInvocation(
                request: request,
                user: user,
                cacheDirectory: try HelperFiles.cacheDirectory(uid: uid).path
            )
        } catch let error as PrivilegedBackupError {
            return .refused(error)
        } catch {
            return .refused(.helperFault(String(describing: error)))
        }
        defer { try? FileManager.default.removeItem(at: restic) }

        log.info("Backing up \(request.sources.count) folder(s) as root for uid \(uid, privacy: .public)")
        // A second of slack: birth times are taken from the volume's clock,
        // and nothing written by this run can predate its own start by more.
        let start = Date().addingTimeInterval(-1)
        let outcome: Outcome
        do {
            for try await line in ResticRunner(binaryURL: restic).lineStream(
                arguments: invocation.arguments,
                environment: invocation.environment,
                interrupt: interrupt
            ) {
                send(line)
            }
            outcome = .exited(0, "")
        } catch let exit as ResticProcessExit {
            outcome = .exited(exit.exitCode, exit.stderr)
        } catch {
            outcome = .refused(.resticUnavailable)
        }

        // restic has exited, so it has written everything it ever will.
        if case .local(let path) = request.destination {
            do {
                let count = try RepositoryOwnership.reassign(
                    repositoryAt: path, from: 0, to: user.uid, group: user.gid, createdSince: start
                )
                log.info("Returned \(count) repository entries to uid \(uid, privacy: .public)")
            } catch {
                log.error("Left repository ownership alone: \(String(describing: error), privacy: .public)")
            }
        }
        return outcome
    }
}
