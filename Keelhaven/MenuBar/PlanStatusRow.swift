import SwiftUI
import KeelhavenCore

struct PlanStatusRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let plan: BackupPlan

    private var runState: PlanRunState {
        appState.runStates[plan.id] ?? .idle
    }

    /// Docker-style health dot: blue while running, green when the last
    /// backup succeeded, red when it failed, gray before the first run.
    private var statusColor: Color {
        switch plan.health(runState: runState) {
        case .running: return .blue
        case .ok: return .green
        case .neverBackedUp: return .gray
        case .needsAttention: return .red
        }
    }

    /// The dot is blue for anything in flight, but only one of those things
    /// is a backup. Saying "Backup running" during a preview would tell a
    /// VoiceOver user that data is being written when a dry run writes
    /// nothing — the one claim this feature must never make (issue #43).
    /// The other three in-flight states were reading as backups too.
    private var statusAccessibilityLabel: String {
        switch runState {
        case .running:
            return String(localized: "Backup running")
        case .previewing:
            return String(localized: "Backup preview running")
        case .checking:
            return String(localized: "Backup verification running")
        case .pruning:
            return String(localized: "Retention cleanup running")
        case .unlocking:
            return String(localized: "Unlocking repository")
        case .idle, .succeeded, .failed, .failedLocked:
            switch plan.health(runState: runState) {
            case .running: return String(localized: "Backup running")
            case .ok: return String(localized: "Backed up")
            case .neverBackedUp: return String(localized: "Not backed up yet")
            case .needsAttention: return String(localized: "Last backup failed")
            }
        }
    }

    /// When the next scheduled run is due, shown as a tooltip on the status line.
    private var nextRunText: String {
        // Asks the policy about the whole plan, not just its schedule: a
        // never-run plan's anchor depends on how it was created, and computing
        // it here from `Date()` made this line disagree with the scheduler
        // (issue #42).
        let next = SchedulePolicy.nextRun(for: plan)
        if next <= Date() {
            return String(localized: "Next backup: as soon as possible")
        }
        return String(localized: "Next backup: \(next.formatted(date: .abbreviated, time: .shortened))")
    }

    var body: some View {
        // The dot hangs in its own column so the name, path and status line
        // share one left edge — the layout the landing-page mockup settled on.
        // Sizes stay at the elder-friendly values from #33 (10px dot, callout
        // secondary text), only the arrangement changes.
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
                .accessibilityLabel(statusAccessibilityLabel)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Long names truncate against the trailing button, so the
                    // hover tooltip carries the full title (issue #39).
                    Text(plan.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(plan.name)
                    Spacer()
                    trailingControl
                    planActionsMenu
                }
                Text(plan.destination.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(plan.destination.displayName)
                // The trigger policy, visible at a glance (issue #42) — the
                // status line's tooltip still carries the concrete next-run time.
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(plan.schedule.displayText)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Schedule: \(plan.schedule.displayText)"))
                // Absent until the first check so a fresh plan stays
                // uncluttered; red is reserved for an actual failed check.
                if let lastCheck = plan.lastCheck {
                    verificationLine(lastCheck)
                }
                // A lock-blocked cleanup is the one failure that never clears
                // itself and never shows up anywhere else: backups keep
                // succeeding, the dot stays green, and the weekly retry hits
                // the same lock forever. Its own line, with the way out.
                if let lastPrune = plan.lastPrune,
                   !lastPrune.success,
                   lastPrune.blockedByLock == true {
                    retentionBlockedLine(lastPrune)
                }
                statusLine
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            planActions
        }
    }

    /// Visible entry point for per-plan actions — the context menu alone was
    /// too hidden to discover (issue #11).
    private var planActionsMenu: some View {
        Menu {
            planActions
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(localized: "Actions for \(plan.name)"))
    }

    @ViewBuilder
    private var planActions: some View {
        Button("Restore…") {
            appState.restorePlanID = plan.id
            openWindow(id: WindowID.restore)
            NSApp.activate(ignoringOtherApps: true)
        }
        // No ellipsis, and next to Verify: both run immediately and need no
        // further input. A preview holds the repository like any other run,
        // so it carries the same gate.
        Button("Preview Backup") {
            runPreview()
        }
        .disabled(appState.isResticBusy || appState.resticBinaryURL == nil)
        Button("Verify Backup Now") {
            appState.runCheck(plan)
        }
        .disabled(appState.isResticBusy || appState.resticBinaryURL == nil)
        // Also reachable from the failed row itself. It stays in the menu for
        // the case the row can't cover: a relaunch resets the run state to
        // idle, so a plan still locked from yesterday shows only red text
        // until its next scheduled attempt re-detects the lock.
        Button("Unlock Repository…") {
            confirmAndUnlock()
        }
        .disabled(appState.isResticBusy || appState.resticBinaryURL == nil)
        Button("Edit Plan…") {
            appState.editPlanID = plan.id
            openWindow(id: WindowID.editPlan)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Rename…") {
            promptRename()
        }
        Button("Copy Repository Password") {
            copyPassword()
        }
        Divider()
        Button("Delete Backup Plan…", role: .destructive) {
            confirmAndDelete()
        }
        // Only this plan's own run blocks deletion — see AppState.deletePlan.
        .disabled(runState.isActive)
    }

    /// Confirmation dialogs use app-modal NSAlert, not SwiftUI `.alert`:
    /// inside a MenuBarExtra window, clicking an alert button tears down the
    /// panel and the follow-up work silently dies with it (issue #11).
    /// `NSApp.activate` first — an LSUIElement app that just lost its panel
    /// isn't active, and the modal/Touch ID dialogs need key status to show.

    private func promptRename() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename “\(plan.name)”")
        let field = NSTextField(string: plan.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.renamePlan(plan, to: field.stringValue)
    }

    private func confirmAndDelete() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(plan.name)”?")
        alert.informativeText = String(localized: "Removes the plan and its saved password from this Mac. Already backed-up data at the destination is not deleted.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete")).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deletePlan()
    }

    /// No Touch ID gate and no warning styling: this destroys no backup data,
    /// and `restic unlock` leaves a lock another Mac is actively holding
    /// alone. It still asks first, because it is worth saying what it does
    /// and does not reach.
    private func confirmAndUnlock() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Unlock the repository for “\(plan.name)”?")
        alert.informativeText = String(localized: "This clears locks left behind by a backup that was interrupted — the usual reason cleanup keeps failing. A backup running right now on another Mac keeps its own lock and is left alone; that one has to finish on its own.\n\nKeelhaven retries this plan's backup right after unlocking.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Unlock"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.unlockRepository(plan)
    }

    /// Runs the dry run and reports what it found. NSAlert for the same
    /// reason as the dialogs above: the panel is gone by the time the answer
    /// arrives, and a SwiftUI alert would go with it (issue #11).
    private func runPreview() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            let outcome = await appState.previewBackup(plan)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            switch outcome {
            case .summary(let summary):
                alert.messageText = String(localized: "Preview of “\(plan.name)”")
                alert.informativeText = Self.previewBody(summary)
                alert.alertStyle = .informational
            case .failed(let message):
                alert.messageText = String(localized: "Couldn't preview “\(plan.name)”")
                alert.informativeText = message
                alert.alertStyle = .warning
            case .unavailable(let message):
                alert.messageText = String(localized: "Can't preview right now")
                alert.informativeText = message
                alert.alertStyle = .informational
            }
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }

    /// The whole point of the feature in two sentences: what would be stored,
    /// and that nothing was. Says "nothing to store" plainly when that is the
    /// answer, rather than three zeroes the reader has to interpret.
    private static func previewBody(_ summary: BackupSummary) -> String {
        let nothingChanged = summary.filesNew == 0 && summary.filesChanged == 0
        if nothingChanged {
            return String(localized: "Nothing has changed since the last backup, so a backup right now would store nothing new.\n\nNothing was written — this was only a preview.")
        }
        let added = ByteCountFormatter.string(
            fromByteCount: summary.dataAdded ?? 0,
            countStyle: .file
        )
        let counts = String(
            localized: "\(summary.filesNew) new files and \(summary.filesChanged) changed, about \(added) to store."
        )
        return counts + "\n\n" + String(localized: "Nothing was written — this was only a preview.")
    }

    /// Both actions below are gated behind Touch ID (login password fallback
    /// on Macs without it).

    private func copyPassword() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard await BiometricAuthService.authenticate(
                reason: String(localized: "copy the backup password for “\(plan.name)”")
            ) else { return }
            guard let password = appState.repositoryPassword(for: plan) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(password, forType: .string)
        }
    }

    private func deletePlan() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard await BiometricAuthService.authenticate(
                reason: String(localized: "delete the backup plan “\(plan.name)”")
            ) else { return }
            // Seconds pass in Touch ID; the plan can start a scheduled check
            // meanwhile. The menu item was enabled when clicked, so if the
            // delete is declined now, say so — a silent no-op after a confirm
            // and a fingerprint reads as "it didn't work".
            if appState.deletePlan(plan) == .planIsActive {
                explainDeleteDeclined()
            }
        }
    }

    private func explainDeleteDeclined() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "“\(plan.name)” is busy right now")
        alert.informativeText = String(localized: "A backup or repository check for this plan is still running. Wait for it to finish, then delete the plan.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch runState {
        case .running:
            // The linear progress bar below already says "running" —
            // a second spinner up here is noise.
            EmptyView()
        default:
            Button("Back Up Now") {
                appState.runBackup(plan)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.isResticBusy || appState.resticBinaryURL == nil)
        }
    }

    /// Same formatter the completion notification uses, so "48 MB" in the
    /// row and "48 MB" in the notification never disagree.
    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Secondary, not orange or red: nothing is wrong. The plan checked, the
    /// folders were identical to the last snapshot, and nothing needed
    /// storing — which is the whole point of the option.
    private var unchangedLine: some View {
        Text("No changes — nothing new to back up")
            .font(.callout)
            .foregroundStyle(.secondary)
            .help(nextRunText)
    }

    private func verificationLine(_ check: CheckRunRecord) -> some View {
        HStack(spacing: 4) {
            Image(systemName: check.success ? "checkmark.shield" : "exclamationmark.shield")
            if check.success {
                Text("Verified \(check.date.formatted(date: .abbreviated, time: .omitted))")
            } else {
                Text("Verification failed")
            }
        }
        .font(.callout)
        .foregroundStyle(check.success ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        .help(check.success
            ? String(localized: "restic reported the repository intact on \(check.date.formatted(date: .abbreviated, time: .shortened))")
            : (check.errorMessage ?? String(localized: "The last repository check failed")))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(check.success
            ? String(localized: "Backup verified on \(check.date.formatted(date: .abbreviated, time: .omitted))")
            : String(localized: "Backup verification failed"))
    }

    /// Orange, not red: the backups themselves are fine and the health dot
    /// stays green — it is only the space reclaim that is stuck.
    private func retentionBlockedLine(_ prune: PruneRunRecord) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.exclamationmark")
            Text("Cleanup blocked by a repository lock")
            Button("Unlock…") {
                confirmAndUnlock()
            }
            .buttonStyle(.link)
            .disabled(appState.isResticBusy || appState.resticBinaryURL == nil)
        }
        .font(.callout)
        .foregroundStyle(.orange)
        .help(prune.errorMessage ?? String(localized: "The last retention pass could not get a lock on the repository"))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runState {
        case .running(let progress, let bytesDone):
            if let progress {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .padding(.top, 2)
                    .accessibilityLabel(String(localized: "Backup \(Int(progress * 100)) percent done"))
            } else {
                // No percentage to show — `--no-scan` means restic never
                // measured the sources (issue #51). The bar spins and the
                // amount copied stands in for it, which is the honest answer
                // rather than a bar frozen at zero.
                VStack(alignment: .leading, spacing: 4) {
                    if let bytesDone {
                        Text("\(Self.formatted(bytesDone)) backed up so far")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView()
                        .controlSize(.small)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    bytesDone.map { String(localized: "Backup running, \(Self.formatted($0)) so far") }
                        ?? String(localized: "Backup running")
                )
            }
        case .previewing(let progress):
            // Deliberately not a bare progress bar like `.running`: the two
            // would be indistinguishable, and someone glancing at the panel
            // would think a backup was being written.
            VStack(alignment: .leading, spacing: 4) {
                Text("Previewing what would be backed up…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let progress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                progress.map { String(localized: "Backup preview \(Int($0 * 100)) percent done") }
                    ?? String(localized: "Backup preview running")
            )
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Verifying backup…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Backup verification running"))
        case .pruning:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Cleaning up old snapshots…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Retention cleanup running"))
        case .unlocking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Unlocking repository…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Unlocking repository"))
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .help(message)
        case .failedLocked(let message):
            // restic's own three lines of PID-and-hostname detail stay in the
            // tooltip; the row says the one thing that matters and offers the
            // way out, which is the whole point of splitting this state off.
            VStack(alignment: .leading, spacing: 4) {
                Text("Backup blocked by a repository lock")
                    .font(.callout)
                    .foregroundStyle(.red)
                Button("Unlock…") {
                    confirmAndUnlock()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isResticBusy || appState.resticBinaryURL == nil)
            }
            .help(message)
        case .succeeded(let date):
            // "Backed up just now" would be a lie when the run stored
            // nothing: the newest snapshot is still the older one, which is
            // what Restore… will offer (issue #46).
            if plan.lastRun?.skippedUnchanged == true {
                unchangedLine
            } else {
                RelativeTimeText(kind: .backedUp, date: date)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(nextRunText)
            }
        case .idle:
            if let lastRun = plan.lastRun {
                if lastRun.success {
                    if lastRun.skippedUnchanged == true {
                        unchangedLine
                    } else {
                        RelativeTimeText(kind: .lastBackup, date: lastRun.date)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .help(nextRunText)
                    }
                } else {
                    Text(lastRun.errorMessage ?? String(localized: "Last backup failed"))
                        .font(.callout)
                        .foregroundStyle(.red)
                        .help(lastRun.errorMessage ?? String(localized: "Last backup failed"))
                }
            } else {
                Text("Not backed up yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(nextRunText)
            }
        }
    }
}

/// "Backed up 5 seconds ago" that keeps counting up on its own (SwiftUI's
/// `.relative` text style live-updates), switching to an absolute date once
/// the moment is more than a day old — exactly the progression issue #19
/// asked for. Whole-sentence keys (not concatenation) so translations can
/// reorder the time fragment freely.
struct RelativeTimeText: View {
    enum Kind {
        case backedUp
        case lastBackup
    }

    let kind: Kind
    let date: Date

    var body: some View {
        if Date().timeIntervalSince(date) < 24 * 60 * 60 {
            switch kind {
            case .backedUp:
                Text("Backed up \(Text(date, style: .relative)) ago")
            case .lastBackup:
                Text("Last backup \(Text(date, style: .relative)) ago")
            }
        } else {
            switch kind {
            case .backedUp:
                Text("Backed up on \(date.formatted(date: .abbreviated, time: .shortened))")
            case .lastBackup:
                Text("Last backup on \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }
}
