import SwiftUI
import KeelhavenCore

struct ScheduleStepView: View {
    @Bindable var model: WizardModel
    @State private var customizeExpanded = false

    var body: some View {
        // Only ever scrolls once Customize is opened; collapsed, the step
        // fits the window exactly as it did before that section existed.
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("How often should it run?")
                    .font(.title3)

                ScheduleEditor(kind: $model.scheduleKind, dailyTime: $model.dailyTime, weekday: $model.weekday)

                firstBackupRow

                customizeSection

                Divider()

                summary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The checkbox and the sentence that explains it, as one block.
    ///
    /// They belong together: the sentence *is* the promise the checkbox
    /// changes, and splitting the control into the summary below would leave
    /// a bare checkbox in a read-only recap and a claim up here that the
    /// choice can contradict (issue #42). On by default, so nobody who does
    /// not care ever has to look at it — unticking is the whole opt-in.
    private var firstBackupRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Start the first backup now", isOn: $model.firstBackupStartsOnCreation)
                .toggleStyle(.checkbox)
            // Surprise-proofing, not decoration: users who set an evening time
            // expect silence until then. One footnote-sized block, System
            // Settings style — not two callout paragraphs competing with the
            // summary.
            Text(firstBackupExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Says what will actually happen, naming the concrete time when the first
    /// backup is going to wait for it — "at the next scheduled time" alone
    /// leaves the user doing the arithmetic.
    private var firstBackupExplanation: String {
        let schedule = Schedule(kind: model.scheduleKind, dailyTime: model.dailyTime, weekday: model.weekday)
        if model.firstBackupStartsOnCreation {
            return String(localized: "The first backup starts as soon as you create the plan. After that, backups run on this schedule, catching up automatically if your Mac was asleep or off.")
        }
        let first = SchedulePolicy.nextRun(for: schedule, after: Date(), calendar: .current)
            .formatted(date: .abbreviated, time: .shortened)
        return String(localized: "The plan is created but stays idle: the first backup runs at \(first), then on this schedule — catching up automatically if your Mac was asleep or off. You can always start one yourself with Back Up Now.")
    }

    /// The four settings Edit Plan offers, collapsed — and staying collapsed
    /// is the point. Every one already holds the default a first-time user
    /// should never have to think about, so this adds one row to the step and
    /// no decisions; opening it is entirely opt-in (issue #41).
    ///
    /// Hand-rolled rather than a `DisclosureGroup`, matching the destination
    /// step's Advanced options: the whole two-line row is the click target,
    /// not just the chevron (issue #50).
    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                customizeExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(customizeExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Customize this plan")
                        Text("Verification, retention, excluded files, speed limits — all optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(customizeExpanded ? [.isSelected] : [])

            if customizeExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VerificationSection(cadence: $model.options.checkCadence)
                    RetentionSection(options: model.options)
                    ExcludePatternsSection(options: model.options)
                    AdvancedPerformanceSection(options: model.options)
                }
                .padding(.top, 12)
            }
        }
        .animation(.default, value: customizeExpanded)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(.headline)
            // The name is editable here, not on the source step: step one is
            // purely about picking folders, and the autofilled default (first
            // folder's name) only settles once those are chosen.
            HStack(alignment: .firstTextBaseline) {
                Text("Name")
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                TextField("Plan name (optional)", text: $model.name, prompt: Text(model.defaultName))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 300)
            }
            .font(.callout)
            summaryRow(
                label: String(localized: "Folders"),
                value: model.sourcePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            )
            summaryRow(label: String(localized: "Destination"), value: model.buildDraft().destination.displayName)
            summaryRow(
                label: String(localized: "Schedule"),
                value: Schedule(kind: model.scheduleKind, dailyTime: model.dailyTime, weekday: model.weekday).displayText
            )
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}
