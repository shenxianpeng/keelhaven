import XCTest
@testable import KeelhavenCore

/// Real filesystem checks rather than injected ones: the whole value of this
/// pre-flight is that it asks macOS the same question restic will, so a mock
/// would test the mock.
final class SourceAccessTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeelhavenSourceAccess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            // Restore the mode first, or the unreadable fixture cannot be removed.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workDirectory.path)
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testReportsNothingWhenEverySourceIsReadable() throws {
        let readable = workDirectory.appendingPathComponent("readable", isDirectory: true)
        try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true)

        XCTAssertEqual(SourceAccess.unreadableExistingPaths([readable.path]), [])
    }

    /// The case that matters on macOS: the folder is there, and this process
    /// still cannot open it. Skipped for root, where mode bits do not restrict
    /// anything and the assertion would be meaningless.
    func testReportsAnExistingButUnreadableFolder() throws {
        try XCTSkipIf(getuid() == 0, "mode bits do not restrict root")

        let readable = workDirectory.appendingPathComponent("readable", isDirectory: true)
        let locked = workDirectory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        XCTAssertEqual(SourceAccess.unreadableExistingPaths([readable.path, locked.path]), [locked.path])
    }

    /// An unplugged drive is not a permission problem, and telling someone to
    /// grant Full Disk Access because their backup disk is on a desk would send
    /// them to the wrong place. A path that is simply not there stays out.
    func testAMissingPathIsNotReportedAsUnreadable() {
        let missing = workDirectory.appendingPathComponent("not-mounted", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))

        XCTAssertEqual(SourceAccess.unreadableExistingPaths([missing.path]), [])
    }

    func testPreservesTheOrderOfThePlanSources() throws {
        try XCTSkipIf(getuid() == 0, "mode bits do not restrict root")

        let first = workDirectory.appendingPathComponent("first", isDirectory: true)
        let second = workDirectory.appendingPathComponent("second", isDirectory: true)
        for url in [first, second] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        }

        XCTAssertEqual(
            SourceAccess.unreadableExistingPaths([first.path, second.path]),
            [first.path, second.path]
        )
    }

    func testEmptyPlanHasNoUnreadableSources() {
        XCTAssertEqual(SourceAccess.unreadableExistingPaths([]), [])
    }
}
