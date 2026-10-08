import SwiftUI
import UniformTypeIdentifiers
import KeelhavenCore

/// The inside of one snapshot: its folders as an outline, or — while a search
/// is on — the matches as a flat list. Selecting rows is how the user says
/// what to bring back; the window around this view owns the buttons.
///
/// It takes plain values and bindings rather than the restore model, so it
/// knows nothing about restic, plans or the app, and can be put on screen by
/// anything that has a tree to show.
struct SnapshotBrowserView: View {
    let tree: SnapshotTree
    /// The matches while a search is on, nil otherwise.
    let searchResults: [SnapshotTree.Node]?
    /// What the user typed, for the screen that says nothing matched it.
    let searchText: String
    @Binding var selection: Set<SnapshotTree.Node.ID>
    let isExpanded: (SnapshotTree.Node) -> Bool
    let setExpanded: (SnapshotTree.Node, Bool) -> Void

    var body: some View {
        // An empty table is a grid of blank stripes; say what happened
        // instead. The search one is the system's own, wording included.
        // Both fill the space the table had, so the window around them does
        // not change shape when a search comes up empty.
        if searchResults?.isEmpty == true {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tree.roots.isEmpty {
            ContentUnavailableView("This backup has nothing in it.", systemImage: "folder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            table
        }
    }

    private var table: some View {
        Table(of: SnapshotTree.Node.self, selection: $selection) {
            TableColumn("Name") { node in
                NameCell(node: node, showsLocation: searchResults != nil)
            }
            TableColumn("Size") { node in
                Text(Self.sizeText(for: node))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 80, max: 110)
            TableColumn("Modified") { node in
                Text(node.modified?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160, max: 200)
        } rows: {
            if let searchResults {
                ForEach(searchResults) { TableRow($0) }
            } else {
                ForEach(tree.roots) { root in
                    SnapshotRows(node: root, isExpanded: isExpanded, setExpanded: setExpanded)
                }
            }
        }
    }

    /// A folder shows everything beneath it added up — "how big is this
    /// folder" is the first thing a restore asks. A symlink has no size of
    /// its own to show.
    private static func sizeText(for node: SnapshotTree.Node) -> String {
        guard node.isDirectory || node.size != nil else { return "–" }
        return ByteCountFormatter.string(fromByteCount: node.totalSize, countStyle: .file)
    }
}

/// One node and, when it is an open folder, everything inside it.
///
/// Recursive `DisclosureTableRow`s rather than `OutlineGroup`: an outline
/// group keeps which rows are open to itself, and the window needs to say —
/// the top level starts open, and closing a folder has to deselect what was
/// selected inside it. Measured on 60 000 entries with every folder open, the
/// table stays lazy: the main thread never stalled for longer than a tenth of
/// a second.
private struct SnapshotRows: TableRowContent {
    let node: SnapshotTree.Node
    let isExpanded: (SnapshotTree.Node) -> Bool
    let setExpanded: (SnapshotTree.Node, Bool) -> Void

    @TableRowBuilder<SnapshotTree.Node>
    var tableRowBody: some TableRowContent<SnapshotTree.Node> {
        // An empty folder gets no triangle: there is nothing to open.
        if let children = node.children, !children.isEmpty {
            DisclosureTableRow(node, isExpanded: Binding(
                get: { isExpanded(node) },
                set: { setExpanded(node, $0) }
            )) {
                ForEach(children) { child in
                    SnapshotRows(node: child, isExpanded: isExpanded, setExpanded: setExpanded)
                }
            }
        } else {
            TableRow(node)
        }
    }
}

private struct NameCell: View {
    let node: SnapshotTree.Node
    /// In a flat list of matches the folder is the only thing telling two
    /// files of the same name apart, so it rides along after the name.
    let showsLocation: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: FileIcon.image(for: node))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if showsLocation {
                // Cut from the front: the end of a path is the part that
                // says where the file is.
                Text((node.path as NSString).deletingLastPathComponent)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}

/// The icons Finder would draw, so a snapshot reads like the folder it was
/// taken from. One lookup per file type, not per row.
@MainActor
private enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for node: SnapshotTree.Node) -> NSImage {
        // A slash cannot be in a file extension, so these two keys are safe.
        let key: String
        let type: UTType
        if node.isDirectory {
            key = "/folder"
            type = .folder
        } else if node.isSymlink {
            key = "/symlink"
            type = .aliasFile
        } else {
            key = (node.name as NSString).pathExtension.lowercased()
            type = UTType(filenameExtension: key) ?? .data
        }
        if let cached = cache[key] {
            return cached
        }
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}
