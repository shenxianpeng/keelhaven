import SwiftUI
import KeelhavenCore

/// Edits an existing plan's name, folders, schedule, exclude patterns
/// and the collapsed Advanced restic knobs.
/// The destination is shown but locked: changing it means a different
/// repository and password, which is a new plan, not an edit (issue #42).
struct EditPlanWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = EditPlanModel()

    private var plan: BackupPlan? {
        appState.plans.first { $0.id == appState.editPlanID }
    }

    var body: some View {
        Group {
            if let plan {
                content(for: plan)
                    .task(id: plan.id) {
                        model.load(from: plan)
                    }
            } else {
                Text("This backup plan no longer exists.")
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Expanding Exclude patterns or Advanced used to grow this window past
        // the bottom of the screen with no way to scroll or shrink it back
        // (issue #39): the content had no scroll view, and `.contentSize`
        // resizability pinned the window to whatever height the content asked
        // for. Now the sections scroll and the window is the user's to resize.
        .frame(
            minWidth: 560,
            idealWidth: 560,
            maxWidth: .infinity,
            minHeight: 320,
            idealHeight: 640,
            maxHeight: .infinity
        )
    }

    @ViewBuilder
    private func content(for plan: BackupPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Edit “\(plan.name)”")
                        .font(.title3.bold())

                    TextField("Name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)

                    folderList

                    Text("Schedule")
                        .font(.headline)
                    ScheduleEditor(kind: $model.scheduleKind, dailyTime: $model.dailyTime, weekday: $model.weekday)

                    VerificationSection(cadence: $model.options.checkCadence)

                    RetentionSection(options: model.options)

                    destinationRow(for: plan)

                    ExcludePatternsSection(options: model.options)

                    AdvancedPerformanceSection(options: model.options)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Outside the scroll view on purpose: Save used to ride the
            // bottom of the content and disappear off-screen the moment a
            // section was expanded.
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    appState.updatePlan(
                        id: plan.id,
                        name: model.name,
                        sourcePaths: model.sourcePaths,
                        excludePatterns: model.options.excludePatterns,
                        schedule: model.builtSchedule(),
                        checkCadence: model.options.checkCadence,
                        retention: model.options.builtRetention(),
                        performance: model.options.builtPerformance(),
                        backupOptions: model.options.builtBackupOptions()
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isValid)
            }
            .padding(16)
        }
    }

    // Same list-row pattern as the wizard's source step (add button above the
    // list), minus the preset chips and the name autofill — editing must never
    // silently rename.
    private var folderList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Folders")
                    .font(.headline)
                Spacer()
                Button {
                    let urls = FolderPicker.pickFolders()
                    for url in urls where !model.sourcePaths.contains(url.path) {
                        model.sourcePaths.append(url.path)
                    }
                } label: {
                    Label("Add Folders…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            PlanRowBox(
                items: model.sourcePaths,
                emptyText: "No folders yet — add at least one."
            ) { path in
                HStack {
                    Image(systemName: "folder")
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        model.sourcePaths.removeAll { $0 == path }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(path)")
                }
            }
        }
    }

    private func destinationRow(for plan: BackupPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Destination")
                .font(.headline)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text(plan.destination.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("The destination can't be changed. To back up somewhere else, choose Duplicate Plan… from the plan's action menu — everything else carries over.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
