import SwiftUI
import BudsKit

// MARK: - Menu bar popover

struct MenuBarView: View {
    @Environment(BudsManager.self) private var manager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let device = manager.selected {
                DeviceHeader(device: device)
                if device.linkState == .connected {
                    BatteryRow(device: device)
                    if device.supportsDualConnection {
                        Divider()
                        DualConnectionToggle(device: device)
                    }
                }
            } else {
                EmptyStateView()
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

// MARK: - Main window

struct MainView: View {
    @Environment(BudsManager.self) private var manager

    var body: some View {
        @Bindable var manager = manager
        Group {
            if let device = manager.selected {
                Form {
                    Section {
                        DeviceHeader(device: device)
                        if manager.devices.count > 1 {
                            Picker("Earbuds", selection: Binding(get: { device.id }, set: { manager.selectedID = $0 })) {
                                ForEach(manager.devices) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    if device.linkState == .connected {
                        Section("Battery") { BatteryRow(device: device) }
                        if device.supportsDualConnection {
                            Section("Dual connection") {
                                DualConnectionToggle(device: device)
                                ForEach(device.hosts) { host in
                                    HStack {
                                        Image(systemName: "laptopcomputer.and.iphone")
                                            .foregroundStyle(.secondary)
                                        Text(host.name.isEmpty ? host.address : host.name)
                                        Spacer()
                                        Text(host.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if device.supports(Command.getKeyFunction) && !device.keyFunctions.isEmpty {
                            GesturesSection(device: device)
                        }
                        if !device.versions.isEmpty {
                            Section("Firmware") {
                                ForEach(Array(device.versions.enumerated()), id: \.offset) { _, v in
                                    LabeledContent(BudSide(rawValue: UInt8(clamping: v.side))?.title ?? "Component \(v.side)",
                                                   value: v.version)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                EmptyStateView().padding(40)
            }
        }
        .toolbar {
            if let device = manager.selected, device.linkState == .connected {
                Button {
                    Task { await device.refreshAll() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(device.busy)
            }
        }
    }
}

// MARK: - Components

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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds.case.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
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

struct BatteryRow: View {
    let device: BudsDevice

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(BudSide.allCases, id: \.self) { side in
                BatteryGauge(side: side, level: device.battery(for: side), status: device.status(for: side))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct BatteryGauge: View {
    let side: BudSide
    let level: BatteryLevel?
    let status: EarStatus?

    var body: some View {
        // The case reports 0 % when it can't be measured (e.g. both buds are out of it).
        let known = level.map { $0.percent > 0 || $0.charging } ?? false
        let percent = known ? level!.percent : 0
        VStack(spacing: 6) {
            Gauge(value: Double(percent), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                if level?.charging == true {
                    Image(systemName: "bolt.fill")
                } else {
                    Text(known ? "\(percent)" : "–")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(!known ? .secondary : percent <= 20 ? .red : .green)
            Text(side.title).font(.caption)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.title) battery \(known ? "\(percent) percent" : "unknown")\(level?.charging == true ? ", charging" : "")")
    }

    private var caption: String? {
        guard side != .caseBox, let status else { return nil }
        if status.inEar { return "In ear" }
        if status.inCase { return "In case" }
        return nil
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

struct GesturesSection: View {
    let device: BudsDevice
    @AppStorage("showAllGestureFunctions") private var showAll = false

    var body: some View {
        let buttons = Array(Set(device.keyFunctions.map(\.button))).sorted()
        ForEach(buttons, id: \.self) { button in
            let slots = device.keyFunctions.filter { $0.button == button }
            let actions = Array(Set(slots.map(\.action))).sorted()
            Section {
                ForEach(actions, id: \.self) { action in
                    GestureRow(device: device, action: action,
                               left: slots.first { $0.action == action && $0.side == BudSide.left.rawValue },
                               right: slots.first { $0.action == action && $0.side == BudSide.right.rawValue },
                               showAll: showAll)
                }
            } header: {
                Text(title(forButton: button, slots: slots))
            }
        }
        Section {
            Toggle(isOn: $showAll) {
                Text("Show all functions")
                Text("Offer every known function. Some earbuds reject functions they don't have.")
            }
        }
    }

    /// Button IDs are model-specific; name a group from what its slots do.
    private func title(forButton button: UInt8, slots: [KeyFunction]) -> String {
        if slots.contains(where: { $0.function == 28 || $0.function == 29 }) { return "Gestures during calls" }
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
    let left: KeyFunction?
    let right: KeyFunction?
    let showAll: Bool

    var body: some View {
        LabeledContent(GestureAction.title(action)) {
            HStack(spacing: 8) {
                if let left { picker(for: left, label: "L") }
                if let right { picker(for: right, label: "R") }
            }
        }
    }

    private func picker(for slot: KeyFunction, label: String) -> some View {
        let options = GestureCatalog.options(for: slot, legacy: device.usesLegacyTrackCodes, showAll: showAll)
        return HStack(spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Picker(label, selection: Binding(
                get: { slot.function },
                set: { code in Task { await device.setKeyFunction(slot, function: code) } }
            )) {
                ForEach(options) { Text($0.title).tag($0.code) }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(device.busy)
        }
    }
}
