import Foundation

/// Hands the files a root restic wrote into a local repository back to the
/// user whose plan it is.
///
/// Without this, a backup to a folder on a local disk leaves its new pack,
/// index and snapshot files owned by root and readable only by root — and
/// the next restore, check or retention pass, which run as the user, cannot
/// open them. (An SMB share needs nothing: the server reports every file as
/// the mounting user's, and nothing here is owned by root to begin with.)
///
/// This runs as root over a directory the user controls, so it is written
/// against a user who wants to trick it into giving away a file that is not
/// part of the repository:
///
/// - The repository root must be a real directory, owned by that user, with
///   a restic `config` in it.
/// - Every entry is opened with `O_NOFOLLOW_ANY`: no symlink anywhere in the
///   path, so a folder swapped for a link cannot lead outside the repository,
///   not even between listing it and opening it. Ownership then changes on
///   the open descriptor (`fchown`), so what was checked is what changes.
/// - Only entries owned by `owner` (root), created since the run began, and
///   for files linked exactly once — a hard link to a root file elsewhere
///   on the volume has a link count of at least two, and an old birth time.
/// - Only regular files and directories.
public enum RepositoryOwnership {
    public enum Refusal: Error, Equatable {
        /// The path is not a directory the user owns holding a repository.
        case notAUserRepository(String)
    }

    /// The number of entries whose owner changed.
    @discardableResult
    public static func reassign(
        repositoryAt path: String,
        from owner: UInt32,
        to uid: UInt32,
        group gid: UInt32,
        createdSince start: Date
    ) throws -> Int {
        guard let resolved = realpath(path, nil) else {
            throw Refusal.notAUserRepository(path)
        }
        let root = String(cString: resolved)
        free(resolved)

        var rootInfo = stat()
        guard lstat(root, &rootInfo) == 0,
              rootInfo.st_mode & S_IFMT == S_IFDIR,
              rootInfo.st_uid == uid,
              FileManager.default.fileExists(atPath: root + "/config") else {
            throw Refusal.notAUserRepository(path)
        }

        var reassigned = 0
        let entries = FileManager.default.enumerator(atPath: root)
        while let relative = entries?.nextObject() as? String {
            let fd = open(root + "/" + relative, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { continue }
            defer { close(fd) }

            var info = stat()
            guard fstat(fd, &info) == 0,
                  shouldReassign(info, from: owner, createdSince: start) else { continue }
            if fchown(fd, uid, gid) == 0 { reassigned += 1 }
        }
        return reassigned
    }

    static func shouldReassign(_ info: stat, from owner: UInt32, createdSince start: Date) -> Bool {
        let type = info.st_mode & S_IFMT
        let born = Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1e9
        return info.st_uid == owner
            && (type == S_IFDIR || (type == S_IFREG && info.st_nlink == 1))
            && born >= start.timeIntervalSince1970
    }
}
