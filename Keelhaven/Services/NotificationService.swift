import Foundation
import UserNotifications
import KeelhavenCore

enum NotificationService {
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func postBackupFinished(planName: String, summary: BackupSummary?) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Backup complete")
        if let summary {
            let added = ByteCountFormatter.string(
                fromByteCount: summary.dataAdded ?? 0,
                countStyle: .file
            )
            content.body = String(localized: "\(planName): \(summary.filesNew) new files, \(added) added.")
        } else {
            content.body = String(localized: "\(planName) finished successfully.")
        }
        await post(content)
    }

    /// A run that stored nothing because the folders were byte-for-byte
    /// identical to the last backup. Reported separately rather than as
    /// "0 new files, Zero bytes added", which reads like something went
    /// wrong — and, more importantly, so nobody is told a snapshot was
    /// written when none was (issue #46).
    static func postBackupUnchanged(planName: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nothing to back up")
        content.body = String(localized: "\(planName): no changes since the last backup, so no new snapshot was created.")
        await post(content)
    }

    static func postBackupFailed(planName: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Backup failed")
        content.body = "\(planName): \(message)"
        content.sound = .default
        await post(content)
    }

    /// Only failures notify — a passed check shows quietly in the plan row.
    static func postCheckFailed(planName: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Backup verification failed")
        content.body = "\(planName): \(message)"
        content.sound = .default
        await post(content)
    }

    /// Only failures notify — a successful retention pass is invisible by
    /// design.
    static func postPruneFailed(planName: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Backup cleanup failed")
        content.body = "\(planName): \(message)"
        content.sound = .default
        await post(content)
    }

    private static func post(_ content: UNMutableNotificationContent) async {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
