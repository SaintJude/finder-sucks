import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymlink: Bool
    /// Logical size. For directories this is nil until the folder has been sized.
    var size: Int64?
    let modified: Date?
    let kind: String

    var id: URL { url }
    /// A directory you navigate into (packages like .app open instead).
    var isFolder: Bool { isDirectory && !isPackage }
    var sortSize: Int64 { size ?? -1 }
    var sortDate: Date { modified ?? .distantPast }

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        self.url = url
        name = url.lastPathComponent
        isSymlink = values?.isSymbolicLink ?? false
        isHidden = values?.isHidden ?? name.hasPrefix(".")
        modified = values?.contentModificationDate
        kind = values?.localizedTypeDescription ?? ""

        var isDir = values?.isDirectory ?? false
        var isPkg = values?.isPackage ?? false
        if isSymlink,
           let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            isDir = target.isDirectory ?? false
            isPkg = target.isPackage ?? false
        }
        isDirectory = isDir
        isPackage = isPkg
        size = isDir ? nil : Int64(values?.fileSize ?? 0)
    }
}

extension URL {
    /// Every folder from the volume root down to (and including) this URL.
    var ancestors: [URL] {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        var result = [current]
        for component in standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            result.append(current)
        }
        return result
    }

    var displayName: String { FileManager.default.displayName(atPath: path) }

    func isSamePath(as other: URL) -> Bool {
        standardizedFileURL.path == other.standardizedFileURL.path
    }
}
