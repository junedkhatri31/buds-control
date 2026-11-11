import SwiftUI
import BudsKit

// MARK: - Menu bar popover

struct MenuBarView: View {
    @Environment(BudsManager.self) private var manager
    @Environment(\.openWindow) private var openWindow

    /// Every linked device, or the most relevant one when none is linked yet.
    private var shown: [BudsDevice] {
        let linked = manager.devices.filter { $0.linkState == .connected }
        if !linked.isEmpty { return linked }
        return manager.selected.map { [$0] } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shown.isEmpty {
                EmptyStateView()
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, device in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 12) {
                    DeviceHeader(device: device, compact: true)
                    if device.linkState == .connected {
                        BatteryRow(device: device)
                        if device.supportsDualConnection {
                            DualConnectionToggle(device: device)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 0) {
                Button("Settings…") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .keyboardShortcut(",")
                Button("Quit Buds Control") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(MenuRowButtonStyle())
            .padding(.horizontal, -6)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Full-width menu-style row: primary text, highlighted on hover like a native menu item.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .foregroundStyle(hovering && isEnabled ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering && isEnabled ? Color.accentColor : .clear)
                        .opacity(configuration.isPressed ? 0.8 : 1)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

// MARK: - Settings window

enum SidebarItem: Hashable {
    case device(String)
    case general
}

struct MainView: View {
    @Environment(BudsManager.self) private var manager
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Devices") {
                    ForEach(manager.devices) { device in
                        DeviceSidebarRow(device: device)
                            .tag(SidebarItem.device(device.id))
                    }
                }
                Section {
                    Label("General", systemImage: "gearshape")
                        .tag(SidebarItem.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .overlay {
                if manager.devices.isEmpty {
                    Text("No devices").foregroundStyle(.secondary)
                }
            }
        } detail: {
            switch selection {
            case .device(let id):
                if let device = manager.devices.first(where: { $0.id == id }) {
                    DevicePage(device: device)
                } else {
                    EmptyStateView().padding(40)
                }
            case .general:
                GeneralPage()
            case nil:
                EmptyStateView().padding(40)
            }
        }
        .onAppear(perform: selectDefault)
        .onChange(of: manager.devices.map(\.id)) { selectDefault() }
        .onChange(of: selection) {
            if case .device(let id) = selection { manager.selectedID = id }
        }
    }

    private func selectDefault() {
        // Debug aid: `--select <name substring>` picks a device at launch (used for screenshots).
        let args = CommandLine.arguments
        if selection == nil, let i = args.firstIndex(of: "--select"), i + 1 < args.count,
           let match = manager.devices.first(where: { $0.name.localizedCaseInsensitiveContains(args[i + 1]) }) {
            selection = .device(match.id)
            return
        }
        if case .device(let id) = selection, manager.devices.contains(where: { $0.id == id }) { return }
        if selection == .general { return }
        selection = manager.selected.map { .device($0.id) }
    }
}

struct DeviceSidebarRow: View {
    let device: BudsDevice

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } icon: {
            Image(systemName: device.symbolName)
        }
    }

    private var summary: String {
        switch device.linkState {
        case .connected:
            let levels = device.batteryComponents.filter { $0.side != BudSide.caseBox.rawValue && $0.percent > 0 }
            if let low = levels.map(\.percent).min() { return "Connected · \(low)%" }
            return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected, .failed: return device.isBluetoothConnected ? "Not linked" : "Not connected"
        }
    }
}

struct DevicePage: View {
    let device: BudsDevice

    var body: some View {
        Form {
            Section { DeviceHeader(device: device, compact: false) }
            if device.linkState == .connected {
                if !device.battery.isEmpty {
                    Section("Battery") { BatteryRow(device: device) }
                }
                if device.supportsDualConnection {
                    DualConnectionSection(device: device)
                }
                if device.supports(Command.getKeyFunction) && !device.keyFunctions.isEmpty {
                    GesturesSection(device: device)
                }
                if !device.versions.isEmpty {
                    Section("Firmware") {
                        ForEach(Array(device.versions.enumerated()), id: \.offset) { _, v in
                            LabeledContent(device.versions.count == 1 ? "Version" : componentTitle(v.side),
                                           value: v.version)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(device.name)
        .toolbar {
            if device.linkState == .connected {
                Button {
                    Task { await device.refreshAll() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Read everything from the device again")
                .disabled(device.busy)
            }
        }
        // Keep the connected-device list fresh while this page is open.
        .onAppear { device.setLiveUpdates(true) }
        .onDisappear { device.setLiveUpdates(false) }
        .id(device.id)
    }

    private func componentTitle(_ side: Int) -> String {
        BudSide(rawValue: UInt8(clamping: side))?.title ?? "Component \(side)"
    }
}

struct GeneralPage: View {
    @AppStorage(AppDelegate.showInDockKey) private var showInDock = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showInDock) {
                    Text("Show in Dock")
                    Text("Turn off to keep Buds Control only in the menu bar.")
                }
                .onChange(of: showInDock) { AppDelegate.applyDockPreference() }
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Components

extension BudsDevice {
    /// Earbuds with a case get an earbuds symbol; single-battery devices (neckbands) get headphones.
    var symbolName: String { battery.isSingleBattery ? "headphones" : "earbuds" }
}

struct EmptyStateView: View {
    @Environment(BudsManager.self) private var manager

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "earbuds").font(.largeTitle).foregroundStyle(.secondary)
            Text("No compatible earbuds").font(.headline)
            Text("Pair and connect compatible OPPO, OnePlus or realme earbuds.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Scan again") { manager.rescan() }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DeviceHeader: View {
    let device: BudsDevice
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbolName)
                .font(compact ? .title3 : .largeTitle)
                .foregroundStyle(.tint)
                .frame(width: compact ? 28 : 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(compact ? .headline : .title3.bold())
                Text(statusText).font(.caption).foregroundStyle(statusColor)
            }
            Spacer()
            switch device.linkState {
            case .connecting:
                ProgressView().controlSize(.small)
            case .connected:
                if device.busy { ProgressView().controlSize(.small) }
            case .disconnected, .failed:
                Button("Connect") { Task { await device.connect() } }
                    .disabled(!device.isBluetoothConnected)
            }
        }
        if let error = device.lastError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch device.linkState {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: device.isBluetoothConnected ? "Not linked" : "Not connected to this Mac"
        case .failed(let message): message
        }
    }

    private var statusColor: Color {
        if case .failed = device.linkState { return .red }
        return .secondary
    }
}

/// One gauge per battery the device reports: left/right/case for earbuds, one for neckbands.
struct BatteryRow: View {
    let device: BudsDevice

    var body: some View {
        let parts = device.batteryComponents
        HStack(alignment: .top, spacing: 0) {
            ForEach(parts, id: \.side) { level in
                BatteryGauge(title: title(for: level.side, single: parts.count == 1),
                             level: level,
                             caption: caption(for: level.side))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func title(for side: UInt8, single: Bool) -> String {
        if single { return "Battery" }
        return BudSide(rawValue: side)?.title ?? "Battery \(side)"
    }

    private func caption(for side: UInt8) -> String? {
        guard side != BudSide.caseBox.rawValue, device.battery.count > 1,
              let status = device.status(for: BudSide(rawValue: side) ?? .left) else { return nil }
        if status.inEar { return "In ear" }
        if status.inCase { return "In case" }
        return nil
    }
}

struct BatteryGauge: View {
    let title: String
    let level: BatteryLevel
    let caption: String?

    var body: some View {
        // A case reports 0 % when it can't be measured (e.g. both buds are out of it).
        let known = level.percent > 0 || level.charging
        VStack(spacing: 6) {
            Gauge(value: Double(level.percent), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                if level.charging {
                    Image(systemName: "bolt.fill")
                } else {
                    Text(known ? "\(level.percent)" : "–")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(!known ? .secondary : level.percent <= 20 ? .red : .green)
            Text(title).font(.caption)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(known ? "\(level.percent) percent" : "unknown")\(level.charging ? ", charging" : "")")
    }
}

struct DualConnectionToggle: View {
    let device: BudsDevice

    var body: some View {
        Toggle(isOn: Binding(
            get: { device.dualConnectionEnabled },
            set: { newValue in Task { await device.setFeature(.dualConnection, enabled: newValue) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dual connection")
                Text("Stay connected to two devices at once.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .disabled(device.busy)
    }
}

struct DualConnectionSection: View {
    let device: BudsDevice

    var body: some View {
        Section {
            DualConnectionToggle(device: device)
        } header: {
            Text("Dual connection")
        }
        Section {
            if device.connectedHosts.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
            ForEach(device.connectedHosts) { host in
                HStack(spacing: 10) {
                    Image(systemName: host.isThisDevice ? "laptopcomputer" : "iphone")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(host.name.isEmpty ? "Unnamed device" : host.name)
                    if host.isThisDevice {
                        Text("This Mac")
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if host.isAudioActive {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.secondary)
                            .help("Playing audio")
                    }
                }
                .help(host.address)
            }
        } header: {
            Text("Connected now")
        }
    }
}

struct GesturesSection: View {
    let device: BudsDevice

    var body: some View {
        let buttons = Array(Set(device.keyFunctions.map(\.button))).sorted()
        // Only label left/right when the device has gestures on both sides.
        let sides = Set(device.keyFunctions.map(\.side))
        ForEach(buttons, id: \.self) { button in
            let slots = device.keyFunctions.filter { $0.button == button }
            let callGroup = GestureCatalog.isCallGroup(slots)
            let actions = Array(Set(slots.map(\.action))).sorted()
            Section {
                ForEach(actions, id: \.self) { action in
                    let row = slots.filter { $0.action == action }.sorted { $0.side < $1.side }
                    GestureRow(device: device, action: action, slots: row,
                               showSides: sides.count > 1, callGroup: callGroup)
                }
            } header: {
                Text(title(forButton: button, callGroup: callGroup))
            }
        }
    }

    /// Button IDs are model-specific; name a group from what its slots do.
    private func title(forButton button: UInt8, callGroup: Bool) -> String {
        if callGroup { return "Gestures during calls" }
        switch button {
        case 1: return "Gestures"
        case 2: return "Volume up button"
        case 3: return "Volume down button"
        case 5: return "Middle button"
        default: return "Gestures (set \(button))"
        }
    }
}

struct GestureRow: View {
    let device: BudsDevice
    let action: UInt8
    let slots: [KeyFunction]
    let showSides: Bool
    let callGroup: Bool

    var body: some View {
        LabeledContent(GestureAction.title(action)) {
            HStack(spacing: 12) {
                ForEach(slots) { slot in picker(for: slot) }
            }
        }
    }

    private func picker(for slot: KeyFunction) -> some View {
        let options = GestureCatalog.options(for: slot, callGroup: callGroup, legacy: device.usesLegacyTrackCodes)
        let side = slot.side == BudSide.left.rawValue ? "L" : slot.side == BudSide.right.rawValue ? "R" : "\(slot.side)"
        return HStack(spacing: 4) {
            if showSides {
                Text(side).font(.caption.bold()).foregroundStyle(.secondary)
            }
            Picker(GestureAction.title(action), selection: Binding(
                get: { slot.function },
                set: { code in Task { await device.setKeyFunction(slot, function: code) } }
            )) {
                ForEach(options.suggested) { Text($0.title).tag($0.code) }
                if !options.more.isEmpty {
                    Section("More functions (may not be supported)") {
                        ForEach(options.more) { Text($0.title).tag($0.code) }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(device.busy)
        }
    }
}
