import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Side: Hashable { case left, right }

    struct NamePrompt {
        enum Kind {
            case rename(URL)
            case newFolder(in: URL)
        }

        let kind: Kind
        let pane: PaneModel

        var title: String {
            switch kind {
            case .rename(let url): "Rename “\(url.lastPathComponent)”"
            case .newFolder: "New Folder"
            }
        }
    }

    let left: PaneModel
    let right: PaneModel
    var activeSide: Side = .left
    var showInspector = false

    var pendingTransfer: Transfer?
    var namePrompt: NamePrompt?
    var isPromptShown = false
    var promptText = ""
    var errorMessage: String?
    var busyMessage: String?

    /// Text in the toolbar's Go/search box.
    var goText = ""
    /// Bumped to ask the toolbar box to take focus.
    var goBoxFocusRequest = 0

    @ObservationIgnored private let sizeCache: FolderSizeCache

    init(startURL: URL? = nil) {
        let cache = FolderSizeCache.shared
        let home = FileManager.default.homeDirectoryForCurrentUser
        sizeCache = cache
        left = PaneModel(url: startURL ?? home, sizeCache: cache)
        right = PaneModel(url: home.appendingPathComponent("Downloads"), sizeCache: cache)
    }

    var active: PaneModel { pane(activeSide) }
    var inactive: PaneModel { pane(activeSide == .left ? .right : .left) }

    func pane(_ side: Side) -> PaneModel { side == .left ? left : right }

    func switchPane() { activeSide = activeSide == .left ? .right : .left }

    func showSameFolderInOtherPane() { inactive.go(to: active.url) }

    func swapPanes() {
        let leftURL = left.url
        left.go(to: right.url)
        right.go(to: leftURL)
    }

    // MARK: Go / search box

    /// Whether the box's text should be treated as a path rather than a search.
    static func looksLikePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("file://")
            || trimmed.hasPrefix(".") || trimmed.contains("/")
    }

    /// As the user types a non-path, filter the active pane live.
    func goTextChanged() {
        if !Self.looksLikePath(goText) {
            active.filter = goText.trimmingCharacters(in: .whitespaces)
        } else if !active.filter.isEmpty {
            active.filter = ""
        }
    }

    /// Return in the box: go to the path if it exists; otherwise keep it as a search.
    /// Returns true if it navigated.
    func submitGoBox() -> Bool {
        let text = goText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if active.resolve(path: text) != nil {
            active.go(toPath: text)
            goText = ""
            active.filter = ""
            return true
        }
        if Self.looksLikePath(text) {
            errorMessage = "Couldn't find “\(text)”."
        }
        return false
    }

    func clearGoBox() {
        goText = ""
        active.filter = ""
    }

    /// True while the user is typing in a text field, so destructive shortcuts like ⌘⌫ don't fire.
    var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSTextView }

    // MARK: Copy / move

    func requestTransfer(_ op: Transfer.Op, urls: [URL]? = nil, from side: Side? = nil) {
        let source = pane(side ?? activeSide)
        let destination = source === left ? right : left
        let sources = urls ?? source.selectedURLs
        guard !sources.isEmpty else { return NSSound.beep() }
        guard !destination.url.isSamePath(as: source.url) else {
            errorMessage = "Both panes are showing the same folder."
            return
        }
        pendingTransfer = Transfer(op: op, sources: sources, destination: destination.url)
    }

    func perform(_ transfer: Transfer) {
        busyMessage = transfer.op == .copy ? "Copying…" : "Moving…"
        Task {
            let errors = await Task.detached(priority: .userInitiated) { FileOps.perform(transfer) }.value
            busyMessage = nil
            sizeCache.invalidate(around: transfer.sources + [transfer.destination])
            left.reload()
            right.reload()
            if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
        }
    }

    // MARK: Other file operations

    func trash(_ urls: [URL]? = nil, side: Side? = nil) {
        let pane = pane(side ?? activeSide)
        let targets = urls ?? pane.selectedURLs
        guard !targets.isEmpty else { return NSSound.beep() }
        var errors: [String] = []
        for url in targets {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        sizeCache.invalidate(around: targets)
        left.reload()
        right.reload()
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
    }

    func promptRename(_ url: URL? = nil, side: Side? = nil) {
        let pane = pane(side ?? activeSide)
        guard let target = url ?? (pane.selectedURLs.count == 1 ? pane.selectedURLs.first : nil) else {
            return NSSound.beep()
        }
        promptText = target.lastPathComponent
        namePrompt = NamePrompt(kind: .rename(target), pane: pane)
        isPromptShown = true
    }

    func promptNewFolder(side: Side? = nil) {
        let pane = pane(side ?? activeSide)
        promptText = "untitled folder"
        namePrompt = NamePrompt(kind: .newFolder(in: pane.url), pane: pane)
        isPromptShown = true
    }

    func commitPrompt() {
        guard let prompt = namePrompt else { return }
        namePrompt = nil
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") || name.count > 1 else {
            errorMessage = "“\(name)” isn't a valid name."
            return
        }
        do {
            switch prompt.kind {
            case .rename(let url):
                let destination = url.deletingLastPathComponent().appendingPathComponent(name)
                guard destination.lastPathComponent != url.lastPathComponent else { return }
                try FileManager.default.moveItem(at: url, to: destination)
                prompt.pane.reload(selecting: destination)
            case .newFolder(let directory):
                let destination = directory.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                prompt.pane.reload(selecting: destination)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Info & integration

    func copyPaths(_ urls: [URL]? = nil, side: Side? = nil) {
        let pane = pane(side ?? activeSide)
        let targets = urls ?? (pane.selectedURLs.isEmpty ? [pane.url] : pane.selectedURLs)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(targets.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func revealInFinder(_ urls: [URL]? = nil, side: Side? = nil) {
        let pane = pane(side ?? activeSide)
        let targets = urls ?? (pane.selectedURLs.isEmpty ? [pane.url] : pane.selectedURLs)
        NSWorkspace.shared.activateFileViewerSelecting(targets)
    }

    func openInTerminal(_ url: URL? = nil, side: Side? = nil) {
        let pane = pane(side ?? activeSide)
        var folder = url ?? pane.url
        if url == nil, let only = pane.selectedItems.first, pane.selectedItems.count == 1, only.isFolder {
            folder = only.url
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
