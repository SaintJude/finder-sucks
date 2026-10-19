import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (e.g. `swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// What a new window opens to. The UUID makes every request distinct, since SwiftUI
/// would otherwise bring an existing window with the same value to the front.
struct WindowSeed: Codable, Hashable {
    var id = UUID()
    var url: URL
}

extension FocusedValues {
    /// The state of the frontmost window, so menu commands act on it.
    @Entry var appState: AppState?
}

@main
struct FinderSucksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Finder Sucks", id: BrowserWindow.id, for: WindowSeed.self) { $seed in
            BrowserWindow(startURL: seed?.url)
        }
        .defaultSize(width: 1300, height: 800)
        .commands { AppCommands() }
    }
}

/// One independent browser window with its own pair of panes.
struct BrowserWindow: View {
    static let id = "browser"

    let startURL: URL?
    @State private var state: AppState?

    var body: some View {
        Group {
            if let state {
                ContentView()
                    .environment(state)
                    .focusedSceneValue(\.appState, state)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if state == nil { state = AppState(startURL: startURL) }
        }
    }
}
