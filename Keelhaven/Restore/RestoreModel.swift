import Foundation
import Observation
import KeelhavenCore

/// Drives the restore window: load a plan's snapshots, then restore a chosen
/// one — all of it, or the files picked out of it — into a fresh subfolder of
/// a user-picked destination.
@MainActor
@Observable
final class RestoreModel {
    enum Phase {
        case loadingSnapshots
        case selecting
        /// Reading what is inside one snapshot. The one slow step in the
        /// window — restic has to open the repository and walk the whole
        /// snapshot, seconds on a remote one (see `SnapshotTree`) — so it
        /// counts what has arrived and can be cancelled.
        case loadingContents(entriesRead: Int)
        case browsing
        case restoring(progress: Double)
        /// `reveal` is what Finder should select: the restored items when
        /// they were picked out, the new folder when it was everything.
        case finished(targetURL: URL, reveal: [URL], filesRestored: Int)
        case failed(String)
    }

    var phase: Phase = .loadingSnapshots
    var snapshots: [ResticSnapshot] = []
    var selectedSnapshotID: ResticSnapshot.ID?
    /// Snapshots a failed run left behind. restic stores what it could read and
    /// then exits 3, so these are real points in time that are missing files —
    /// the restore window says so instead of presenting them as ordinary ones.
    private(set) var incompleteSnapshotIDs: Set<String> = []

    /// True when the snapshot the user is about to restore is one of those.
    var selectedSnapshotIsIncomplete: Bool {
        guard let selectedSnapshotID else { return false }
        return incompleteSnapshotIDs.contains(selectedSnapshotID)
    }

    var selectedSnapshot: ResticSnapshot? {
        snapshots.first { $0.id == selectedSnapshotID }
    }

    // MARK: - Inside one snapshot

    /// The contents of the snapshot being browsed. Kept after going back to
    /// the list, so returning to the same snapshot does not read it twice.
    private(set) var tree: SnapshotTree?
    private var treeSnapshotID: ResticSnapshot.ID?
    var contentSelection: Set<SnapshotTree.Node.ID> = []
    var expandedFolders: Set<SnapshotTree.Node.ID> = []
    private(set) var searchText = ""
    /// The matches while a search is on, in tree order; nil shows the tree.
    private(set) var searchResults: [SnapshotTree.Node]?
    private var contentsTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    /// What a restore from the browser would bring back: the selection, with
    /// anything inside an already selected folder counted once.
    var selectedNodes: [SnapshotTree.Node] {
        tree?.effectiveSelection(contentSelection) ?? []
    }

    func loadSnapshots(appState: AppState, plan: BackupPlan) async {
        phase = .loadingSnapshots
        do {
            guard let binaryURL = appState.resticBinaryURL else {
                throw ResticError.binaryNotFound
            }
            let credentials = try appState.restoreCredentials(for: plan)
            let runner = ResticRunner(binaryURL: binaryURL)
            let loaded = try await runner.run(
                .snapshots,
                destination: plan.destination,
                credentials: credentials,
                decoding: [ResticSnapshot].self
            )
            // Newest first — the most likely restore point on top.
            snapshots = loaded.sorted { $0.time > $1.time }
            selectedSnapshotID = snapshots.first?.id
            incompleteSnapshotIDs = await appState.incompleteSnapshotIDs(for: plan.id)
            phase = .selecting
        } catch {
            phase = .failed(errorText(error))
        }
    }

    /// Reads the selected snapshot and opens it for browsing.
    func browseSelectedSnapshot(appState: AppState, plan: BackupPlan) {
        guard let snapshot = selectedSnapshot else { return }
        if treeSnapshotID == snapshot.id, let tree {
            // Read once, but shown afresh every time. The table is rebuilt
            // when the browser comes back and does not reopen the folders it
            // had open — so carrying the old selection over left a file
            // selected inside a folder that was now closed: counted in the
            // footer, about to be restored, and nowhere on screen.
            open(tree, of: snapshot.id)
            return
        }

        phase = .loadingContents(entriesRead: 0)
        contentsTask = Task {
            do {
                guard let binaryURL = appState.resticBinaryURL else {
                    throw ResticError.binaryNotFound
                }
                let credentials = try appState.restoreCredentials(for: plan)
                let built = try await Self.readContents(
                    of: snapshot,
                    with: ResticRunner(binaryURL: binaryURL),
                    destination: plan.destination,
                    credentials: credentials
                ) { [weak self] entriesRead in
                    // A count that was already on its way when the user
                    // cancelled must not put the progress screen back.
                    guard !Task.isCancelled else { return }
                    self?.phase = .loadingContents(entriesRead: entriesRead)
                }
                guard !Task.isCancelled else { return }
                open(built, of: snapshot.id)
            } catch {
                // Cancelling ends restic with a signal, which arrives here as
                // a failed run. It is not one: the user asked for it, and
                // `cancelReadingContents` has already put the list back.
                guard !Task.isCancelled else { return }
                phase = .failed(errorText(error))
            }
        }
    }

