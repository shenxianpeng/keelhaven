import Foundation

/// Cheap local checks about the folders a plan points at, asked *before*
/// restic is spawned so an obviously hopeless run fails in a second rather
/// than after several minutes of reading.
///
/// This is a pre-flight, not a proof. It can see that a folder is present but
/// closed to this process; it cannot promise that everything *inside* a
/// readable folder is readable too. When it is wrong in that direction, the
/// run ends in `ResticError.someSourcesUnreadable` anyway, which is where the
/// authoritative list comes from.
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
