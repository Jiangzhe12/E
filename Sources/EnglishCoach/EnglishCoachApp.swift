import AppKit
import SwiftUI

@main
struct EnglishCoachApp: App {
    @StateObject private var model = AppModel()
    private let iconManager = AppIconManager()

    var body: some Scene {
        WindowGroup("English Coach") {
            ContentView(model: model)
                .onAppear {
                    model.refreshDailyCompletionState()
                    iconManager.applyLearningState(
                        completedToday: model.hasCompletedLearningToday,
                        animateTransition: false
                    )
                }
                .onChange(of: model.hasCompletedLearningToday) { oldValue, newValue in
                    iconManager.applyLearningState(
                        completedToday: newValue,
                        animateTransition: !oldValue && newValue
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshDailyCompletionState()
                    model.refreshPermissionStatus()
                    iconManager.applyLearningState(
                        completedToday: model.hasCompletedLearningToday,
                        animateTransition: false
                    )
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("English Coach", systemImage: "character.book.closed") {
            MenubarPopoverView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
