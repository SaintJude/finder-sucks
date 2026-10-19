import SwiftUI

struct PaneView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Bindable var pane: PaneModel
    let side: AppState.Side
    var focusedSide: FocusState<AppState.Side?>.Binding

    private var isActive: Bool { state.activeSide == side }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(pane: pane, isActive: isActive)
            Divider()
            if let error = pane.loadError {
                ContentUnavailableView(
                    "Can't Open Folder", systemImage: "exclamationmark.triangle", description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
            Divider()
            StatusBar(pane: pane)
        }
        .frame(minWidth: 340)
    }

    private var table: some View {
        ScrollViewReader { proxy in
            Table(pane.items, selection: $pane.selection, sortOrder: $pane.sortOrder) {
                TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                    NameCell(item: item)
                }
                .width(min: 150, ideal: 280)

                TableColumn("Size", value: \.sortSize) { item in
                    SizeCell(item: item, sizingEnabled: pane.computeFolderSizes)
                }
                .width(min: 60, ideal: 80, max: 120)

                TableColumn("Kind", value: \.kind) { item in
                    Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 60, ideal: 110)

                TableColumn("Date Modified", value: \.sortDate) { item in
                    Text(Fmt.date(item.modified)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 100, ideal: 150)
            }
            .focused(focusedSide, equals: side)
            .contextMenu(forSelectionType: URL.self) { selection in
                contextMenu(for: selection)
            } primaryAction: { selection in
                pane.open(selection)
            }
            .onKeyPress(.return) {
                pane.open(pane.selection)
                return .handled
            }
            .onKeyPress(.delete) {
                pane.goUp()
                return .handled
            }
            .onKeyPress(.tab) {
                state.switchPane()
                return .handled
            }
            .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters), phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                pane.typeSelect(press.characters)
                return .handled
            }
            .onChange(of: pane.scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target)
                pane.scrollTarget = nil
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for selection: Set<URL>) -> some View {
        let urls = pane.items.map(\.url).filter(selection.contains)
        if urls.isEmpty {
            Button("New Folder") { state.promptNewFolder(side: side) }
            Divider()
            Button("Copy Path of This Folder") { state.copyPaths([pane.url]) }
            Button("Open in Terminal") { state.openInTerminal(pane.url) }
            Button("Reveal in Finder") { state.revealInFinder([pane.url]) }
        } else {
            Button("Open") { pane.open(selection) }
            if urls.count == 1, pane.items.first(where: { $0.url == urls[0] })?.isFolder == true {
                Button("Open in New Window") {
                    openWindow(id: BrowserWindow.id, value: WindowSeed(url: urls[0]))
                }
            }
            Divider()
            Button("Copy to Other Pane") { state.requestTransfer(.copy, urls: urls, from: side) }
            Button("Move to Other Pane") { state.requestTransfer(.move, urls: urls, from: side) }
            if urls.count == 1 {
                Button("Rename…") { state.promptRename(urls[0], side: side) }
            }
            Divider()
            Button(urls.count == 1 ? "Copy Path" : "Copy Paths") { state.copyPaths(urls) }
            Button("Reveal in Finder") { state.revealInFinder(urls) }
            if urls.count == 1, pane.items.first(where: { $0.url == urls[0] })?.isFolder == true {
                Button("Open in Terminal") { state.openInTerminal(urls[0]) }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { state.trash(urls, side: side) }
        }
    }
}

private struct NameCell: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(for: item.url))
                .resizable()
                .frame(width: 16, height: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isSymlink {
                Image(systemName: "arrow.turn.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(item.isHidden ? 0.55 : 1)
    }
}

private struct SizeCell: View {
    let item: FileItem
    let sizingEnabled: Bool

    var body: some View {
        Group {
            if let size = item.size {
                Text(Fmt.bytes(size))
            } else if item.isDirectory && !item.isSymlink && sizingEnabled {
                Text("…")
            } else {
                Text("—")
            }
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct PathBar: View {
    @Bindable var pane: PaneModel
    let isActive: Bool
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)

            if pane.isEditingPath {
                TextField("Go to path (e.g. ~/Projects)", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { pane.go(toPath: text) }
                    .onExitCommand { pane.isEditingPath = false }
                    .onAppear {
                        text = pane.url.path
                        fieldFocused = true
                    }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { pane.isEditingPath = false }
                    }
            } else {
                breadcrumbs
            }

            Button { pane.isEditingPath.toggle() } label: { Image(systemName: "pencil") }
                .help("Type a path (⌘L)")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pane.url.path, forType: .string)
            } label: { Image(systemName: "doc.on.clipboard") }
                .help("Copy this folder's path")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                let ancestors = pane.url.ancestors
                ForEach(Array(ancestors.enumerated()), id: \.offset) { index, folder in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .foregroundStyle(.tertiary)
                    }
                    Button(folder.displayName) { pane.go(to: folder) }
                        .buttonStyle(.plain)
                        .fontWeight(index == ancestors.count - 1 ? .semibold : .regular)
                        .padding(.horizontal, 3)
                        .contextMenu {
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(folder.path, forType: .string)
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .defaultScrollAnchor(.trailing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { pane.isEditingPath = true }
    }
}

struct StatusBar: View {
    @Bindable var pane: PaneModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(pane.filter.isEmpty ? .secondary : Color.accentColor)
            TextField("Filter", text: $pane.filter)
                .textFieldStyle(.plain)
                .frame(maxWidth: 160)
                .focused($filterFocused)
                .onExitCommand {
                    pane.filter = ""
                    filterFocused = false
                }
            Spacer()
            if pane.isSizing {
                ProgressView()
                    .controlSize(.mini)
                    .help("Calculating folder sizes")
            }
            Text(pane.summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .onChange(of: pane.filterFocusRequest) { _, _ in filterFocused = true }
    }
}
