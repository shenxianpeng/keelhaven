import Foundation

/// Cheap local checks about the folders a plan points at, asked *before*
/// restic is spawned so an obviously hopeless run fails in a second rather
/// than after several minutes of reading.
///
/// This is a pre-flight, not a proof, and the distinction is worth being
/// precise about. It answers "can this process open that folder", which is the
/// filesystem's own question (`access(2)`) — **not** the question TCC answers.
/// TCC is enforced nearer `open(2)`, so a folder guarded by Desktop/Documents/
/// Downloads consent can pass this check and still fail inside restic. It also
/// cannot promise that everything *inside* a readable folder is readable too.
///
/// Both of those gaps end in the same place: `ResticError.someSourcesUnreadable`
/// from restic's exit code 3, which is the authoritative report and names the
/// files. This exists so the cheap, obvious cases never get that far.
public enum SourceAccess {
    /// The paths that exist but cannot be read by this process right now.
    ///
    /// A path that does not exist is deliberately **not** reported. An
    /// unplugged drive and a folder the user moved have a different cause and
    /// a different fix, restic already describes them in its own words, and
    /// telling someone to grant Full Disk Access because their backup drive
    /// is on the desk would be a lie.
    public static func unreadableExistingPaths(_ paths: [String]) -> [String] {
        let manager = FileManager.default
        return paths.filter { path in
            manager.fileExists(atPath: path) && !manager.isReadableFile(atPath: path)
        }
    }
}
