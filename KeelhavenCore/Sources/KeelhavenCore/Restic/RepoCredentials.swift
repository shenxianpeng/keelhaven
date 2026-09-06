import Foundation

/// Secrets needed to open a plan's repository, fetched from the Keychain just
/// before a run and handed to restic through its child-process environment.
public struct RepoCredentials: Sendable {
    public var repositoryPassword: String
    public var s3SecretAccessKey: String?
    /// HTTP basic-auth password for a REST server destination. Unrelated to
    /// repositoryPassword, which stays the restic repository's own encryption
    /// password regardless of destination.
    public var restPassword: String?

    public init(repositoryPassword: String, s3SecretAccessKey: String? = nil, restPassword: String? = nil) {
        self.repositoryPassword = repositoryPassword
        self.s3SecretAccessKey = s3SecretAccessKey
        self.restPassword = restPassword
    }

    /// The complete environment for the restic child process: a minimal clean
    /// base (PATH/HOME/TMPDIR so restic can find ssh, its cache, and temp
    /// space) plus repository location and secrets. The app's own environment
    /// is deliberately not inherited.
    public func environment(for destination: Destination) -> [String: String] {
        var env: [String: String] = [:]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["PATH", "HOME", "TMPDIR", "SSH_AUTH_SOCK"] {
            if let value = inherited[key] {
                env[key] = value
            }
        }

        env["RESTIC_REPOSITORY"] = destination.repositoryLocation
        env["RESTIC_PASSWORD"] = repositoryPassword

        if case .s3(let config) = destination {
            env["AWS_ACCESS_KEY_ID"] = config.accessKeyID
            if let secret = s3SecretAccessKey {
                env["AWS_SECRET_ACCESS_KEY"] = secret
            }
        }
        // restic only reads these when the repository URL itself carries no
        // username/password, which RESTConfig.repositoryLocation guarantees —
        // so this is the only place REST auth can come from. An empty
        // username means the server has no authentication; omit both.
        if case .rest(let config) = destination, !config.username.isEmpty {
            env["RESTIC_REST_USERNAME"] = config.username
            if let password = restPassword {
                env["RESTIC_REST_PASSWORD"] = password
            }
        }
        return env
    }
}
