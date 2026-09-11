import Foundation

/// A snapshot's contents as a browsable tree (issue #61).
///
/// **Why the whole snapshot in one call.** `Scripts/bench-remote-ls.sh`
/// measures `restic ls` against real S3 and SFTP servers through an injected
/// round trip; the numbers decide this shape rather than taste. At 60 ms RTT
/// over SFTP, a 15 000-file snapshot lists in ~4.5 s — but *opening the
/// repository alone costs ~2.7 s*. Quadrupling the dataset barely moves it:
/// 60 000 files take ~5.6 s, while listing a single directory still costs
/// ~3.2 s. So per-directory expansion would pay that ~2.7 s of overhead again
/// on every click and still need the same total walk. One call, one tree — and
/// because everything is local afterwards, search is instant instead of
/// another round trip.
///
/// The walk itself is cheap at any size people actually have: at S3's 60 ms
/// that same 4× dataset grows the full listing by under a second.
///
/// The cost of this choice is a visible wait on the first open (worst measured:
/// ~5.6 s), which the UI owes the user as a progress indicator and a way out
/// rather than a frozen window.
public struct SnapshotTree: Sendable {
    /// One entry. `children` distinguishes a directory (`[]` when empty) from
    /// a leaf (`nil`), so an empty folder is never mistaken for a file.
    public struct Node: Identifiable, Sendable, Hashable {
        public let path: String
        public let name: String
        public let type: String
        /// The entry's own size: present for files, absent for directories and
        /// symlinks, exactly as restic reports it.
        public let size: Int64?
        public let modified: Date?
        public let children: [Node]?
        /// For a directory, every file beneath it added up; equal to `size`
        /// for a file; 0 for an empty directory. Directories carry it because
        /// "how big is this folder" is the first question a restore asks.
        public let totalSize: Int64

        public var id: String { path }
        public var isDirectory: Bool { type == "dir" }
        public var isSymlink: Bool { type == "symlink" }
    }

    /// One node per path the snapshot covers. A plan can back up several
    /// folders, so this is a forest, not a single tree.
    public let roots: [Node]

    /// The number of non-directory entries — what a person means by "how many
    /// files".
    public let fileCount: Int
    /// Every file's size added up, matching the snapshot summary's
    /// `total_bytes_processed`.
    public let totalSize: Int64

    /// Builds the forest from a flat `restic ls` listing.
    ///
    /// `rootPaths` comes from the snapshot header (`snapshot.paths`). It
    /// matters because restic walks from the filesystem root: listing
    /// `/Users/me/Documents` also emits `/Users` and `/Users/me`, and nobody
    /// asked to browse `~/../../..`. Anything outside the stated roots is
    /// dropped from the tree.
    ///
    /// Two deliberate non-failures: a node whose parent is missing becomes a
    /// root rather than disappearing, and an empty `rootPaths` keeps the whole
    /// listing. Neither should happen, and both are better than a tree that
    /// quietly omits a file someone is trying to restore.
    public static func build(from nodes: [ResticLsNode], rootedAt rootPaths: [String]) -> SnapshotTree {
        let scoped = rootPaths.isEmpty ? nodes : nodes.filter { node in
            rootPaths.contains { root in
                node.path == root || node.path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
        }

        var childrenByParent: [String: [ResticLsNode]] = [:]
        var topLevel: [ResticLsNode] = []
        let present = Set(scoped.map(\.path))
        for node in scoped {
            let parent = (node.path as NSString).deletingLastPathComponent
            if parent != node.path, present.contains(parent) {
                childrenByParent[parent, default: []].append(node)
            } else {
                topLevel.append(node)
            }
        }

        func makeNode(_ node: ResticLsNode) -> Node {
            guard node.isDirectory else {
                return Node(
                    path: node.path, name: node.name, type: node.type,
                    size: node.size, modified: node.mtime, children: nil,
                    // A symlink has no size of its own; the bytes live at the
                    // target, and counting them here would double-count.
                    totalSize: node.size ?? 0
                )
            }
            let children = (childrenByParent[node.path] ?? [])
                .sorted(by: Self.order)
                .map(makeNode)
            return Node(
                path: node.path, name: node.name, type: node.type,
                size: node.size, modified: node.mtime, children: children,
                totalSize: children.reduce(0) { $0 + $1.totalSize }
            )
        }

        let roots = topLevel.sorted(by: Self.order).map(makeNode)
        return SnapshotTree(
            roots: roots,
            fileCount: roots.reduce(0) { $0 + Self.countFiles(in: $1) },
            totalSize: roots.reduce(0) { $0 + $1.totalSize }
        )
    }

    /// Everything whose name **or** full path contains `query`, case
    /// insensitively, in tree order.
    ///
    /// Both, because the two ways people look for a file are remembering its
    /// name and pasting a path they got from somewhere else. A directory that
    /// matches is returned too — selecting it restores its whole subtree — and
    /// so are its descendants, since their paths contain the query as well.
    public func search(_ query: String) -> [Node] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var matches: [Node] = []
        func visit(_ node: Node) {
            if node.name.localizedCaseInsensitiveContains(needle)
                || node.path.localizedCaseInsensitiveContains(needle) {
                matches.append(node)
            }
            for child in node.children ?? [] {
                visit(child)
            }
        }
        for root in roots {
            visit(root)
        }
        return matches
    }

    /// Directories first, then names case-insensitively — the order a file
    /// browser has used for forty years.
    private static func order(_ a: ResticLsNode, _ b: ResticLsNode) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private static func countFiles(in node: Node) -> Int {
        guard let children = node.children else { return 1 }
        return children.reduce(0) { $0 + countFiles(in: $1) }
    }
}
