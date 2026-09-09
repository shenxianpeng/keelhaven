import AppKit

/// A menu-bar-only app gives zero visible feedback when double-clicked while
/// already running. The delegate can't see AppState or open SwiftUI windows,
/// so it forwards the event; MenuBarLabelView decides what to show.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ _: Notification) {
        // About and Welcome read NSApp.applicationIconImage, which resolves
        // through the system icon cache — and this bundle shipped many builds
        // *without* an icon, so the cache serves the generic one even though
        // Assets.car now has the real icon (issue #36). Loading it from our
        // own asset catalog sidesteps the cache entirely.
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldHandleReopen(
        _ _: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        NotificationCenter.default.post(name: .keelhavenReopen, object: nil)
        return false
    }
}
