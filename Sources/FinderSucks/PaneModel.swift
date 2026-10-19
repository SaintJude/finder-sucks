import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PaneModel {
    private(set) var url: URL
    /// Everything in the folder, before hidden-file filtering and sorting.
    private(set) var allItems: [FileItem] = [] { didSet { rebuild() } }
    /// What the table shows.
    private(set) var items: [FileItem] = []
    var selection: Set<URL> = []

    var sortOrder: [KeyPathComparator<FileItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)] {
        didSet { rebuild() }
    }
    var showHidden = false { didSet { rebuild() } }
    var foldersFirst = true { didSet { rebuild() } }
    var filter = "" { didSet { rebuild() } }
    var computeFolderSizes = true {
        didSet { computeFolderSizes ? startSizing() : stopSizing() }
    }

    var isEditingPath = false
    /// Bumped to ask the status bar to focus its filter field.
    var filterFocusRequest = 0
    /// Row the table should scroll to.
    var scrollTarget: URL?

    private(set) var loadError: String?
    private(set) var isSizing = false
    private(set) var freeSpace: Int64?
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    @ObservationIgnored private let sizeCache: FolderSizeCache
    @ObservationIgnored private let watcher = DirectoryWatcher()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadDebounce: Task<Void, Never>?
    @ObservationIgnored private var pendingSelection: URL?
    @ObservationIgnored private var lastOpen: (urls: Set<URL>, at: Date)?

    init(url: URL, sizeCache: FolderSizeCache) {
        self.url = url.standardizedFileURL
        self.sizeCache = sizeCache
        startWatching()
        load()
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { url.path != "/" }

    var selectedItems: [FileItem] { items.filter { selection.contains($0.url) } }
    var selectedURLs: [URL] { selectedItems.map(\.url) }

    // MARK: Navigation

    func go(to newURL: URL) {
        let target = newURL.standardizedFileURL
        guard !target.isSamePath(as: url) else { return }
        backStack.append(url)
        forwardStack.removeAll()
        setURL(target)
    }

    /// Turns pasted text into an existing file URL. Handles `~`, quotes, `file://` URLs,
    /// shell-escaped spaces (`My\ Folder`), and paths relative to this pane's folder.
    func resolve(path raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" {
            text = String(text.dropFirst().dropLast())
        }
        guard !text.isEmpty else { return nil }

        var candidates: [String] = []
        if text.hasPrefix("file://"), let url = URL(string: text), url.isFileURL {
            candidates.append(url.path)
        }
        let unescaped = text.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
        for variant in [text, unescaped] {
            let expanded = (variant as NSString).expandingTildeInPath
            candidates.append(expanded.hasPrefix("/") ? expanded : url.appendingPathComponent(expanded).path)
        }
        return candidates
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Navigates to a typed or pasted path; a file path selects the file in its folder.
    /// Returns false if the path doesn't exist.
    @discardableResult
    func go(toPath raw: String) -> Bool {
        guard let target = resolve(path: raw) else {
            NSSound.beep()
            return false
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir)
        isEditingPath = false
        let isPackage = (try? target.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        if isDir.boolValue && !isPackage {
            go(to: target)
        } else {
            pendingSelection = target
            go(to: target.deletingLastPathComponent())
            if target.deletingLastPathComponent().isSamePath(as: url) { load() }
        }
        return true
    }

    func goUp() {
        guard canGoUp else { return }
        pendingSelection = url
        go(to: url.deletingLastPathComponent())
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(url)
        pendingSelection = url
        setURL(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(url)
        setURL(next)
    }

    /// Double-click / Return: enter a single folder, otherwise open files with their default app.
    func open(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        // Double-click and Return can both fire for one gesture; ignore the echo.
        if let last = lastOpen, last.urls == urls, Date().timeIntervalSince(last.at) < 0.4 { return }
        lastOpen = (urls, Date())

        let chosen = allItems.filter { urls.contains($0.url) }
        if chosen.count == 1, chosen[0].isFolder {
            go(to: chosen[0].url)
        } else {
            for item in chosen where !item.isFolder {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    private func setURL(_ newURL: URL) {
        url = newURL
        selection = []
        filter = ""
        isEditingPath = false
        allItems = []
        startWatching()
        load()
    }

    // MARK: Loading

    /// Reloads the folder, then selects `url` if given.
    func reload(selecting url: URL? = nil) {
        if let url { pendingSelection = url }
        load()
    }

    /// Reload and re-measure every subfolder.
    func refresh() {
        sizeCache.invalidateChildren(of: url)
        load()
    }

    func load() {
        loadTask?.cancel()
        let directory = url
        loadTask = Task {
            // Off the main thread: listing a protected folder can wait on a privacy prompt.
            let (result, free) = await Task.detached(priority: .userInitiated) {
                let result = Result { try FileLister.list(directory) }
                let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
                return (result, free)
            }.value
            guard !Task.isCancelled, directory == self.url else { return }

            switch result {
            case .success(var list):
                for i in list.indices where list[i].isDirectory {
                    list[i].size = sizeCache.sizes[list[i].url.standardizedFileURL.path]
                }
                loadError = nil
                allItems = list
                if let pending = pendingSelection,
                   let match = list.first(where: { $0.url.isSamePath(as: pending) }) {
                    selection = [match.url]
                    scrollTarget = match.url
                }
            case .failure(let error):
                allItems = []
                loadError = error.localizedDescription
            }
            pendingSelection = nil
            freeSpace = free
            startSizing()
        }
    }

    private func startWatching() {
        watcher.watch(url) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    /// Coalesces bursts of file system events (e.g. during a big copy).
    private func scheduleReload() {
        reloadDebounce?.cancel()
        reloadDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            load()
        }
    }

    // MARK: Folder sizes

    private func startSizing() {
        sizeTask?.cancel()
        guard computeFolderSizes else { return }
        let pending = allItems.filter { $0.isDirectory && !$0.isSymlink && $0.size == nil }.map(\.url)
        guard !pending.isEmpty else {
            isSizing = false
            return
        }
        isSizing = true
        sizeTask = Task {
            for folder in pending {
                guard let size = await FolderSizer.sizeInBackground(of: folder), !Task.isCancelled else { return }
                sizeCache.sizes[folder.standardizedFileURL.path] = size
                if let index = allItems.firstIndex(where: { $0.url == folder }) {
                    allItems[index].size = size
                }
            }
            isSizing = false
        }
    }

    private func stopSizing() {
        sizeTask?.cancel()
        isSizing = false
    }

    // MARK: Derived state

    private func rebuild() {
        var visible = showHidden ? allItems : allItems.filter { !$0.isHidden }
        let query = filter.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            visible = visible.filter { $0.name.localizedStandardContains(query) }
        }
        visible.sort(using: sortOrder)
        if foldersFirst {
            visible = visible.filter(\.isFolder) + visible.filter { !$0.isFolder }
        }
        items = visible

        let visibleIDs = Set(visible.map(\.url))
        if !selection.isSubset(of: visibleIDs) {
            selection.formIntersection(visibleIDs)
        }
    }

    var summary: String {
        var parts: [String] = []
        let selected = selectedItems
        if selected.isEmpty {
            parts.append(items.count == 1 ? "1 item" : "\(items.count) items")
        } else {
            let total = selected.compactMap(\.size).reduce(0, +)
            let unsized = selected.contains { $0.size == nil }
            parts.append("\(selected.count) of \(items.count) selected, \(Fmt.bytes(total))\(unsized ? "+" : "")")
        }
        if let freeSpace { parts.append("\(Fmt.bytes(freeSpace)) available") }
        return parts.joined(separator: " · ")
    }

    // MARK: Type-to-select

    @ObservationIgnored private var typeBuffer = ""
    @ObservationIgnored private var lastTypeAt = Date.distantPast

    func typeSelect(_ characters: String) {
        let now = Date()
        typeBuffer = now.timeIntervalSince(lastTypeAt) > 1 ? characters : typeBuffer + characters
        lastTypeAt = now
        let prefix = typeBuffer.lowercased()
        if let match = items.first(where: { $0.name.lowercased().hasPrefix(prefix) }) {
            selection = [match.url]
            scrollTarget = match.url
        }
    }
}
