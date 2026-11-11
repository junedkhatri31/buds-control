import Foundation
import IOBluetooth

public enum BudsError: LocalizedError {
    case serviceNotFound
    case openFailed(IOReturn)
    case notConnected
    case timeout(UInt16)
    case status(UInt16, UInt8)
    case unsupported(UInt16)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound: "These earbuds don't expose the control service."
        case .openFailed(let rc): String(format: "Couldn't open the control channel (0x%08X).", rc)
        case .notConnected: "Not connected to the earbuds."
        case .timeout(let c): String(format: "The earbuds didn't answer command 0x%04X.", c)
        case .status(let c, let s): String(format: "The earbuds rejected command 0x%04X (status %d).", c, s)
        case .unsupported(let c): String(format: "These earbuds don't support command 0x%04X.", c)
        }
    }
}

/// Earbud control RFCOMM service UUIDs, in preference order.
public let budsServiceUUIDs: [[UInt8]] = [
    [0x00, 0x00, 0x07, 0x9A, 0xD1, 0x02, 0x11, 0xE1, 0x9B, 0x23, 0x00, 0x02, 0x5B, 0x00, 0xA5, 0xA5],
    [0x00, 0x00, 0x11, 0x07, 0xD1, 0x02, 0x11, 0xE1, 0x9B, 0x23, 0x00, 0x02, 0x5B, 0x00, 0xA5, 0xA5],
]

func sdpUUIDs() -> [IOBluetoothSDPUUID] {
    budsServiceUUIDs.map { IOBluetoothSDPUUID(bytes: $0, length: 16) }
}

/// Returns the RFCOMM channel of the control service from the device's cached SDP records.
func controlChannel(of device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
    for uuid in sdpUUIDs() {
        if let record = device.getServiceRecord(for: uuid) {
            var channel: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess { return channel }
        }
    }
    return nil
}

/// Low-level request/response transport over one RFCOMM channel. Main-actor only, because
/// IOBluetooth delivers its callbacks on the main run loop.
@MainActor
final class RFCOMMConnection: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameDecoder()
    private var nextSequence: UInt8 = 0
    private var pending: [UInt8: (command: UInt16, continuation: CheckedContinuation<[UInt8], Error>)] = [:]

    /// Unsolicited packets (events and device→host requests).
    var onPacket: ((Packet) -> Void)?
    var onClose: (() -> Void)?

    init(device: IOBluetoothDevice) { self.device = device }

    var isOpen: Bool { channel?.isOpen() ?? false }

    func open() async throws {
        var channelID = controlChannel(of: device)
        if channelID == nil {
            // Refresh SDP records (async in IOBluetooth); poll the cache for up to 6 s.
            device.performSDPQuery(nil, uuids: sdpUUIDs())
            for _ in 0..<30 where channelID == nil {
                try await Task.sleep(for: .milliseconds(200))
                channelID = controlChannel(of: device)
            }
        }
        guard let id = channelID else { throw BudsError.serviceNotFound }
        var ch: IOBluetoothRFCOMMChannel?
        let rc = device.openRFCOMMChannelSync(&ch, withChannelID: id, delegate: self)
        guard rc == kIOReturnSuccess, let ch else { throw BudsError.openFailed(rc) }
        channel = ch
    }

    func close() {
        channel?.close()
        channel = nil
        failAll(BudsError.notConnected)
    }

    /// Sends a request and returns the response payload with the status byte removed.
    func request(_ command: UInt16, _ payload: [UInt8] = [], timeout: Duration = .seconds(3)) async throws -> [UInt8] {
        guard let channel, channel.isOpen() else { throw BudsError.notConnected }
        let seq = nextSequence
        nextSequence &+= 1
        let response: [UInt8] = try await withCheckedThrowingContinuation { cont in
            pending[seq] = (command, cont)
            write(Packet(command: command, sequence: seq, payload: payload), on: channel)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolve(seq, with: .failure(BudsError.timeout(command)))
            }
        }
        guard let status = response.first else { return [] }
        if status != 0 { throw BudsError.status(command, status) }
        return Array(response.dropFirst())
    }

    /// Replies to a device-initiated request (same sequence, response bit set).
    func reply(to packet: Packet, payload: [UInt8]) {
        guard let channel else { return }
        write(Packet(command: packet.command | 0x8000, sequence: packet.sequence, payload: payload), on: channel)
    }

    private func write(_ packet: Packet, on channel: IOBluetoothRFCOMMChannel) {
        let mtu = Int(channel.getMTU())
        for var frame in Framing.frames(for: packet, maxFrameSize: min(660, max(64, mtu))) {
            _ = frame.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        }
    }

    private func resolve(_ seq: UInt8, with result: Result<[UInt8], Error>) {
        guard let entry = pending.removeValue(forKey: seq) else { return }
        entry.continuation.resume(with: result)
    }

    private func failAll(_ error: Error) {
        let all = pending
        pending.removeAll()
        all.values.forEach { $0.continuation.resume(throwing: error) }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        MainActor.assumeIsolated { self.handle(bytes) }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            self.channel = nil
            self.failAll(BudsError.notConnected)
            self.onClose?()
        }
    }

    private func handle(_ bytes: [UInt8]) {
        for packet in decoder.feed(bytes) {
            if packet.isResponse, let entry = pending[packet.sequence], entry.command == packet.baseCommand {
                resolve(packet.sequence, with: .success(packet.payload))
            } else {
                onPacket?(packet)
            }
        }
    }
}
