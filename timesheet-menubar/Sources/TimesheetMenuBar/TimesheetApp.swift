import SwiftUI
import AppKit

@main
struct TimesheetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(state)
                .frame(width: 340)
        } label: {
            // SF Symbol shown in the menu bar. Falls back gracefully if the
            // symbol is unavailable on very old systems.
            Image(systemName: "clock.badge.checkmark")
        }
        .menuBarExtraStyle(.window) // rich SwiftUI content rather than a plain menu
    }
}

/// Keeps the app out of the Dock and app switcher — it lives only in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
