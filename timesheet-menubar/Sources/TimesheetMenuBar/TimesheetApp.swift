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

/// The menu bar item: clock icon plus the current period's total hours.
private struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: state.menuBarSymbol)
            if let text = state.menuBarText {
                Text(text)
            }
        }
    }
}

/// Keeps the app out of the Dock and app switcher — it lives only in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
