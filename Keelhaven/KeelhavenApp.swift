import SwiftUI
import KeelhavenCore

enum WindowID {
    static let wizard = "wizard"
    static let duplicatePlan = "duplicatePlan"
    static let about = "about"
    static let restore = "restore"
    static let welcome = "welcome"
    static let editPlan = "editPlan"
}

@main
struct KeelhavenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabelView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Keelhaven", id: WindowID.welcome) {
            WelcomeWindowView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("New Backup Plan", id: WindowID.wizard) {
            WizardWindowView()
                .environment(appState)
        }
        .windowResizability(.contentSize)

        // The same wizard, prefilled from an existing plan: duplicating is
        // "same plan, new destination", and the destination step already
        // owns every destination form, its conflict rules and the adopt flow
        // (issue #62). Seeded from `appState.duplicatePlanID`.
        Window("Duplicate Backup Plan", id: WindowID.duplicatePlan) {
            WizardWindowView(isDuplicate: true)
                .environment(appState)
        }
        .windowResizability(.contentSize)

        Window("Restore Backup", id: WindowID.restore) {
            RestoreWindowView()
                .environment(appState)
        }
        .windowResizability(.contentSize)

        // The only window the user can resize: its sections expand, and
        // `.contentSize` used to pin it to whatever height the expanded
        // content demanded — off the bottom of the screen, unshrinkable
        // and unscrollable (issue #39). `.contentMinSize` keeps the floor
        // the content asks for and hands the rest to the user.
        Window("Edit Backup Plan", id: WindowID.editPlan) {
            EditPlanWindowView()
                .environment(appState)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 640)

        Window("About Keelhaven", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
