import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focusedSide: AppState.Side?
    @FocusState private var goBoxFocused: Bool

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 280)
        } detail: {
            HSplitView {
                PaneView(pane: state.left, side: .left, focusedSide: $focusedSide)
                PaneView(pane: state.right, side: .right, focusedSide: $focusedSide)
            }
            .toolbar { toolbar }
        }
        .inspector(isPresented: $state.showInspector) {
            InspectorView(pane: state.active)
                .inspectorColumnWidth(min: 220, ideal: 270, max: 420)
        }
        .navigationTitle(state.active.url.displayName)
        .onChange(of: focusedSide) { _, side in
            if let side { state.activeSide = side }
        }
        .onChange(of: state.activeSide) { _, side in focusedSide = side }
        .onAppear { focusedSide = state.activeSide }
        .onChange(of: state.goBoxFocusRequest) { _, _ in goBoxFocused = true }
        .confirmationDialog(
            state.pendingTransfer?.title ?? "",
            isPresented: Binding(get: { state.pendingTransfer != nil }, set: { if !$0 { state.pendingTransfer = nil } }),
            presenting: state.pendingTransfer
        ) { transfer in
            Button(transfer.verb) { state.perform(transfer) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { transfer in
            Text(transfer.destination.path)
        }
        .alert(state.namePrompt?.title ?? "", isPresented: $state.isPromptShown) {
            TextField("Name", text: $state.promptText)
            Button("OK") { state.commitPrompt() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { state.namePrompt = nil }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    /// Paste a path and press Return to go there; type anything else to filter the active pane.
    private var goBox: some View {
        @Bindable var state = state
        let isPath = AppState.looksLikePath(state.goText)

        return HStack(spacing: 6) {
            Image(systemName: isPath ? "arrow.right.circle" : "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Paste a path, or search this folder", text: $state.goText)
                .textFieldStyle(.plain)
                .focused($goBoxFocused)
                .onChange(of: state.goText) { _, _ in state.goTextChanged() }
                .onSubmit {
                    if state.submitGoBox() { focusedSide = state.activeSide }
                }
                .onExitCommand {
                    state.clearGoBox()
                    focusedSide = state.activeSide
                }
            if !state.goText.isEmpty {
                Button {
                    state.clearGoBox()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 380)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .help("Paste a path and press Return to open it in the active pane (⌘L)")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { state.active.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!state.active.canGoBack)
            Button { state.active.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .disabled(!state.active.canGoForward)
            Button { state.active.goUp() } label: { Label("Enclosing Folder", systemImage: "arrow.up") }
                .disabled(!state.active.canGoUp)
        }
        ToolbarItem(placement: .principal) {
            goBox
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let busy = state.busyMessage {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(busy).foregroundStyle(.secondary)
                }
            }
            Button { state.requestTransfer(.copy) } label: {
                Label("Copy to Other Pane (F5)", systemImage: "doc.on.doc")
            }
            Button { state.requestTransfer(.move) } label: {
                Label("Move to Other Pane (F6)", systemImage: "arrow.right.doc.on.clipboard")
            }
            Button { state.promptNewFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            Button { state.trash() } label: { Label("Move to Trash", systemImage: "trash") }
            Toggle(isOn: Binding(get: { state.active.showHidden }, set: { state.active.showHidden = $0 })) {
                Label("Show Hidden Files", systemImage: state.active.showHidden ? "eye" : "eye.slash")
            }
            Button { state.showInspector.toggle() } label: { Label("Inspector", systemImage: "info.circle") }
        }
    }
}
