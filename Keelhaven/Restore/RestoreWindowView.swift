import SwiftUI
import KeelhavenCore

struct RestoreWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model: RestoreModel

    /// The model can be handed in so the window can be shown in a given state
    /// without the app around it; the app itself always takes the default.
    @MainActor
    init(model: RestoreModel? = nil) {
        _model = State(initialValue: model ?? RestoreModel())
    }

    private var plan: BackupPlan? {
        appState.plans.first { $0.id == appState.restorePlanID }
    }

    var body: some View {
        Group {
            if let plan {
                content(for: plan)
                    .task(id: plan.id) {
                        await model.loadSnapshots(appState: appState, plan: plan)
                    }
            } else {
                Text("This backup plan no longer exists.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        // Resizable, with the old fixed size as its floor: a snapshot list is
        // happy in a small window, a folder of long file names is not.
        .frame(minWidth: 520, idealWidth: 600, minHeight: 400, idealHeight: 460)
    }

    @ViewBuilder
    private func content(for plan: BackupPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore “\(plan.name)”")
                .font(.title3.bold())

            switch model.phase {
            case .loadingSnapshots:
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("Loading snapshots…")
                    Spacer()
                }
                Spacer()

            case .selecting:
                if model.snapshots.isEmpty {
                    Spacer()
                    Text("No snapshots yet — run a backup first.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Text("Choose a point in time. Files are restored into a new folder — nothing is overwritten.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Table(model.snapshots, selection: $model.selectedSnapshotID) {
                        TableColumn("Date") { snapshot in
                            Text(snapshot.time.formatted(date: .abbreviated, time: .shortened))
                        }
                        TableColumn("Files") { snapshot in
                            Text(snapshot.summary?.totalFilesProcessed.map(String.init) ?? "–")
                        }
                        .width(70)
                        TableColumn("Size") { snapshot in
                            Text(snapshot.summary?.totalBytesProcessed.map {
                                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                            } ?? "–")
                        }
                        .width(90)
                    }
                    // A snapshot restic wrote before it gave up on unreadable
                    // files is a real point in time that is missing them.
                    // Restoring it is still the right thing to offer — half a
                    // backup beats none — but not silently, and not after the
                    // button that acts on it.
                    if model.selectedSnapshotIsIncomplete {
                        Label(
                            "This snapshot is incomplete: some files could not be read when it was made.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    // Everything is the default and stays one click away.
                    // Picking files out is the other road, off to the side,
                    // for whoever came for one document.
                    HStack {
                        Button("Choose Files…") {
                            model.browseSelectedSnapshot(appState: appState, plan: plan)
                        }
                        .disabled(model.selectedSnapshotID == nil)
                        Spacer()
                        Button("Cancel") { dismiss() }
                        Button("Restore To…") {
                            pickTargetAndRestore(plan: plan)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selectedSnapshotID == nil)
                    }
                }

            case .loadingContents(let entriesRead):
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        ProgressView("Reading what is in this backup…")
                        // restic says nothing while it opens the repository,
                        // so there is no count to show until entries arrive.
                        Text("\(entriesRead) items so far")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .opacity(entriesRead > 0 ? 1 : 0)
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancelReadingContents() }
                }

            case .browsing:
                browser(for: plan)

            case .restoring(let progress):
                Spacer()
                ProgressView(value: progress) {
                    Text("Restoring… \(Int(progress * 100))%")
                }
                Spacer()

            case .finished(let targetURL, let reveal, let filesRestored):
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                        Text("Restored \(filesRestored) items")
                            .font(.headline)
                        Text(targetURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(reveal)
                    }
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }

            case .failed(let message):
                Spacer()
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Spacer()
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// One snapshot, opened up: find the file, select it, bring it back.
    @ViewBuilder
    private func browser(for plan: BackupPlan) -> some View {
        if let tree = model.tree {
            let selected = model.selectedNodes
            HStack(alignment: .firstTextBaseline) {
                if let snapshot = model.selectedSnapshot {
                    Text("Backup from \(snapshot.time.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(
                    "Search",
                    text: Binding(get: { model.searchText }, set: { model.search(for: $0) }),
                    prompt: Text("Search by name")
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            }
            SnapshotBrowserView(
                tree: tree,
                searchResults: model.searchResults,
                searchText: model.searchText,
                selection: $model.contentSelection,
                isExpanded: { model.expandedFolders.contains($0.id) },
                setExpanded: { model.setExpanded($0, $1) }
            )
            // The file someone is looking for may be one of the ones this
            // snapshot never got, so the warning follows them in here.
            if model.selectedSnapshotIsIncomplete {
                Label(
                    "This snapshot is incomplete: some files could not be read when it was made.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Group {
                    if selected.isEmpty {
                        Text("Select the files or folders to bring back.")
                    } else {
                        // The total a restore would write, with a folder
                        // counted as everything inside it.
                        Text("\(selected.count) selected — \(ByteCountFormatter.string(fromByteCount: selected.reduce(0) { $0 + $1.totalSize }, countStyle: .file))")
                            .monospacedDigit()
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Back") { model.backToSnapshots() }
                Button("Restore Selected…") {
                    pickTargetAndRestore(plan: plan, only: selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
    }

    private func pickTargetAndRestore(plan: BackupPlan, only nodes: [SnapshotTree.Node] = []) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Restore Here")
        panel.message = String(localized: "Choose where to put the restored files. Keelhaven creates a new subfolder — existing files are never touched.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parentURL = panel.urls.first else { return }
        model.restore(appState: appState, plan: plan, into: parentURL, only: nodes)
    }
}
