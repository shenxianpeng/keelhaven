import SwiftUI
import KeelhavenCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var startAtLogin = LoginItemService.isEnabled
    @State private var plansHeight: CGFloat = 0

    /// About four plan rows; the fifth peeks out to hint at scrollability,
    /// and the fixed header/footer keep the panel well under even a small
    /// screen's visible height.
    private static let plansMaxHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keelhaven")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    openWindow(id: WindowID.about)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("About Keelhaven")
                .accessibilityLabel("About Keelhaven")
            }

            if let startupError = appState.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if appState.resticBinaryURL == nil {
                // Deliberately the same sentence the failure path throws, read
                // straight off the error rather than restated here: the two
                // drifted apart once already, and this copy is the one users
                // meet first — it sits at the top of the panel on launch,
                // while the other only appears once something is attempted.
                Label(
                    ResticError.binaryNotFound.localizedDescription,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            // Only shown when something is actually wrong — a healthy panel
            // stays quiet rather than announcing "all good" every time
            // (issue #65: an always-on summary line fit that app's dashboard,
            // not this one's "quiet until needed" menu bar).
            if attentionCount > 0 {
                Label(attentionSummaryText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let update = appState.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.dmgURL)
                } label: {
                    Label(String(localized: "New version \(update.version) available"), systemImage: "arrow.down.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if appState.plans.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing is backed up yet.")
                        .foregroundStyle(.secondary)
                    Button {
                        openWizard()
                    } label: {
                        Label("Set Up a Backup", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.resticBinaryURL == nil)
                }
            } else {
                // The .window-style MenuBarExtra panel sizes itself to its
                // content with no screen clamp, so an unbounded plan list
                // pushes Add/Login/Quit below the screen edge. Cap the list
                // at ~4 rows and scroll inside it; the measured height keeps
                // short lists hugging their content instead of reserving the
                // full cap.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.plans) { plan in
                            PlanStatusRow(plan: plan)
                        }
                    }
                    .background(ScrollerSuppressor())
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        plansHeight = height
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: min(plansHeight, Self.plansMaxHeight))
            }

            Divider()

            Button {
                openWizard()
            } label: {
                Label("Add Backup Plan…", systemImage: "plus")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appState.resticBinaryURL == nil)

            Divider()

            // App-level controls share the last section, like a system menu:
            // the toggle and Quit belong together, actions live above.
            HStack {
                Text("Start at Login")
                Spacer()
                Toggle("Start at Login", isOn: $startAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.green)
                    .onChange(of: startAtLogin) { _, newValue in
                        do {
                            try LoginItemService.setEnabled(newValue)
                        } catch {
                            startAtLogin = LoginItemService.isEnabled
                        }
                    }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit Keelhaven")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var attentionCount: Int {
        appState.plans.filter { plan in
            plan.health(runState: appState.runStates[plan.id] ?? .idle) == .needsAttention
        }.count
    }

    private var attentionSummaryText: String {
        attentionCount == 1
            ? String(localized: "1 backup needs attention")
            : String(localized: "\(attentionCount) backups need attention")
    }

    private func openWizard() {
        openWindow(id: WindowID.wizard)
        // LSUIElement apps don't come forward on their own.
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// `.scrollIndicators(.hidden)` above stops SwiftUI's own indicator, but
/// macOS still flashes the underlying NSScrollView's system scroller on an
/// active scroll gesture in this MenuBarExtra popover — and it can get
/// stuck visible instead of fading (#71 follow-up). Reaching into the real
/// NSScrollView and disabling its scroller is the only fix that sticks.
private struct ScrollerSuppressor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let probe = NSView(frame: .zero)
        DispatchQueue.main.async {
            var view: NSView? = probe
            while let current = view, !(current is NSScrollView) {
                view = current.superview
            }
            (view as? NSScrollView)?.hasVerticalScroller = false
        }
        return probe
    }

    func updateNSView(_ _: NSView, context _: Context) {
        // Nothing to update: the suppressor disables the scroller once, at
        // creation, and SwiftUI has no state to sync back afterwards.
    }
}
