import SwiftUI
import KeelhavenCore

/// The wizard's last step: the four settings that used to be reachable only
/// after the plan existed, plus the summary and the name field.
///
/// It exists because the first backup starts the instant the plan is created
/// — so "edit it afterwards" meant one whole backup had already run on
/// defaults, with the wrong excludes and no retention (issue #39). Every
/// control here already carries a sensible default, so clicking straight
/// through to Create is still a complete answer.
struct OptionsStepView: View {
    @Bindable var model: WizardModel

    var body: some View {
        // The two disclosure groups can each add a screenful; the step scrolls
        // rather than pushing Create out of the window.
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Anything to fine-tune?")
                    .font(.title3)

                Text("These all have sensible defaults. You can change them later under Edit Plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VerificationSection(cadence: $model.options.checkCadence)

                RetentionSection(retention: $model.options.retention)

                ExcludePatternsSection(options: model.options)

                AdvancedPerformanceSection(options: model.options)

                Divider()

                summary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
