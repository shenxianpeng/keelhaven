import SwiftUI
import KeelhavenCore

struct WizardWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = WizardModel()

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
