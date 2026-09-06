import Foundation
import Security

/// Abstracts Keychain access so the engine and tests never touch Security
/// framework state directly.
public protocol KeychainStoring: Sendable {
    func setSecret(_ secret: String, account: String) throws
    func secret(account: String) throws -> String?
    func deleteSecret(account: String) throws
}

/// Well-known account names, one secret per plan.
public enum KeychainAccount {
    public static func repositoryPassword(planID: UUID) -> String {
        "repo-password.\(planID.uuidString)"
    }

    public static func s3SecretKey(planID: UUID) -> String {
        "s3-secret.\(planID.uuidString)"
    }

    public static func restPassword(planID: UUID) -> String {
        "rest-secret.\(planID.uuidString)"
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(Int32)
    case invalidData
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        // The two statuses macOS returns when the user dismisses or fails the
        // Keychain access prompt (common after replacing the app binary, which
        // changes the code signature the Keychain item was granted to).
        case .unexpectedStatus(errSecUserCanceled), .unexpectedStatus(errSecAuthFailed):
            return String(localized: "Couldn't read the Keychain password — click Always Allow next time macOS asks.", bundle: .module)
        case .unexpectedStatus(let status):
            // Interpolate as a string so the OSStatus prints as "-34018",
            // not the locale-grouped "-34,018".
            return String(localized: "Could not read this plan's password from the Keychain (error \(String(status))).", bundle: .module)
        case .invalidData:
            return String(localized: "The password stored in the Keychain for this plan is unreadable. Delete the plan and set it up again.", bundle: .module)
        }
    }
}
