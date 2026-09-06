import Foundation

/// Where a plan's restic repository lives. One repository per plan.
public enum Destination: Codable, Hashable, Sendable {
    /// Local folder, including mounted external drives.
    case local(path: String)
    case s3(S3Config)
    case sftp(SFTPConfig)
    case rest(RESTConfig)

    /// The restic repository location string, passed via RESTIC_REPOSITORY.
    public var repositoryLocation: String {
        switch self {
        case .local(let path):
            return path
        case .s3(let config):
            return config.repositoryLocation
        case .sftp(let config):
            return config.repositoryLocation
        case .rest(let config):
            return config.repositoryLocation
        }
    }

    /// Short human-readable label for UI display.
    public var displayName: String {
        switch self {
        case .local(let path):
            return path
        case .s3(let config):
            return "s3://\(config.bucket)"
        case .sftp(let config):
            return "\(config.user)@\(config.host)"
        case .rest(let config):
            return config.displayName
        }
    }
}

/// S3-compatible object storage. The secret access key is never stored here —
/// it lives in the Keychain and is injected via AWS_SECRET_ACCESS_KEY at run time.
public struct S3Config: Codable, Hashable, Sendable {
    /// Endpoint host, with or without scheme, e.g. "s3.amazonaws.com" or "https://minio.example.com:9000".
    public var endpoint: String
    public var bucket: String
    /// Optional key prefix inside the bucket; empty means repository at bucket root.
    public var pathPrefix: String
    public var accessKeyID: String

    public init(endpoint: String, bucket: String, pathPrefix: String, accessKeyID: String) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.pathPrefix = pathPrefix
        self.accessKeyID = accessKeyID
    }

    public var repositoryLocation: String {
        var endpointWithScheme = endpoint
        if !endpointWithScheme.contains("://") {
            endpointWithScheme = "https://" + endpointWithScheme
        }
        var location = "s3:\(endpointWithScheme)/\(bucket)"
        let prefix = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !prefix.isEmpty {
            location += "/\(prefix)"
        }
        return location
    }
}

/// SFTP/NAS destination. v1 relies on the user's ~/.ssh keys or agent for auth.
public struct SFTPConfig: Codable, Hashable, Sendable {
    public var user: String
    public var host: String
    public var port: Int
    /// Path on the remote host. Absolute paths must start with "/".
    public var path: String

    public init(user: String, host: String, port: Int = 22, path: String) {
        self.user = user
        self.host = host
        self.port = port
        self.path = path
    }

    public var repositoryLocation: String {
        if port == 22 {
            return "sftp:\(user)@\(host):\(path)"
        }
        // restic URL form: sftp://user@host:port/relative or sftp://user@host:port//absolute,
        // so the remote path is always appended after a separating "/".
        return "sftp://\(user)@\(host):\(port)/\(path)"
    }
}

/// A restic REST server (https://github.com/restic/rest-server) reached over
/// plain HTTP or HTTPS. v1 targets the server's default mode: no
/// `--private-repos` path layout, no `--append-only`, no self-signed TLS
/// (public CA-signed HTTPS works as-is; a custom CA is not yet supported —
/// see docs/ARCHITECTURE.md).
public struct RESTConfig: Codable, Hashable, Sendable {
    /// Scheme + host + port + optional path, e.g. "http://127.0.0.1:8000/" or
    /// "https://backups.example.com/mac/". Never contains credentials —
    /// those are carried separately so they never end up in RESTIC_REPOSITORY.
    public var url: String
    /// HTTP basic-auth username for a server run with an .htpasswd file.
    /// Empty means the server has no authentication (rest-server --no-auth).
    public var username: String

    public init(url: String, username: String = "") {
        self.url = url
        self.username = username
    }

    public var repositoryLocation: String {
        "rest:\(url)"
    }

    public var displayName: String {
        guard let components = URLComponents(string: url), let host = components.host else {
            return url
        }
        guard let port = components.port else {
            return "rest://\(host)"
        }
        return "rest://\(host):\(port)"
    }
}
