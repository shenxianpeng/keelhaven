import SwiftUI
import KeelhavenCore

struct ScheduleStepView: View {
    @Bindable var model: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How often should it run?")
                .font(.title3)

            ScheduleEditor(kind: $model.scheduleKind, dailyTime: $model.dailyTime, weekday: $model.weekday)

            // Surprise-proofing, not decoration: the first run starts on
            // creation (SchedulePolicy treats a never-run plan as due), and
            // users who set an evening time expect silence until then. One
            // footnote-sized block, System Settings style — not two callout
            // paragraphs competing with the summary.
            //
            // It is also why the next step exists: a backup that starts this
            // soon has to be fully configured before it does.
            Text("The first backup starts as soon as you create the plan. After that, backups run on this schedule, catching up automatically if your Mac was asleep or off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
