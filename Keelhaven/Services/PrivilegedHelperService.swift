import Foundation
import ServiceManagement
import KeelhavenCore

/// The app's end of the privileged helper: registering it with launchd, and
/// running a plan's backup through it as root.
///
/// The helper does the reading; this side still does everything else. Its
/// stdout is decoded with the same `ResticJSON` and its failures classified
/// with the same `ResticError.classify` as a user-level run, so a plan's row,
/// run record and notifications cannot tell the two apart.
enum PrivilegedHelperService {
    enum Availability: Equatable {
        /// Ad-hoc or unsigned: there is no team for the helper to check the
        /// app against, so it would refuse every connection.
        case unavailableInThisBuild
        case notRegistered
        /// Registered, waiting for the user in System Settings › Login Items.
        case requiresApproval
        case enabled
    }

    private static var daemon: SMAppService {
        .daemon(plistName: PrivilegedHelper.launchDaemonPlistName)
    }

    /// What the helper must be: our own helper, signed by our own team.
    private static var helperRequirement: String? {
        CodeSigning.sameTeamRequirement(identifier: PrivilegedHelper.helperIdentifier)
    }

    static var availability: Availability {
        guard helperRequirement != nil else { return .unavailableInThisBuild }
        switch daemon.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .notRegistered
        }
    }

    /// Registers the daemon. The first time, macOS leaves it waiting for the
    /// user's approval rather than running it — and reports that as an
    /// error from `register()`, which is the expected path, not a failure.
    /// So the outcome is read back from `availability`, and only an error
    /// that left the helper unregistered is passed on.
    static func register() throws {
        do {
            try daemon.register()
        } catch {
            if availability == .notRegistered {
                throw error
            }
        }
    }

    static func unregister() async throws {
        try await daemon.unregister()
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The helper's equivalent of `ResticRunner.backupStream`, with the same
    /// lifecycle: cancelling the consuming task stops restic with SIGINT,
    /// and the stream simply ends.
    static func backupStream(_ request: PrivilegedBackupRequest) -> AsyncThrowingStream<BackupProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let requirement = helperRequirement else {
                continuation.finish(throwing: PrivilegedHelperError.unavailableInThisBuild)
                return
            }
            guard availability == .enabled else {
                continuation.finish(throwing: PrivilegedHelperError.notEnabled)
                return
            }
            let data: Data
            do {
                data = try request.encoded()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let runID = UUID().uuidString
            let connection = NSXPCConnection(machServiceName: PrivilegedHelper.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperXPC.self)
            connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperClientXPC.self)
            connection.exportedObject = OutputReceiver { line in
                if let event = ResticJSON.decodeProgressEvent(fromLine: line) {
                    continuation.yield(event)
                }
            }
            connection.setCodeSigningRequirement(requirement)
            connection.resume()

            let helper = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.finish(throwing: PrivilegedHelperError.connectionFailed(error.localizedDescription))
                connection.invalidate()
            } as? PrivilegedHelperXPC

            // Messages on one connection arrive in the order they were sent,
            // so every output line has been delivered before this reply.
            helper?.runBackup(data, runID: runID) { exitCode, stderr, failure in
                if let failure {
                    let error = (try? JSONDecoder().decode(PrivilegedBackupError.self, from: failure))
                        ?? PrivilegedBackupError.helperFault("unreadable reply")
                    continuation.finish(throwing: error)
                } else if exitCode == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ResticError.classify(
                        exitCode: exitCode,
                        stderr: String(decoding: stderr, as: UTF8.self)
                    ))
                }
                connection.invalidate()
            }

            continuation.onTermination = { termination in
                // The connection stays open until the reply, so the helper
                // can finish restic's shutdown and the ownership hand-back.
                if case .cancelled = termination {
                    helper?.cancelBackup(runID: runID)
                }
            }
        }
    }
}

private final class OutputReceiver: NSObject, PrivilegedHelperClientXPC {
    private let receive: (String) -> Void

    init(_ receive: @escaping (String) -> Void) {
        self.receive = receive
    }

    func receiveOutputLine(_ line: String, runID: String) {
        receive(line)
    }
}

enum PrivilegedHelperError: LocalizedError, Equatable {
    case unavailableInThisBuild
    case notEnabled
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailableInThisBuild:
            return String(localized: "This plan reads files as administrator, which needs a copy of Keelhaven signed with a Developer ID. Turn the setting off in Edit Plan, or install a signed build.")
        case .notEnabled:
            return String(localized: "This plan reads files as administrator, but Keelhaven's helper isn't allowed to run. Open Edit Plan › Administrator access to turn it on.")
        case .connectionFailed(let detail):
            return String(localized: "Keelhaven could not reach its administrator helper. \(detail)")
        }
    }
}
