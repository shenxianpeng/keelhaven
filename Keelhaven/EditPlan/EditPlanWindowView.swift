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
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private func content(for plan: BackupPlan) -> some View {
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

            verificationSection

            retentionSection

            destinationRow(for: plan)

            excludeSection

            advancedSection

            Divider()

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
                        excludePatterns: model.excludePatterns,
                        schedule: model.builtSchedule(),
                        checkCadence: model.checkCadence,
                        retention: model.retention,
                        performance: model.builtPerformance()
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isValid)
            }
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
            List {
                ForEach(model.sourcePaths, id: \.self) { path in
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
            .frame(height: 110)
            .overlay {
                if model.sourcePaths.isEmpty {
                    Text("No folders yet — add at least one.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Verification")
                .font(.headline)
            Picker("Verification", selection: $model.checkCadence) {
                Text("Weekly").tag(CheckCadence.weekly)
                Text("Monthly").tag(CheckCadence.monthly)
                Text("Off").tag(CheckCadence.off)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Text("Runs restic's own repository check after a backup, and only speaks up when something is wrong.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Retention")
                .font(.headline)
            Picker("Retention", selection: $model.retention) {
                Text("Keep everything").tag(RetentionPolicy.off)
                Text("A year of history").tag(RetentionPolicy.year)
                Text("A month of history").tag(RetentionPolicy.month)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)
            Text("Thins older snapshots to daily, weekly and monthly keepers and reclaims the space — after a backup, at most once a week. Keep everything never deletes a snapshot.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
            Text("The destination can't be changed. To back up somewhere else, create a new backup plan.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Collapsed like the exclude patterns above it, and for the same
    /// reason: nobody needs it to make a working backup. These map to restic
    /// flags one to one, and an empty field means the flag is left off
    /// entirely rather than sent with a value we picked.
    private var advancedSection: some View {
        DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Leave these empty unless a backup is too slow or takes too much of your connection. Empty means restic's own default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                advancedField(
                    title: "Upload limit",
                    placeholder: "Unlimited",
                    unit: "KiB/s",
                    text: $model.uploadLimitText,
                    explanation: "Caps how fast a backup uploads, so it can't take the whole connection. Only affects backups to a server — a local disk ignores it."
                )

                advancedField(
                    title: "Files read at once",
                    placeholder: "Default (2)",
                    unit: "1–32",
                    text: $model.readConcurrencyText,
                    explanation: "Lower this on an external hard disk, where reading several files at once makes it slower. Raise it on a fast internal SSD."
                )

                advancedField(
                    title: "Pack size",
                    placeholder: "Default (16)",
                    unit: "MiB (4–128)",
                    text: $model.packSizeText,
                    explanation: "Larger packs mean fewer, bigger uploads. Worth raising for cloud storage that charges per request; leave it alone otherwise."
                )
            }
            .padding(.top, 6)
        }
    }

    private func advancedField(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        unit: LocalizedStringKey,
        text: Binding<String>,
        explanation: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .frame(width: 130, alignment: .leading)
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var excludeSection: some View {
        DisclosureGroup("Exclude patterns") {
            VStack(alignment: .leading, spacing: 8) {
                List {
                    ForEach(model.excludePatterns, id: \.self) { pattern in
                        HStack {
                            Text(pattern)
                                .font(.callout.monospaced())
                            Spacer()
                            Button {
                                model.removeExcludePattern(pattern)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(pattern)")
                        }
                    }
                }
                .frame(height: 100)
                HStack {
                    TextField("*.log", text: $model.newExcludePattern)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { model.addExcludePattern() }
                    Button("Add") {
                        model.addExcludePattern()
                    }
                    .disabled(model.newExcludePattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Files and folders matching these patterns are skipped.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }
}
