import XCTest
@testable import KeelhavenCore

/// restic recreates each restored path in full beneath the target (verified
/// against 0.19.1 by `testListBuildsATreeAndRestoreIncludeTakesOneFile`,
/// which finds the file at target + its original path). These tests are about
/// what follows from that: where to point Finder afterwards.
final class RestoreLayoutTests: XCTestCase {
    private let target = "/Volumes/Out/Keelhaven Restore"

    func testAPathLandsInFullBeneathTheTarget() {
        XCTAssertEqual(
            RestoreLayout.landingPath(of: "/Users/me/Documents/a.txt", in: target),
            "/Volumes/Out/Keelhaven Restore/Users/me/Documents/a.txt"
        )
    }

    /// A whole snapshot has no one item to point at.
    func testAWholeSnapshotRevealsTheTargetFolder() {
        XCTAssertEqual(RestoreLayout.pathsToReveal(target: target, includes: []), [target])
    }

    /// The case this exists for: one file, four folders down. Finder is sent
    /// to the file, not to the top of the folders around it.
    func testOneRestoredFileIsRevealedItself() {
        XCTAssertEqual(
            RestoreLayout.pathsToReveal(target: target, includes: ["/Users/me/Documents/a.txt"]),
            ["/Volumes/Out/Keelhaven Restore/Users/me/Documents/a.txt"]
        )
    }

    /// Side by side, they can all be highlighted in one Finder window.
    func testSiblingsAreAllRevealed() {
        XCTAssertEqual(
            RestoreLayout.pathsToReveal(
                target: target,
                includes: ["/Users/me/Documents/a.txt", "/Users/me/Documents/photos"]
            ),
            [
                "/Volumes/Out/Keelhaven Restore/Users/me/Documents/a.txt",
                "/Volumes/Out/Keelhaven Restore/Users/me/Documents/photos",
            ]
        )
    }

    /// Selecting items in different folders would open a Finder window for
    /// each, so the nearest folder holding them all is shown instead.
    func testItemsInDifferentFoldersRevealTheFolderTheyShare() {
        XCTAssertEqual(
            RestoreLayout.pathsToReveal(
                target: target,
                includes: ["/Users/me/Documents/taxes/2024.pdf", "/Users/me/Documents/photos/cat.jpg", "/Users/me/Documents/a.txt"]
            ),
            ["/Volumes/Out/Keelhaven Restore/Users/me/Documents"]
        )
    }

    /// Two source folders with nothing in common above them share only the
    /// target — which is where the whole-snapshot case points too.
    func testItemsFromSeparateSourceFoldersRevealTheTarget() {
        XCTAssertEqual(
            RestoreLayout.pathsToReveal(target: target, includes: ["/Users/me/Documents/a.txt", "/Volumes/Work/b.txt"]),
            [target]
        )
    }
}
