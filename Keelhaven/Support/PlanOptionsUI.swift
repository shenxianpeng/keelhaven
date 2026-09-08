import SwiftUI
import KeelhavenCore

// The controls for the four settings in `PlanOptionsDraft`, written once and
// shown identically by the wizard's Options step and the Edit Plan window.
// Same copy, same ranges, same explanations — the two used to disagree by
// simply not offering the settings at all on the wizard side (issue #39).

/// A bordered, scroll-free stand-in for `List`: plain rows in a rounded box.
///
/// Both windows using it scroll as a whole now, and a real `List` brings its
/// own scroll view — one that swallows the wheel whenever the pointer happens
/// to be over it, which is the very "stuck" feeling this change removes.
/// These rows just make the outer scroll longer.
struct PlanRowBox<Item: Hashable, Row: View>: View {
    let items: [Item]
    let emptyText: LocalizedStringKey
    let row: (Item) -> Row

    init(
        items: [Item],
        emptyText: LocalizedStringKey,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        self.emptyText = emptyText
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    row(item)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

/// How often `restic check` rides the tail of a finished backup.
struct VerificationSection: View {
    @Binding var cadence: CheckCadence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Verification")
                .font(.headline)
            Picker("Verification", selection: $cadence) {
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How much snapshot history to keep. `off` — never delete — is the default.
struct RetentionSection: View {
    @Binding var retention: RetentionPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Retention")
                .font(.headline)
            Picker("Retention", selection: $retention) {
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Collapsed, because a working backup never needs it touched.
struct ExcludePatternsSection: View {
    @Bindable var options: PlanOptionsDraft

    var body: some View {
        DisclosureGroup("Exclude patterns") {
            VStack(alignment: .leading, spacing: 8) {
                PlanRowBox(
                    items: options.excludePatterns,
                    emptyText: "Nothing is excluded — every file in those folders is backed up."
                ) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.callout.monospaced())
                        Spacer()
                        Button {
                            options.removeExcludePattern(pattern)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(pattern)")
                    }
                }
                HStack {
                    TextField("*.log", text: $options.newExcludePattern)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { options.addExcludePattern() }
                    Button("Add") {
                        options.addExcludePattern()
                    }
                    .disabled(options.newExcludePattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Files and folders matching these patterns are skipped.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }
}

/// Collapsed like the exclude patterns above it, and for the same reason:
/// nobody needs it to make a working backup. These map to restic flags one to
/// one, and an empty field means the flag is left off entirely rather than
/// sent with a value we picked.
struct AdvancedPerformanceSection: View {
    @Bindable var options: PlanOptionsDraft

    var body: some View {
        DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Leave these empty unless a backup is too slow or takes too much of your connection. Empty means restic's own default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                field(
                    title: "Upload limit",
                    placeholder: "Unlimited",
                    unit: "KiB/s",
                    text: $options.uploadLimitText,
                    explanation: "Caps how fast a backup uploads, so it can't take the whole connection. Only affects backups to a server — a local disk ignores it."
                )

                field(
                    title: "Files read at once",
                    placeholder: "Default (2)",
                    unit: "1–32",
                    text: $options.readConcurrencyText,
                    explanation: "Lower this on an external hard disk, where reading several files at once makes it slower. Raise it on a fast internal SSD."
                )

                field(
                    title: "Pack size",
                    placeholder: "Default (16)",
                    unit: "MiB (4–128)",
                    text: $options.packSizeText,
                    explanation: "Larger packs mean fewer, bigger uploads. Worth raising for cloud storage that charges per request; leave it alone otherwise."
                )
            }
            .padding(.top, 6)
        }
    }

    private func field(
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
