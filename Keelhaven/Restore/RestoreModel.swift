import Foundation
import Observation
import KeelhavenCore

/// Drives the restore window: load a plan's snapshots, then restore a chosen
/// one into a fresh subfolder of a user-picked destination.
@MainActor
@Observable
final class RestoreModel {
    enum Phase {
        case loadingSnapshots
        case selecting
        case restoring(progress: Double)
        case finished(targetURL: URL, filesRestored: Int)
        case failed(String)
    }

    var phase: Phase = .loadingSnapshots
    var snapshots: [ResticSnapshot] = []
    var selectedSnapshotID: ResticSnapshot.ID?
    /// Snapshots a failed run left behind. restic stores what it could read and
    /// then exits 3, so these are real points in time that are missing files —
    /// the restore window says so instead of presenting them as ordinary ones.
    private(set) var incompleteSnapshotIDs: Set<String> = []

    /// True when the snapshot the user is about to restore is one of those.
    var selectedSnapshotIsIncomplete: Bool {
        guard let selectedSnapshotID else { return false }
        return incompleteSnapshotIDs.contains(selectedSnapshotID)
    }

    func loadSnapshots(appState: AppState, plan: BackupPlan) async {
        phase = .loadingSnapshots
        do {
            guard let binaryURL = appState.resticBinaryURL else {
                throw ResticError.binaryNotFound
            }
            let credentials = try appState.restoreCredentials(for: plan)
            let runner = ResticRunner(binaryURL: binaryURL)
            let loaded = try await runner.run(
                .snapshots,
                destination: plan.destination,
                credentials: credentials,
                decoding: [ResticSnapshot].self
            )
            // Newest first — the most likely restore point on top.
            snapshots = loaded.sorted { $0.time > $1.time }
            selectedSnapshotID = snapshots.first?.id
            incompleteSnapshotIDs = await appState.incompleteSnapshotIDs(for: plan.id)
            phase = .selecting
        } catch {
            phase = .failed(errorText(error))
        }
    }

    func restore(appState: AppState, plan: BackupPlan, into parentURL: URL) {
        guard let snapshotID = selectedSnapshotID else { return }
        phase = .restoring(progress: 0)
        Task {
            do {
                guard let binaryURL = appState.resticBinaryURL else {
                    throw ResticError.binaryNotFound
                }
                let credentials = try appState.restoreCredentials(for: plan)

                // Always restore into a fresh, uniquely named subfolder so an
                // existing file can never be overwritten.
                let stamp = Date().formatted(
                    .dateTime.year().month(.twoDigits).day(.twoDigits)
                        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                ).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
                let safeName = plan.name.replacingOccurrences(of: "/", with: "-")
                let targetURL = parentURL.appendingPathComponent(
                    "Keelhaven Restore \(safeName) \(stamp)",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

                let runner = ResticRunner(binaryURL: binaryURL)
                let events = runner.restoreStream(
                    .restore(snapshotID: snapshotID, target: targetURL.path, includes: []),
                    destination: plan.destination,
                    credentials: credentials
                )

                var summary: RestoreSummary?
                for try await event in events {
                    switch event {
                    case .status(let status):
                        phase = .restoring(progress: status.percentDone)
                    case .summary(let value):
                        summary = value
                    }
                }
                phase = .finished(targetURL: targetURL, filesRestored: summary?.filesRestored ?? 0)
            } catch {
                phase = .failed(errorText(error))
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? ResticError)?.localizedDescription ?? error.localizedDescription
    }
}
