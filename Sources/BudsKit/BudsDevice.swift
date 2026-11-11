import Foundation
import IOBluetooth
import Observation

/// One pair of earbuds and everything the app knows about it.
@MainActor
@Observable
public final class BudsDevice: Identifiable {
    public enum LinkState: Equatable { case disconnected, connecting, connected, failed(String) }

    public nonisolated let id: String
    public let name: String
    public private(set) var linkState: LinkState = .disconnected
    public private(set) var capabilities = Capabilities(commands: alwaysSupportedCommands)
    public private(set) var battery: [BatteryLevel] = []
    public private(set) var earStatus: [EarStatus] = []
    public private(set) var keyFunctions: [KeyFunction] = []
    public private(set) var features: [UInt8: Bool] = [:]
    public private(set) var hosts: [ConnectedHost] = []
    public private(set) var versions: [FirmwareVersion] = []
    public private(set) var lastError: String?
    public private(set) var busy = false

    @ObservationIgnored let bluetoothDevice: IOBluetoothDevice
    @ObservationIgnored private var connection: RFCOMMConnection?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public var usesLegacyTrackCodes: Bool { GestureCatalog.usesLegacyTrackCodes(deviceName: name) }
    public var isBluetoothConnected: Bool { bluetoothDevice.isConnected() }

    init(device: IOBluetoothDevice) {
        bluetoothDevice = device
        id = device.addressString ?? UUID().uuidString
        name = device.name ?? "Earbuds"
    }

    public func battery(for side: BudSide) -> BatteryLevel? { battery.first { $0.side == side.rawValue } }
    public func status(for side: BudSide) -> EarStatus? { earStatus.first { $0.side == side.rawValue } }
    public func supports(_ command: UInt16) -> Bool { capabilities.supports(command) }
    /// The buds echo every requested feature ID, so presence in `features` doesn't imply support.
    /// Multipoint support is signalled by the multi-connect capability bit (0x0112/0x040B).
    public var supportsDualConnection: Bool { supports(Command.getMultiConnect) && supports(Command.setSwitchFeature) }
    public var dualConnectionEnabled: Bool { features[Feature.dualConnection.rawValue] ?? false }

    // MARK: Lifecycle

    public func connect() async {
        guard connection?.isOpen != true else { return }
        linkState = .connecting
        let conn = RFCOMMConnection(device: bluetoothDevice)
        conn.onPacket = { [weak self] in self?.handleUnsolicited($0) }
        conn.onClose = { [weak self] in self?.handleClosed() }
        do {
            try await conn.open()
            connection = conn
            linkState = .connected
            await initialSync()
            startPolling()
        } catch {
            linkState = .failed(error.localizedDescription)
        }
    }

    public func disconnect() {
        pollTask?.cancel()
        connection?.close()
        connection = nil
        linkState = .disconnected
    }

    private func handleClosed() {
        pollTask?.cancel()
        connection = nil
        linkState = .disconnected
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refreshBattery()
            }
        }
    }

    // MARK: Reads

    private func initialSync() async {
        if let bitmap = try? await request(Command.getCapability) {
            capabilities = Capabilities(bitmap: bitmap)
        }
        await refreshAll()
        await subscribeToEvents()
    }

    public func refreshAll() async {
        busy = true
        defer { busy = false }
        await refreshBattery()
        if let d = try? await request(Command.getEarStatus) { earStatus = Parse.earStatus(d) }
        if supports(Command.getVersion), let d = try? await request(Command.getVersion) { versions = Parse.versions(d) }
        await refreshKeyFunctions()
        await refreshFeatures()
        await refreshHosts()
    }

    public func refreshBattery() async {
        if let d = try? await request(Command.getBattery) { battery = Parse.battery(d) }
    }

    func refreshKeyFunctions() async {
        guard supports(Command.getKeyFunction) else { return }
        if let d = try? await request(Command.getKeyFunction) { keyFunctions = Parse.keyFunctions(d) }
    }

    func refreshFeatures() async {
        let ids = Feature.allCases.map(\.rawValue)
        if let d = try? await request(Command.getFeatureSwitch, [UInt8(ids.count)] + ids) {
            features = Parse.featureSwitches(d)
        }
    }

    func refreshHosts() async {
        guard supports(Command.getMultiConnect) else { return }
        if let d = try? await request(Command.getMultiConnect) { hosts = Parse.multiConnect(d) }
    }

    private func subscribeToEvents() async {
        guard let raw = try? await request(Command.getNotificationCapability) else { return }
        let events = Parse.idList(raw)
        guard !events.isEmpty else { return }
        if supports(Command.registerMultiNotification) {
            _ = try? await request(Command.registerMultiNotification, [UInt8(events.count)] + events)
        } else {
            for e in events { _ = try? await request(Command.registerNotification, [e]) }
        }
    }

    // MARK: Writes

    public func setFeature(_ feature: Feature, enabled: Bool) async {
        await perform {
            try await self.request(Command.setSwitchFeature, [feature.rawValue, enabled ? 1 : 0])
            self.features[feature.rawValue] = enabled
        }
        await refreshFeatures()
        if feature == .dualConnection { await refreshHosts() }
    }

    public func setKeyFunction(_ slot: KeyFunction, function: UInt8) async {
        var updated = slot
        updated.function = function
        await perform {
            try await self.request(Command.setKeyFunction, [1] + updated.bytes)
        }
        await refreshKeyFunctions()
    }

    private func perform(_ body: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await body()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    private func request(_ command: UInt16, _ payload: [UInt8] = []) async throws -> [UInt8] {
        guard let connection else { throw BudsError.notConnected }
        return try await connection.request(command, payload)
    }

    // MARK: Device-initiated packets

    private func handleUnsolicited(_ packet: Packet) {
        switch packet.command {
        case Command.deviceRequestsUTCTime:
            let now = UInt32(Date().timeIntervalSince1970)
            connection?.reply(to: packet, payload: [0, UInt8(now & 0xFF), UInt8((now >> 8) & 0xFF),
                                                    UInt8((now >> 16) & 0xFF), UInt8(now >> 24)])
        case Command.notificationEvent:
            handleEvent(packet.payload)
        case Command.deviceFeatureSwitchSync:
            features.merge(Parse.featureSwitches(packet.payload)) { _, new in new }
        case Command.deviceMultiConnectChanged:
            Task { await refreshHosts() }
        default:
            break
        }
    }

    private func handleEvent(_ payload: [UInt8]) {
        guard let event = payload.first else { return }
        let data = Array(payload.dropFirst())
        switch event {
        case 1:
            let update = Parse.battery(data)
            if !update.isEmpty {
                for b in update { battery.removeAll { $0.side == b.side } }
                battery = (battery + update).sorted { $0.side < $1.side }
            }
        case 2:
            let update = Parse.earStatus(data)
            if !update.isEmpty { earStatus = update }
        default:
            break
        }
    }
}
