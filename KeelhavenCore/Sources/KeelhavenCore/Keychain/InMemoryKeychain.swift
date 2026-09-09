import Foundation

/// Test double for `KeychainStoring`.
public final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {
        // All state lives in the lock-protected storage dictionary, which
        // starts empty — nothing else to set up.
    }

    public func setSecret(_ secret: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[account] = secret
    }

    public func secret(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    public func deleteSecret(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: account)
    }
}
