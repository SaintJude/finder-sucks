import SwiftUI

/// Shows details for the active pane's selection, or the current folder if nothing is selected.
struct InspectorView: View {
    let pane: PaneModel

    var body: some View {
        let selected = pane.selectedItems
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if selected.count > 1 {
                    MultiSelectionInfo(items: selected)
                } else {
                    ItemInfo(url: selected.first?.url ?? pane.url, knownSize: selected.first?.size)
                        .id(selected.first?.url ?? pane.url)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MultiSelectionInfo: View {
    let items: [FileItem]

    var body: some View {
        let total = items.compactMap(\.size).reduce(0, +)
        let pending = items.contains { $0.size == nil }
        Text("\(items.count) items").font(.title3.bold())
        InfoRow("Total size", Fmt.bytes(total) + (pending ? " (still calculating)" : ""))
        InfoRow("Folders", "\(items.filter(\.isFolder).count)")
        InfoRow("Files", "\(items.filter { !$0.isFolder }.count)")
    }
}

private struct ItemInfo: View {
    let url: URL
    let knownSize: Int64?
    @State private var computedSize: Int64?

    var body: some View {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .localizedTypeDescriptionKey, .creationDateKey, .contentModificationDateKey,
            .contentAccessDateKey, .fileSizeKey, .isSymbolicLinkKey,
        ])
        let isDirectory = values?.isDirectory ?? false
        let size = knownSize ?? computedSize ?? (isDirectory ? nil : values?.fileSize.map(Int64.init))

        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .frame(width: 64, height: 64)
            Text(url.lastPathComponent.isEmpty ? url.displayName : url.lastPathComponent)
                .font(.title3.bold())
                .textSelection(.enabled)
        }

        InfoRow("Kind", values?.localizedTypeDescription ?? "—")
        InfoRow("Size", size.map { "\(Fmt.bytes($0))  (\($0.formatted()) bytes)" } ?? "Calculating…")

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Path").foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                .controlSize(.small)
            }
            Text(url.path)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }

        if values?.isSymbolicLink == true,
           let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            InfoRow("Links to", target, monospaced: true)
        }

        Divider()
        InfoRow("Created", Fmt.date(values?.creationDate))
        InfoRow("Modified", Fmt.date(values?.contentModificationDate))
        InfoRow("Last opened", Fmt.date(values?.contentAccessDate))
        Divider()
        InfoRow("Owner", "\(attributes[.ownerAccountName] as? String ?? "?"):\(attributes[.groupOwnerAccountName] as? String ?? "?")")
        if let mode = attributes[.posixPermissions] as? Int {
            InfoRow("Permissions", Fmt.permissions(mode), monospaced: true)
        }

        Color.clear.frame(height: 0)
            .task(id: url) {
                guard isDirectory, knownSize == nil else { return }
                computedSize = await FolderSizer.sizeInBackground(of: url)
            }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    init(_ label: String, _ value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}
