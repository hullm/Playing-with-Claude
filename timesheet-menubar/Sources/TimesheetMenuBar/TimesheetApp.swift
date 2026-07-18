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
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window) // rich SwiftUI content rather than a plain menu
    }
}

/// The menu bar item: just the clock icon (swaps to a nudge when a draft is
/// ready to submit).
private struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    var body: some View {
        Image(systemName: state.menuBarSymbol)
    }
}

/// Keeps the app out of the Dock and app switcher — it lives only in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
