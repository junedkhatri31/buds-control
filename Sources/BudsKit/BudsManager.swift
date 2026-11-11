import Foundation
import IOBluetooth
import Observation

/// Finds paired earbuds that expose the earbud control service, and connects
/// to them automatically when they connect to this Mac.
@MainActor
@Observable
public final class BudsManager {
    public private(set) var devices: [BudsDevice] = []
    public var selectedID: String?

    @ObservationIgnored private var observer: ConnectionObserver?

    public init() {}

    public var selected: BudsDevice? {
        devices.first { $0.id == selectedID } ?? devices.first { $0.isBluetoothConnected } ?? devices.first
    }

    public func start() {
        guard observer == nil else { return }
        observer = ConnectionObserver { [weak self] device in
            self?.deviceDidConnect(device)
        }
        rescan()
    }

    /// Re-reads paired devices. Earbuds qualify if their cached SDP records list the control
    /// service; connected devices without cached records are queried.
    public func rescan() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in paired {
            if controlChannel(of: device) != nil {
                adopt(device)
            } else if device.isConnected(), isHeadsetClass(device) {
                device.performSDPQuery(nil, uuids: sdpUUIDs())
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if controlChannel(of: device) != nil { self.adopt(device) }
                }
            }
        }
    }

    private func isHeadsetClass(_ device: IOBluetoothDevice) -> Bool {
        device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio)
    }

    private func adopt(_ device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        let buds: BudsDevice
        if let existing = devices.first(where: { $0.id == address }) {
            buds = existing
        } else {
            buds = BudsDevice(device: device)
            devices.append(buds)
        }
        if device.isConnected(), buds.linkState != .connected, buds.linkState != .connecting {
            Task { await buds.connect() }
        }
    }

    private func deviceDidConnect(_ device: IOBluetoothDevice) {
        if controlChannel(of: device) != nil || devices.contains(where: { $0.id == device.addressString }) {
            // Give the audio profiles a moment to settle before opening RFCOMM.
            Task {
                try? await Task.sleep(for: .seconds(2))
                self.adopt(device)
            }
        } else if isHeadsetClass(device) {
            rescan()
        }
    }
}

/// Bridges IOBluetooth's selector-based connect/disconnect notifications.
@MainActor
private final class ConnectionObserver: NSObject {
    private let onConnect: (IOBluetoothDevice) -> Void
    private var connectNotification: IOBluetoothUserNotification?

    init(onConnect: @escaping (IOBluetoothDevice) -> Void) {
        self.onConnect = onConnect
        super.init()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onConnect(device)
    }
}
