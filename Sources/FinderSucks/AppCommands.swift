import AppKit
import SwiftUI

struct AppCommands: Commands {
    /// The frontmost window's state; nil when no browser window is key.
    @FocusedValue(\.appState) private var state
    @Environment(\.openWindow) private var openWindow

    private func functionKey(_ code: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(code)!))
    }

    /// A menu item that acts on the frontmost window. With `whenNotTyping`, it does nothing while
    /// a text field has focus, so shortcuts like ⌘⌫ and ⌘↑ keep their text-editing meaning.
    private func item(
        _ title: String, whenNotTyping: Bool = false, action: @escaping (AppState) -> Void
    ) -> some View {
        Button(title) {
            guard let state, !(whenNotTyping && state.isEditingText) else { return }
            action(state)
        }
        .disabled(state == nil)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                let url = state?.active.url ?? FileManager.default.homeDirectoryForCurrentUser
                openWindow(id: BrowserWindow.id, value: WindowSeed(url: url))
            }
            .keyboardShortcut("n")
            item("New Folder") { $0.promptNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            item("Open") { $0.active.open($0.active.selection) }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            item("Copy Path") { $0.copyPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            item("Copy to Other Pane") { $0.requestTransfer(.copy) }
                .keyboardShortcut(functionKey(NSF5FunctionKey), modifiers: [])
            item("Move to Other Pane") { $0.requestTransfer(.move) }
                .keyboardShortcut(functionKey(NSF6FunctionKey), modifiers: [])
            item("Rename…") { $0.promptRename() }
                .keyboardShortcut(functionKey(NSF2FunctionKey), modifiers: [])
            item("Move to Trash", whenNotTyping: true) { $0.trash() }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            item("Reveal in Finder") { $0.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            item("Open in Terminal") { $0.openInTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }

        CommandGroup(after: .sidebar) {
            item("Show/Hide Hidden Files") { $0.active.showHidden.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            item("Calculate Folder Sizes On/Off") { $0.active.computeFolderSizes.toggle() }
            item("Folders First On/Off") { $0.active.foldersFirst.toggle() }
            item("Show/Hide Inspector") { $0.showInspector.toggle() }
                .keyboardShortcut("i")
            item("Filter") { $0.active.filterFocusRequest += 1 }
                .keyboardShortcut("f")
            item("Refresh") { $0.active.refresh() }
                .keyboardShortcut("r")
            Divider()
        }

        CommandMenu("Go") {
            item("Back") { $0.active.goBack() }
                .keyboardShortcut("[")
            item("Forward") { $0.active.goForward() }
                .keyboardShortcut("]")
            item("Enclosing Folder", whenNotTyping: true) { $0.active.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            item("Open Selection", whenNotTyping: true) { $0.active.open($0.active.selection) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            item("Go to Path…") { $0.goBoxFocusRequest += 1 }
                .keyboardShortcut("l")
            item("Go to Folder…") { $0.goBoxFocusRequest += 1 }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            item("Edit Pane Path") { $0.active.isEditingPath = true }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            goButton("Home", FileManager.default.homeDirectoryForCurrentUser, key: "h")
            goButton("Desktop", home("Desktop"), key: "d")
            goButton("Downloads", home("Downloads"), key: "l", modifiers: [.command, .option])
            goButton("Documents", home("Documents"), key: "o")
            goButton("Applications", URL(fileURLWithPath: "/Applications"), key: "a")
            Divider()
            item("Switch Pane") { $0.switchPane() }
                .keyboardShortcut(.tab, modifiers: .control)
            item("Same Folder in Other Pane") { $0.showSameFolderInOtherPane() }
                .keyboardShortcut("=", modifiers: [.command, .option])
            item("Swap Panes") { $0.swapPanes() }
                .keyboardShortcut("u")
        }
    }

    private func home(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
    }

    private func goButton(
        _ title: String, _ url: URL, key: KeyEquivalent, modifiers: EventModifiers = [.command, .shift]
    ) -> some View {
        item(title) { $0.active.go(to: url) }
            .keyboardShortcut(key, modifiers: modifiers)
    }
}
