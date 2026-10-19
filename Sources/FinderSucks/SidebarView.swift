import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @State private var volumes: [URL] = []

    private struct Place: Identifiable {
        let name: String
        let symbol: String
        let url: URL
        var id: URL { url }
    }

    private var favorites: [Place] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var places = [
            Place(name: NSUserName(), symbol: "house", url: home),
            Place(name: "Desktop", symbol: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop")),
            Place(name: "Documents", symbol: "doc", url: home.appendingPathComponent("Documents")),
            Place(name: "Downloads", symbol: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            Place(name: "Applications", symbol: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications")),
        ]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) {
            places.append(Place(name: "iCloud Drive", symbol: "icloud", url: iCloud))
        }
        return places
    }

    var body: some View {
        List {
            Section("Favorites") {
                ForEach(favorites) { place in
                    row(place.name, symbol: place.symbol, url: place.url)
                }
            }
            Section("Locations") {
                ForEach(volumes, id: \.self) { volume in
                    row(volume.displayName, symbol: volume.path == "/" ? "internaldrive" : "externaldrive", url: volume)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear(perform: loadVolumes)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            loadVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            loadVolumes()
        }
    }

    private func row(_ name: String, symbol: String, url: URL) -> some View {
        let isCurrent = state.active.url.isSamePath(as: url)
        return Button { state.active.go(to: url) } label: {
            Label(name, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fontWeight(isCurrent ? .semibold : .regular)
        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
    }

    private func loadVolumes() {
        volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]
        ) ?? []
    }
}
