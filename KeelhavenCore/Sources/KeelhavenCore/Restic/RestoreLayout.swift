import Foundation

/// Where a restore puts things, and so what to show the user when it is done.
///
/// restic recreates every restored path in full beneath the target: asking
/// for `/Users/me/Documents/a.txt` into `/Volumes/Out/Restore` writes
/// `/Volumes/Out/Restore/Users/me/Documents/a.txt` (verified against restic
/// 0.19.1). That is the right thing for a whole snapshot and a poor ending for
/// one file — the window says "restored", and the file is four folders down
/// from the place it points at.
public enum RestoreLayout {
    /// The place `snapshotPath` lands when restored into `target`.
    public static func landingPath(of snapshotPath: String, in target: String) -> String {
        (target as NSString).appendingPathComponent(snapshotPath)
    }

    /// What to select in Finder after a restore.
    ///
    /// A whole snapshot (`includes` empty) is the target folder itself. For a
    /// selection, it is the restored items when they sit side by side —
    /// Finder then opens one window with all of them highlighted — and
    /// otherwise the closest folder that holds all of them, because selecting
    /// items in different folders would open a window for each.
    public static func pathsToReveal(target: String, includes: [String]) -> [String] {
        let landings = includes.map { landingPath(of: $0, in: target) }
        guard let first = landings.first else { return [target] }

        let parents = Set(landings.map { ($0 as NSString).deletingLastPathComponent })
        if parents.count == 1 {
            return landings
        }

        var common = (first as NSString).pathComponents
        for landing in landings.dropFirst() {
            let components = (landing as NSString).pathComponents
            var shared = 0
            while shared < min(common.count, components.count), common[shared] == components[shared] {
                shared += 1
            }
            common = Array(common.prefix(shared))
        }
        return [NSString.path(withComponents: common)]
    }
}
