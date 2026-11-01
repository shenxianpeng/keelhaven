import XCTest
@testable import KeelhavenCore

/// Run unprivileged, so the "owner" being handed back is this test's own
/// uid: what is under test is *which* entries get chown'd, and that choice
/// is identical whoever the owner is. Root-only behaviour (actually changing
/// owner) is exercised by the helper itself.
final class RepositoryOwnershipTests: XCTestCase {
    private var repo: URL!
    private let me = getuid()
    private let myGroup = getgid()

    override func setUpWithError() throws {
        repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenOwnership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("data/ab"), withIntermediateDirectories: true)
        try Data("config".utf8).write(to: repo.appendingPathComponent("config"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    private func reassign(createdSince: Date = .distantPast) throws -> Int {
        try RepositoryOwnership.reassign(repositoryAt: repo.path, from: me, to: me, group: myGroup, createdSince: createdSince)
    }

    func testReassignsFilesAndFoldersCreatedDuringTheRun() throws {
        try Data("pack".utf8).write(to: repo.appendingPathComponent("data/ab/abcd"))
        // config, data, data/ab, data/ab/abcd
        XCTAssertEqual(try reassign(), 4)
    }

    func testLeavesAloneWhatExistedBeforeTheRun() throws {
        XCTAssertEqual(try reassign(createdSince: Date().addingTimeInterval(60)), 0)
    }

    /// A hard link to a root file elsewhere on the volume is the way a user
    /// could smuggle one in; its link count gives it away.
    func testSkipsHardLinkedFiles() throws {
        let file = repo.appendingPathComponent("data/ab/abcd")
        try Data("pack".utf8).write(to: file)
        try FileManager.default.linkItem(at: file, to: repo.appendingPathComponent("data/ab/link"))
        // config, data, data/ab — both names of the twice-linked file skipped.
        XCTAssertEqual(try reassign(), 3)
    }

    func testNeverFollowsSymlinks() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("victim".utf8).write(to: outside.appendingPathComponent("victim"))

        try FileManager.default.createSymbolicLink(at: repo.appendingPathComponent("data/ab/file-link"), withDestinationURL: outside.appendingPathComponent("victim"))
        try FileManager.default.createSymbolicLink(at: repo.appendingPathComponent("data/dir-link"), withDestinationURL: outside)
        // config, data, data/ab — neither link, nor anything behind them.
        XCTAssertEqual(try reassign(), 3)
    }

    func testSkipsAnythingButFilesAndFolders() throws {
        XCTAssertEqual(mkfifo(repo.appendingPathComponent("data/fifo").path, 0o600), 0)
        XCTAssertEqual(try reassign(), 3)
    }

    func testRefusesSomethingThatIsNotTheUsersRepository() throws {
        let path = repo.path
        XCTAssertThrowsError(
            try RepositoryOwnership.reassign(repositoryAt: path, from: me, to: me + 1, group: myGroup, createdSince: .distantPast)
        ) { error in
            XCTAssertEqual(error as? RepositoryOwnership.Refusal, .notAUserRepository(path))
        }

        try FileManager.default.removeItem(at: repo.appendingPathComponent("config"))
        XCTAssertThrowsError(try reassign())

        let file = repo.appendingPathComponent("plain-file")
        try Data().write(to: file)
        XCTAssertThrowsError(
            try RepositoryOwnership.reassign(repositoryAt: file.path, from: me, to: me, group: myGroup, createdSince: .distantPast)
        )
        XCTAssertThrowsError(
            try RepositoryOwnership.reassign(repositoryAt: repo.path + "/missing", from: me, to: me, group: myGroup, createdSince: .distantPast)
        )
    }
}
