import Foundation
import KeelhavenCore
import Security

// Compiled into both the app and the privileged helper (project.yml), which
// check each other with it. Not in KeelhavenCore: it only says anything
// useful about a signed bundle, and `swift test` runs unsigned.

enum CodeSigning {
    /// The team this process was signed by. nil for an ad-hoc or unsigned
    /// build — which is what turns the privileged helper off entirely.
    static func currentTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// A requirement for `identifier` signed by this process's own team, or
    /// nil when this process has no team to require.
    static func sameTeamRequirement(identifier: String) -> String? {
        PrivilegedHelper.codeSigningRequirement(identifier: identifier, teamID: currentTeamID())
    }

    /// Whether the file at `url` is intact and satisfies `requirement`.
    static func file(at url: URL, satisfies requirement: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess, let compiled else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(staticCode, flags, compiled) == errSecSuccess
    }
}
