import Foundation

/// Names and rules shared by the app and its privileged helper — the launchd
/// daemon that runs `restic backup` as root for plans with
/// `BackupOptions.readsAsAdministrator` set.
///
/// Both sides must agree on every one of these, which is why they live here
/// rather than being typed twice. See docs/ARCHITECTURE.md § "Reading as
/// administrator" for the whole design.
public enum PrivilegedHelper {
    /// The Mach service launchd publishes the helper under, and its label.
    public static let machServiceName = "com.keelhaven.helper"
    /// The plist in `Contents/Library/LaunchDaemons/` that
    /// `SMAppService.daemon(plistName:)` registers.
    public static let launchDaemonPlistName = "com.keelhaven.helper.plist"
    /// Code-signing identifiers each side checks the other against.
    public static let appIdentifier = "com.keelhaven.Keelhaven"
    public static let helperIdentifier = "com.keelhaven.helper"
    /// The bundled restic is signed with its file name as its identifier.
    public static let resticIdentifier = "restic"

    /// A code requirement that only `identifier`, signed by `teamID` through
    /// a certificate Apple issued, can satisfy.
    ///
    /// nil for anything that is not a well-formed team ID — and in
    /// particular for an ad-hoc build, which has no team at all. An
    /// identifier on its own is a name anyone can sign their own code with,
    /// and the one thing a root helper must never do is take orders from
    /// whoever claims to be Keelhaven. So unsigned builds get no helper
    /// rather than an unsafe one.
    public static func codeSigningRequirement(identifier: String, teamID: String?) -> String? {
        guard let teamID, teamID.count == 10,
              teamID.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else {
            return nil
        }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

/// What the app may ask of the helper. Deliberately narrow: one backup (or
/// its preview) described as data, never an argv. The helper builds the
/// restic command line itself from `PrivilegedBackupRequest`, so nothing the
/// app sends can turn into a different restic subcommand or flag.
@objc public protocol PrivilegedHelperXPC {
    /// Runs one backup as root. stdout comes back a line at a time through
    /// the connection's exported `PrivilegedHelperClientXPC`; the reply
    /// carries restic's exit code and stderr once it has exited, or — when
    /// the helper could not run restic at all — a JSON-encoded
    /// `PrivilegedBackupError` for the app to put into words. (The helper
    /// is a bare executable with no resource bundle, so it never localizes
    /// anything itself.)
    func runBackup(
        _ request: Data,
        runID: String,
        reply: @escaping (_ exitCode: Int32, _ stderr: Data, _ failure: Data?) -> Void
    )

    /// SIGINT to the run, the same stop a user-level backup gets.
    func cancelBackup(runID: String)
}

/// Exported by the app on its end of the connection.
@objc public protocol PrivilegedHelperClientXPC {
    func receiveOutputLine(_ line: String, runID: String)
}
