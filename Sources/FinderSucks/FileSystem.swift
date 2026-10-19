import AppKit
import Foundation

enum FileLister {
    static func list(_ directory: URL) throws -> [FileItem] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: FileItem.resourceKeys, options: [])
            .map(FileItem.init(url:))
    }
}

enum FolderSizer {
    /// Recursively sums logical file sizes. Returns nil if the calling task is cancelled.
    static func size(of url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return nil }

        var total: Int64 = 0
        var count = 0
        while let next = enumerator.nextObject() {
            count += 1
            if count % 500 == 0, Task.isCancelled { return nil }
            guard let fileURL = next as? URL,
                  let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Sizes a folder off the main thread; cancelling the caller stops the walk.
    static func sizeInBackground(of url: URL) async -> Int64? {
        let task = Task.detached(priority: .utility) { size(of: url) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}

/// Folder sizes keyed by path, shared by every pane in every window so revisiting a folder is instant.
@MainActor
final class FolderSizeCache {
    static let shared = FolderSizeCache()

    var sizes: [String: Int64] = [:]

    /// Drops cached sizes for these paths and every folder that contains them.
    func invalidate(around urls: [URL]) {
        let paths = urls.map { $0.standardizedFileURL.path }
        sizes = sizes.filter { key, _ in
            !paths.contains { $0 == key || $0.hasPrefix(key + "/") }
        }
    }

    func invalidateChildren(of directory: URL) {
        let prefix = directory.standardizedFileURL.path + "/"
        sizes = sizes.filter { key, _ in !key.hasPrefix(prefix) }
    }
}

struct Transfer: Identifiable, Sendable {
    enum Op: Sendable { case copy, move }

    let id = UUID()
    let op: Op
    let sources: [URL]
    let destination: URL

    var verb: String { op == .copy ? "Copy" : "Move" }

    var title: String {
        let what = sources.count == 1 ? "“\(sources[0].lastPathComponent)”" : "\(sources.count) items"
        return "\(verb) \(what) to “\(destination.displayName)”?"
    }
}

enum FileOps {
    /// Performs a copy/move, returning a human-readable message for each failure.
    static func perform(_ transfer: Transfer) -> [String] {
        let fm = FileManager.default
        var errors: [String] = []
        let destPath = transfer.destination.standardizedFileURL.path

        for source in transfer.sources {
            let name = source.lastPathComponent
            let target = transfer.destination.appendingPathComponent(name)
            let sourcePath = source.standardizedFileURL.path

            if destPath == sourcePath || destPath.hasPrefix(sourcePath + "/") {
                errors.append("“\(name)” can't be put inside itself.")
                continue
            }
            if target.isSamePath(as: source) {
                errors.append("“\(name)” is already in that folder.")
                continue
            }
            if fm.fileExists(atPath: target.path) {
                errors.append("“\(name)” already exists in “\(transfer.destination.displayName)”.")
                continue
            }
            do {
                switch transfer.op {
                case .copy: try fm.copyItem(at: source, to: target)
                case .move: try fm.moveItem(at: source, to: target)
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return errors
    }
}

/// Calls back on the main queue whenever a directory's contents change.
/// Must be used from the main thread.
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    /// Bumped on every watch/stop so a slow `open` for an old folder is discarded.
    private var generation = 0

    func watch(_ url: URL, onChange: @escaping () -> Void) {
        stop()
        let expected = generation
        // `open` blocks until the user answers a privacy prompt for folders like
        // Downloads or Documents, so it must stay off the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == expected else {
                    close(fd)
                    return
                }
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main
                )
                source.setEventHandler(handler: onChange)
                source.setCancelHandler { close(fd) }
                source.resume()
                self.source = source
            }
        }
    }

    func stop() {
        generation += 1
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}

@MainActor
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

enum Fmt {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    static func permissions(_ mode: Int) -> String {
        let chars = Array("rwxrwxrwx")
        let bits = (0..<9).map { i in mode & (1 << (8 - i)) != 0 ? chars[i] : "-" }
        return String(bits) + String(format: "  (%o)", mode & 0o777)
    }
}
