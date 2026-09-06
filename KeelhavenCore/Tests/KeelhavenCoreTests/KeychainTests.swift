import XCTest
import Security
@testable import KeelhavenCore

final class KeychainAccountTests: XCTestCase {
    func testAccountNamesAreKeyedByPlanID() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(
            KeychainAccount.repositoryPassword(planID: id),
            "repo-password.11111111-2222-3333-4444-555555555555"
        )
        XCTAssertEqual(
            KeychainAccount.s3SecretKey(planID: id),
            "s3-secret.11111111-2222-3333-4444-555555555555"
        )
        XCTAssertEqual(
            KeychainAccount.restPassword(planID: id),
            "rest-secret.11111111-2222-3333-4444-555555555555"
        )
    }
}

final class InMemoryKeychainTests: XCTestCase {
    func testRoundTripAndDelete() throws {
        let keychain = InMemoryKeychain()
        XCTAssertNil(try keychain.secret(account: "a"))

        try keychain.setSecret("s3cret", account: "a")
        XCTAssertEqual(try keychain.secret(account: "a"), "s3cret")

        try keychain.setSecret("updated", account: "a")
        XCTAssertEqual(try keychain.secret(account: "a"), "updated")

        try keychain.deleteSecret(account: "a")
        XCTAssertNil(try keychain.secret(account: "a"))
    }
}

final class KeychainErrorDescriptionTests: XCTestCase {
    func testEveryCaseHasAnActionableDescription() {
        let cases: [(KeychainError, String)] = [
            (.unexpectedStatus(errSecUserCanceled), "Always Allow"),
            (.unexpectedStatus(errSecAuthFailed), "Always Allow"),
            (.unexpectedStatus(errSecMissingEntitlement), "error \(errSecMissingEntitlement)"),
            (.invalidData, "set it up again"),
        ]
        for (error, expectedFragment) in cases {
            let description = error.localizedDescription
            XCTAssertTrue(
                description.contains(expectedFragment),
                "\(error) description missing “\(expectedFragment)”: \(description)"
            )
        }
    }
}

/// Exercises `KeychainStore`'s status handling through an injected
/// `SecItemClient` — the real keychain is never touched, so these run
/// deterministically everywhere (including CI).
final class KeychainStoreTests: XCTestCase {
    func testLiveClientConstruction() {
        // The public initializer binds the real Security functions.
        _ = KeychainStore()
    }

    // MARK: setSecret

    func testSetSecretUpdatesExistingItem() throws {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecSuccess },
            add: { _, _ in XCTFail("add must not be called"); return errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecItemNotFound }
        ))
        try store.setSecret("pw", account: "acct")
    }

    func testSetSecretAddsWhenItemMissing() throws {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecItemNotFound },
            add: { query, _ in
                let attrs = query as! [String: Any]
                XCTAssertEqual(attrs[kSecAttrService as String] as? String, KeychainStore.service)
                XCTAssertNotNil(attrs[kSecValueData as String])
                return errSecSuccess
            },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecItemNotFound }
        ))
        try store.setSecret("pw", account: "acct")
    }

    func testSetSecretThrowsWhenAddFails() {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecItemNotFound },
            add: { _, _ in errSecAuthFailed },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecItemNotFound }
        ))
        XCTAssertThrowsError(try store.setSecret("pw", account: "acct")) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedStatus(errSecAuthFailed))
        }
    }

    func testSetSecretThrowsWhenUpdateFailsUnexpectedly() {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecAuthFailed },
            add: { _, _ in XCTFail("add must not be called"); return errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecItemNotFound }
        ))
        XCTAssertThrowsError(try store.setSecret("pw", account: "acct")) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedStatus(errSecAuthFailed))
        }
    }

    // MARK: secret

    func testSecretReturnsStoredValue() throws {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecSuccess },
            add: { _, _ in errSecSuccess },
            copyMatching: { _, item in
                item?.pointee = Data("hunter2".utf8) as CFTypeRef
                return errSecSuccess
            },
            delete: { _ in errSecSuccess }
        ))
        XCTAssertEqual(try store.secret(account: "acct"), "hunter2")
    }

    func testSecretReturnsNilWhenMissing() throws {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecSuccess },
            add: { _, _ in errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecSuccess }
        ))
        XCTAssertNil(try store.secret(account: "acct"))
    }

    func testSecretThrowsOnNonUTF8Data() {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecSuccess },
            add: { _, _ in errSecSuccess },
            copyMatching: { _, item in
                item?.pointee = Data([0xFF, 0xFE, 0xFD]) as CFTypeRef
                return errSecSuccess
            },
            delete: { _ in errSecSuccess }
        ))
        XCTAssertThrowsError(try store.secret(account: "acct")) { error in
            XCTAssertEqual(error as? KeychainError, .invalidData)
        }
    }

    func testSecretThrowsOnUnexpectedStatus() {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecSuccess },
            add: { _, _ in errSecSuccess },
            copyMatching: { _, _ in errSecAuthFailed },
            delete: { _ in errSecSuccess }
        ))
        XCTAssertThrowsError(try store.secret(account: "acct")) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedStatus(errSecAuthFailed))
        }
    }

    // MARK: deleteSecret

    func testDeleteTreatsMissingItemAsSuccess() throws {
        for status in [errSecSuccess, errSecItemNotFound] {
            let store = KeychainStore(client: .init(
                update: { _, _ in errSecSuccess },
                add: { _, _ in errSecSuccess },
                copyMatching: { _, _ in errSecItemNotFound },
                delete: { _ in status }
            ))
            XCTAssertNoThrow(try store.deleteSecret(account: "acct"))
        }
    }

    func testDeleteThrowsOnUnexpectedStatus() {
        let store = KeychainStore(client: .init(
            update: { _, _ in errSecSuccess },
            add: { _, _ in errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecAuthFailed }
        ))
        XCTAssertThrowsError(try store.deleteSecret(account: "acct")) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedStatus(errSecAuthFailed))
        }
    }
}
