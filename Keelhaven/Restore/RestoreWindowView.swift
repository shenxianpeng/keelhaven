import SwiftUI
import KeelhavenCore

struct RestoreWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = RestoreModel()

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
        .frame(width: 520, height: 400)
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
                    HStack {
                        Spacer()
                        Button("Cancel") { dismiss() }
                        Button("Restore To…") {
                            pickTargetAndRestore(plan: plan)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selectedSnapshotID == nil)
                    }
                }

            case .restoring(let progress):
                Spacer()
                ProgressView(value: progress) {
                    Text("Restoring… \(Int(progress * 100))%")
                }
                Spacer()

            case .finished(let targetURL, let filesRestored):
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
                        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
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

    private func pickTargetAndRestore(plan: BackupPlan) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Restore Here")
        panel.message = String(localized: "Choose where to put the restored files. Keelhaven creates a new subfolder — existing files are never touched.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parentURL = panel.urls.first else { return }
        model.restore(appState: appState, plan: plan, into: parentURL)
    }
}
