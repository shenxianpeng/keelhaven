import Foundation
import KeelhavenCore
import OpenDirectory

/// The few places on disk the helper writes as root, all under one
/// root-owned folder no other account can change:
/// /Library/Application Support/Keelhaven/Helper.
enum HelperFiles {
    /// A private copy of the bundled restic, checked after copying.
    ///
    /// Never the bundled binary itself: the app usually sits in
    /// /Applications owned by whoever installed it, so its restic is a file
    /// a user process could swap between a signature check and the exec —
    /// and whatever ran then would run as root. The copy lives where only
    /// root can write, and it is the copy whose signature is verified, so
    /// what was checked is exactly what runs. One per run, removed after.
    static func verifiedResticCopy() throws -> URL {
        guard let requirement = CodeSigning.sameTeamRequirement(identifier: PrivilegedHelper.resticIdentifier),
              let helper = Bundle.main.executableURL else {
            throw PrivilegedBackupError.resticUnavailable
        }
        let bundled = helper.deletingLastPathComponent().appendingPathComponent("restic")
        let directory = try privateDirectory("bin")
        let copy = directory.appendingPathComponent("restic-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: bundled, to: copy)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copy.path)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw PrivilegedBackupError.resticUnavailable
        }
        guard CodeSigning.file(at: copy, satisfies: requirement) else {
            try? FileManager.default.removeItem(at: copy)
            throw PrivilegedBackupError.resticUnavailable
        }
        return copy
    }

    /// root's restic cache for one user's repositories — never the user's
    /// own cache, which root would otherwise fill with files they cannot
    /// remove. Readable by root alone: it holds (encrypted) repository
    /// metadata, which is nobody else's business.
    static func cacheDirectory(uid: uid_t) throws -> URL {
        try privateDirectory("cache/\(uid)", mode: 0o700)
    }

    /// Creates `relative` under the helper's folder, checking every level on the way
    /// down is a real directory owned by root that no one else can write to.
    /// A folder planted there by someone else would otherwise let them steer
    /// where root writes. The last level gets `mode`, also when it exists
    /// already.
    private static func privateDirectory(_ relative: String, mode: mode_t = 0o755) throws -> URL {
        var url = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
        for component in ["Keelhaven", "Helper"] + relative.split(separator: "/").map(String.init) {
            url.appendPathComponent(component, isDirectory: true)
            if mkdir(url.path, 0o755) != 0 && errno != EEXIST {
                throw PrivilegedBackupError.helperFault("cannot create \(url.path)")
            }
            var info = stat()
            guard lstat(url.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == 0,
                  info.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
                throw PrivilegedBackupError.helperFault("\(url.path) is not a private root folder")
            }
        }
        guard chmod(url.path, mode) == 0 else {
            throw PrivilegedBackupError.helperFault("cannot set permissions on \(url.path)")
        }
        return url
    }
}

enum UserAccounts {
    static func user(uid: uid_t) throws -> RequestingUser {
        guard let entry = getpwuid(uid) else {
            throw PrivilegedBackupError.helperFault("no account for uid \(uid)")
        }
        return RequestingUser(
            uid: uid,
            gid: entry.pointee.pw_gid,
            name: String(cString: entry.pointee.pw_name),
            home: String(cString: entry.pointee.pw_dir)
        )
    }

    /// Membership of the `admin` group as Directory Services resolves it —
    /// nested groups included, unlike a scan of `getgrouplist`.
    static func isAdministrator(uid: uid_t) -> Bool {
        guard let entry = getpwuid(uid),
              let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
              let user = try? node.record(withRecordType: kODRecordTypeUsers, name: String(cString: entry.pointee.pw_name), attributes: nil),
              let admin = try? node.record(withRecordType: kODRecordTypeGroups, name: "admin", attributes: nil) else {
            return false
        }
        // Throws when the user is not a member.
        return (try? admin.isMemberRecord(user)) != nil
    }
}
