import XCTest
@testable import KeelhavenCore

/// The tree is built from the captured `restic ls --json` fixture wherever
/// possible, so the tests describe a real snapshot rather than a shape someone
/// imagined.
final class SnapshotTreeTests: XCTestCase {
    private func nodesFromFixture() throws -> (snapshot: ResticSnapshot, nodes: [ResticLsNode]) {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/ls-nested.jsonl", withExtension: nil),
            "Missing fixture ls-nested.jsonl"
        )
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)

        var snapshot: ResticSnapshot?
        var nodes: [ResticLsNode] = []
        for line in text.split(separator: "\n").map(String.init) {
            switch ResticJSON.decodeLsEvent(fromLine: line) {
            case .snapshot(let value): snapshot = value
            case .node(let value): nodes.append(value)
            case nil: XCTFail("Undecoded line: \(line)")
            }
        }
        return (try XCTUnwrap(snapshot), nodes)
    }

    private func tree() throws -> SnapshotTree {
        let (snapshot, nodes) = try nodesFromFixture()
        return SnapshotTree.build(from: nodes, rootedAt: snapshot.paths)
    }

    private func node(_ path: String, in tree: SnapshotTree) -> SnapshotTree.Node? {
        var found: SnapshotTree.Node?
        func visit(_ candidate: SnapshotTree.Node) {
            if candidate.path == path { found = candidate }
            for child in candidate.children ?? [] { visit(child) }
        }
        for root in tree.roots { visit(root) }
        return found
    }

    /// restic walks from the filesystem root, so the listing holds `/tmp` and
    /// `/tmp/keelhaven-ls` — ancestors nobody asked to browse. The tree is
    /// rooted where the snapshot says its content begins.
    func testTreeIsRootedAtTheSnapshotsOwnPaths() throws {
        let tree = try tree()
        XCTAssertEqual(tree.roots.map(\.path), ["/tmp/keelhaven-ls/src"])
        XCTAssertEqual(tree.roots.first?.name, "src")
        XCTAssertNil(node("/tmp", in: tree), "An ancestor outside the snapshot's paths must not appear")
        XCTAssertNil(node("/tmp/keelhaven-ls", in: tree))
    }

    /// Directories first, then names case-insensitively — and hidden files are
    /// ordinary files, which is what a backup is for.
    func testChildrenAreDirectoriesFirstThenAlphabetical() throws {
        let tree = try tree()
        let root = try XCTUnwrap(tree.roots.first)
        XCTAssertEqual(root.children?.map(\.name), ["docs", "empty", ".hidden.txt", "a.txt", "link-to-a", "文档 名.txt"])

        let docs = try XCTUnwrap(node("/tmp/keelhaven-ls/src/docs", in: tree))
        XCTAssertEqual(docs.children?.map(\.name), ["deep", "b.txt"])
    }

    /// The number the restore window shows for "how big is this folder", and a
    /// cross-check that the tree and restic's own summary agree about the
    /// snapshot: the header's `total_bytes_processed` is the sum of the files.
    func testDirectorySizesAddUpAndMatchTheSnapshotsOwnSummary() throws {
        let (snapshot, nodes) = try nodesFromFixture()
        let tree = SnapshotTree.build(from: nodes, rootedAt: snapshot.paths)

        let root = try XCTUnwrap(tree.roots.first)
        XCTAssertEqual(root.totalSize, 37)
        XCTAssertEqual(root.totalSize, snapshot.summary?.totalBytesProcessed)

        let docs = try XCTUnwrap(node("/tmp/keelhaven-ls/src/docs", in: tree))
        XCTAssertEqual(docs.totalSize, 16, "7 in b.txt plus 2 and 7 under deep")
        XCTAssertEqual(docs.size, nil, "A directory keeps its own (absent) size separate from the total")
    }

    /// An empty directory is a directory with no children — not a leaf. The
    /// distinction is what stops the UI from drawing a folder as a file.
    func testEmptyDirectoryHasNoChildrenRatherThanNoValue() throws {
        let tree = try tree()
        let empty = try XCTUnwrap(node("/tmp/keelhaven-ls/src/empty", in: tree))
        XCTAssertEqual(empty.children, [])
        XCTAssertTrue(empty.isDirectory)
        XCTAssertEqual(empty.totalSize, 0)

        let file = try XCTUnwrap(node("/tmp/keelhaven-ls/src/a.txt", in: tree))
        XCTAssertNil(file.children)
        XCTAssertFalse(file.isDirectory)
    }

    /// A symlink is a leaf that contributes no bytes: it carries no size of its
    /// own, and counting the target's bytes here would count them twice.
    func testSymlinkIsALeafWithNoSize() throws {
        let tree = try tree()
        let symlink = try XCTUnwrap(node("/tmp/keelhaven-ls/src/link-to-a", in: tree))
        XCTAssertTrue(symlink.isSymlink)
        XCTAssertNil(symlink.children)
        XCTAssertEqual(symlink.totalSize, 0)
    }

    func testTotalsCountLeavesNotDirectories() throws {
        let tree = try tree()
        // Six regular files plus the symlink, which is a leaf too; the eight
        // directories are not counted.
        XCTAssertEqual(tree.fileCount, 7)
        XCTAssertEqual(tree.totalSize, 37)
    }

    func testSearchFindsByNameAndByPathAndIgnoresCase() throws {
        let tree = try tree()
        XCTAssertEqual(tree.search("b.txt").map(\.name), ["b.txt"])
        XCTAssertEqual(tree.search("B.TXT").map(\.name), ["b.txt"], "Search is case insensitive")
        XCTAssertEqual(tree.search("deep").map(\.name), ["deep", "another", "d.txt", "c.txt"])
        XCTAssertTrue(tree.search("nothing-like-this").isEmpty)
        XCTAssertTrue(tree.search("   ").isEmpty, "A blank query is not a search for everything")
    }

    /// Selecting a directory restores its subtree, so a directory that matches
    /// has to be in the results.
    func testSearchReturnsMatchingDirectoriesToo() throws {
        let tree = try tree()
        let matches = tree.search("empty")
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].isDirectory)
    }

    // MARK: - Shapes a real snapshot will not produce, but a bug might

    /// A node **inside** the snapshot whose parent is missing from the listing
    /// becomes a root rather than vanishing. It should not happen; hiding a
    /// file from the restore browser is the one failure worth defending
    /// against. (A node genuinely outside the roots is dropped on purpose —
    /// that is how `/tmp` is kept out, and the fixture test above covers it.)
    func testNodeWhoseParentIsMissingBecomesARoot() throws {
        let line = #"{"name":"orphan.txt","type":"file","path":"/Users/me/Documents/ghost/orphan.txt","size":3,"message_type":"node"}"#
        guard case .node(let orphan)? = ResticJSON.decodeLsEvent(fromLine: line) else {
            return XCTFail("Expected a node")
        }

        let tree = SnapshotTree.build(from: [orphan], rootedAt: ["/Users/me/Documents"])
        XCTAssertEqual(tree.roots.map(\.path), ["/Users/me/Documents/ghost/orphan.txt"])
        XCTAssertEqual(tree.fileCount, 1)
    }

    /// `restic ls` can emit `dev`, `chardev`, `fifo`, `socket` and `irregular`
    /// as well. None may be dropped for being unrecognised.
    func testAnUnrecognisedTypeIsKeptAsALeaf() throws {
        let line = #"{"name":"pipe","type":"fifo","path":"/tmp/pipe","message_type":"node"}"#
        guard case .node(let fifo)? = ResticJSON.decodeLsEvent(fromLine: line) else {
            return XCTFail("Expected a node")
        }

        let tree = SnapshotTree.build(from: [fifo], rootedAt: ["/tmp"])
        let root = try XCTUnwrap(tree.roots.first)
        XCTAssertEqual(root.type, "fifo")
        XCTAssertFalse(root.isDirectory)
        XCTAssertFalse(root.isSymlink)
        XCTAssertNil(root.children)
        XCTAssertEqual(tree.fileCount, 1)
    }

    func testEmptyListingBuildsAnEmptyTree() {
        let tree = SnapshotTree.build(from: [], rootedAt: ["/Users/me/Documents"])
        XCTAssertTrue(tree.roots.isEmpty)
        XCTAssertEqual(tree.fileCount, 0)
        XCTAssertEqual(tree.totalSize, 0)
    }

    /// Defensive: a snapshot header without paths keeps the whole listing
    /// rather than returning nothing.
    func testMissingRootPathsKeepsTheWholeListing() throws {
        let (_, nodes) = try nodesFromFixture()
        let tree = SnapshotTree.build(from: nodes, rootedAt: [])
        XCTAssertEqual(tree.roots.map(\.path), ["/tmp"])
    }

    /// Several source folders in one plan produce several roots, in the order
    /// the directories-first rule gives them.
    func testMultipleRootsAreKept() throws {
        let lines = [
            #"{"name":"a","type":"dir","path":"/one/a","message_type":"node"}"#,
            #"{"name":"x.txt","type":"file","path":"/one/a/x.txt","size":1,"message_type":"node"}"#,
            #"{"name":"b","type":"dir","path":"/two/b","message_type":"node"}"#,
            #"{"name":"y.txt","type":"file","path":"/two/b/y.txt","size":2,"message_type":"node"}"#,
        ]
        let nodes = lines.compactMap { line -> ResticLsNode? in
            guard case .node(let node)? = ResticJSON.decodeLsEvent(fromLine: line) else { return nil }
            return node
        }

        let tree = SnapshotTree.build(from: nodes, rootedAt: ["/one/a", "/two/b"])
        XCTAssertEqual(tree.roots.map(\.path), ["/one/a", "/two/b"])
        XCTAssertEqual(tree.fileCount, 2)
        XCTAssertEqual(tree.totalSize, 3)
    }
}
