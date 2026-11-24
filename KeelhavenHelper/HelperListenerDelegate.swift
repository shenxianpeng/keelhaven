import Foundation
import KeelhavenCore
import os

/// Decides who may talk to the helper at all.
///
/// Two conditions, both required, because the helper reads any file on the
/// Mac on request:
///
/// - **Keelhaven, signed by this helper's own team.** Enforced by the
///   connection itself (`setCodeSigningRequirement`), against the caller's
///   running code, so a modified copy of the app or anything else claiming
///   to be it is cut off. An ad-hoc build has no team, and then no
///   connection is accepted at all.
/// - **An administrator.** Someone who could already `sudo` gains nothing
///   they did not have; a standard account on the same Mac must not gain
///   the ability to read every other account's files.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let log = Logger(subsystem: PrivilegedHelper.machServiceName, category: "listener")
    private let appRequirement = CodeSigning.sameTeamRequirement(identifier: PrivilegedHelper.appIdentifier)
    private let lock = NSLock()
    private var openConnections = 0

    /// How long the helper lingers with no connections before it exits.
    private static let idleExitDelay: TimeInterval = 30

    override init() {
        super.init()
        // launchd started us because a connection is on its way, but exit
        // eventually even if it never arrives.
        scheduleIdleExit()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let appRequirement else {
            log.error("Refusing connection: this helper has no team identifier to check callers against")
            return false
        }
        let uid = connection.effectiveUserIdentifier
        guard UserAccounts.isAdministrator(uid: uid) else {
            log.error("Refusing connection from uid \(uid, privacy: .public): not an administrator")
            return false
        }

        connection.setCodeSigningRequirement(appRequirement)
        let service = HelperService(connection: connection)
        connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperClientXPC.self)
        // The app quitting, crashing or being refused mid-run all end here:
        // any restic still running for it is stopped the usual way.
        connection.invalidationHandler = { [weak self] in
            service.interruptAll()
            self?.connectionClosed()
        }
        lock.withLock { openConnections += 1 }
        connection.resume()
        return true
    }

    private func connectionClosed() {
        lock.withLock { openConnections -= 1 }
        scheduleIdleExit()
    }

    private func scheduleIdleExit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleExitDelay) { [weak self] in
            guard let self else { return }
            let idle = lock.withLock { self.openConnections == 0 && !HelperService.anyRunActive }
            if idle {
                exit(0)
            }
            scheduleIdleExit()
        }
    }
}