    /// Reads a snapshot's listing and builds its tree, away from the main
    /// actor. Tens of thousands of entries arrive faster than they can be
    /// taken one main-actor hop at a time without the window stuttering, and
    /// sorting and totalling them afterwards is real work too — so only the
    /// running count crosses over, every few hundred entries: often enough
    /// to show it is alive, rarely enough not to be thousands of redraws.
    private nonisolated static func readContents(
        of snapshot: ResticSnapshot,
        with runner: ResticRunner,
        destination: Destination,
        credentials: RepoCredentials,
        progress: @MainActor @Sendable (Int) -> Void
    ) async throws -> SnapshotTree {
        var nodes: [ResticLsNode] = []
        var rootPaths = snapshot.paths
        let events = runner.listStream(
            .ls(snapshotID: snapshot.id),
            destination: destination,
            credentials: credentials
        )
        for try await event in events {
            switch event {
            case .snapshot(let header):
                rootPaths = header.paths
            case .node(let node):
                nodes.append(node)
                if nodes.count.isMultiple(of: 500) {
                    await progress(nodes.count)
                }
            }
        }
        try Task.checkCancellation()
        return SnapshotTree.build(from: nodes, rootedAt: rootPaths)
    }

    func cancelReadingContents() {
        contentsTask?.cancel()
        contentsTask = nil
        phase = .selecting
    }

    func backToSnapshots() {
        phase = .selecting
    }

    private func open(_ built: SnapshotTree, of snapshotID: ResticSnapshot.ID) {
        tree = built
        treeSnapshotID = snapshotID
        contentSelection = []
        searchText = ""
        searchResults = nil
        expandedFolders = Self.topLevelFolders(of: built)
        phase = .browsing
    }

    /// The top level starts open. A plan with one source folder would
    /// otherwise greet the user with a single closed row.
    private static func topLevelFolders(of tree: SnapshotTree) -> Set<SnapshotTree.Node.ID> {
        Set(tree.roots.filter(\.isDirectory).map(\.id))
    }

    /// Searching replaces the tree with a flat list of matches.
    ///
    /// The selection is dropped whenever the query changes: what is selected
    /// is what gets restored, so nothing may stay selected in a list that no
    /// longer shows it.
    func search(for text: String) {
        guard text != searchText else { return }
        searchText = text
        contentSelection = []
        searchTask?.cancel()

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tree, !query.isEmpty else {
            // Back to the outline, and to the outline as it first appears:
            // the rows are built again, and what was open before the search
            // is not something the table brings back.
            searchResults = nil
            if let tree {
                expandedFolders = Self.topLevelFolders(of: tree)
            }
            return
        }
        // A pass over every entry per keystroke, so it stays off the main
        // actor; a result that arrives after the next keystroke is dropped.
        searchTask = Task {
            let matches = await Task.detached { tree.search(query) }.value
            guard !Task.isCancelled else { return }
            searchResults = matches
        }
    }

    /// Collapsing a folder deselects what was selected inside it, for the
    /// same reason a new search clears the selection.
    func setExpanded(_ node: SnapshotTree.Node, _ isExpanded: Bool) {
        if isExpanded {
            expandedFolders.insert(node.id)
        } else {
            expandedFolders.remove(node.id)
            contentSelection = contentSelection.filter { !node.contains(path: $0) }
        }
    }

    /// Restores the selected snapshot into a new subfolder of `parentURL`:
    /// all of it, or only `nodes` when the user picked files out of it.
    func restore(appState: AppState, plan: BackupPlan, into parentURL: URL, only nodes: [SnapshotTree.Node] = []) {
        guard let snapshotID = selectedSnapshotID else { return }
        let includes = nodes.map(\.path)
        phase = .restoring(progress: 0)
        Task {
            do {
                guard let binaryURL = appState.resticBinaryURL else {
                    throw ResticError.binaryNotFound
                }
                let credentials = try appState.restoreCredentials(for: plan)

                // Always restore into a fresh, uniquely named subfolder so an
                // existing file can never be overwritten.
                let stamp = Date().formatted(
                    .dateTime.year().month(.twoDigits).day(.twoDigits)
                        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                ).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
                let safeName = plan.name.replacingOccurrences(of: "/", with: "-")
                let targetURL = parentURL.appendingPathComponent(
                    "Keelhaven Restore \(safeName) \(stamp)",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

                let runner = ResticRunner(binaryURL: binaryURL)
                let events = runner.restoreStream(
                    .restore(snapshotID: snapshotID, target: targetURL.path, includes: includes),
                    destination: plan.destination,
                    credentials: credentials
                )

                var summary: RestoreSummary?
                for try await event in events {
                    switch event {
                    case .status(let status):
                        phase = .restoring(progress: status.percentDone)
                    case .summary(let value):
                        summary = value
                    }
                }
                let reveal = RestoreLayout.pathsToReveal(target: targetURL.path, includes: includes)
                    .map { URL(fileURLWithPath: $0) }
                // restic's own count includes every folder it had to recreate
                // above a restored file — eight of them for one document a
                // few levels down. For a selection, the number that means
                // something is how many things were picked.
                phase = .finished(
                    targetURL: targetURL,
                    reveal: reveal,
                    filesRestored: nodes.isEmpty ? (summary?.filesRestored ?? 0) : nodes.count
                )
            } catch {
                phase = .failed(errorText(error))
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? ResticError)?.localizedDescription ?? error.localizedDescription
    }
}
