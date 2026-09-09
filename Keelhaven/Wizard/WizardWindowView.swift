import SwiftUI
import KeelhavenCore

/// The three-step flow for creating a plan. Serves both windows that create
/// one: the New Backup Plan window from an empty draft, and the Duplicate
/// Backup Plan window seeded from an existing plan (issue #62). Same steps,
/// same destination forms and conflict rules — only the starting draft
/// differs, so one view drives both.
struct WizardWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = WizardModel()

    /// True in the Duplicate Backup Plan window: the model is seeded from the
    /// plan named by `appState.duplicatePlanID` instead of starting blank.
    let isDuplicate: Bool

    init(isDuplicate: Bool = false) {
        self.isDuplicate = isDuplicate
    }

    private let stepTitles = [
        String(localized: "What to back up"),
        String(localized: "Where to"),
        String(localized: "When"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch model.step {
                case 0:
                    SourceStepView(model: model)
                case 1:
                    DestinationStepView(model: model)
                default:
                    ScheduleStepView(model: model)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .onAppear {
            model.existingRepositoryLocations = appState.plans.map { $0.destination.repositoryLocation }
        }
        // Seeds the duplicate from its source plan. `.task(id:)`, not
        // `onAppear`: it also re-seeds when the user picks another plan's
        // Duplicate Plan… while this window stays open — the same handoff the
        // Edit Plan window uses for `editPlanID`. Runs on first appearance
        // regardless of the id, so a reopened window re-seeds even when
        // `duplicatePlanID` did not change.
        .task(id: appState.duplicatePlanID) {
            guard isDuplicate,
                  let id = appState.duplicatePlanID,
                  let plan = appState.plans.first(where: { $0.id == id })
            else { return }
            model.loadForDuplicate(from: plan)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ForEach(0..<WizardModel.stepCount, id: \.self) { index in
                HStack(spacing: 6) {
                    Image(systemName: index < model.step ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(index <= model.step ? Color.accentColor : Color.secondary)
                    Text(stepTitles[index])
                        .fontWeight(index == model.step ? .semibold : .regular)
                        .foregroundStyle(index == model.step ? .primary : .secondary)
                }
                if index < WizardModel.stepCount - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: 40)
                }
            }
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(model.step + 1) of \(WizardModel.stepCount): \(stepTitles[model.step])")
    }

    private var footer: some View {
        HStack {
            if let creationError = model.creationError {
                Text(creationError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(4)
                    .help(creationError)
            } else if let hint = model.blockingHint, !model.isVerifyingPassword {
                // Why Next is grayed out (issue #38) — guidance, not an
                // error, so it stays secondary rather than red.
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(hint)
            }
            Spacer()

            if model.step > 0 {
                Button("Back") {
                    model.step -= 1
                    model.creationError = nil
                }
                .disabled(model.isCreating)
            }

            if model.step < WizardModel.stepCount - 1 {
                Button {
                    advance()
                } label: {
                    if model.isVerifyingPassword {
                        Text("Verifying Password…")
                    } else {
                        Text("Next")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canAdvance || model.isVerifyingPassword)
            } else {
                Button {
                    create()
                } label: {
                    if model.isCreating {
                        Text("Creating Repository…")
                    } else {
                        Text("Create Backup Plan")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isCreating)
            }
        }
        .padding(16)
    }

    /// Leaving the destination step while adopting an existing repository
    /// verifies the password right away (issue #30), so a typo surfaces next
    /// to the password field instead of at the final Create.
    private func advance() {
        model.creationError = nil
        if model.step == 0 {
            model.autoGeneratePasswordIfNeeded()
        }
        guard model.step == 1, model.adoptExistingRepository else {
            model.step += 1
            return
        }
        guard let binaryURL = appState.resticBinaryURL else {
            model.passwordVerificationError = ResticError.binaryNotFound.localizedDescription
            return
        }
        Task {
            if await model.verifyExistingRepositoryPassword(binaryURL: binaryURL) {
                model.step += 1
            }
        }
    }

    private func create() {
        model.isCreating = true
        model.creationError = nil
        let draft = model.buildDraft()
        Task {
            do {
                try await appState.createPlan(from: draft)
                model.isCreating = false
                model.reset()
                dismiss()
            } catch {
                model.isCreating = false
                model.creationError = error.localizedDescription
            }
        }
    }
}
