import SwiftUI
import BudsKit

@main
struct BudsControlApp: App {
    @State private var manager = BudsManager()

    init() {
        if SelfTest.isRequested {
            let manager = _manager.wrappedValue
            Task { @MainActor in await SelfTest.run(manager) }
        }
        Task { @MainActor in Snapshot.scheduleIfRequested() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(manager)
                .task { manager.start() }
        } label: {
            MenuBarLabel(device: manager.selected)
                .task { manager.start() }
        }
        .menuBarExtraStyle(.window)

        Window("Buds Control", id: "main") {
            MainView()
                .environment(manager)
                .frame(minWidth: 520, minHeight: 560)
                .task { manager.start() }
        }
        .defaultSize(width: 600, height: 1100)
        .windowResizability(.contentMinSize)

        // Debug aid (`--preview-menu`): the menu-bar popover's content in a normal window.
        Window("Menu Preview", id: "menu-preview") {
            MenuBarView()
                .environment(manager)
                .task { manager.start() }
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    let device: BudsDevice?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        label.task {
            if CommandLine.arguments.contains("--show-window") {
                openWindow(id: "main")
                NSApp.activate()
            }
            if CommandLine.arguments.contains("--preview-menu") {
                openWindow(id: "menu-preview")
                NSApp.activate()
            }
        }
    }

    @ViewBuilder private var label: some View {
        let levels = [BudSide.left, .right].compactMap { device?.battery(for: $0)?.percent }.filter { $0 > 0 }
        if device?.linkState == .connected, let low = levels.min() {
            Label("\(low)%", systemImage: "earbuds")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "earbuds")
        }
    }
}
