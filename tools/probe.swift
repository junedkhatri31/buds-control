// RFCOMM probe for OPPO/OnePlus earbuds.
// Usage: probe <MAC> [hexcmd[:hexpayload] ...]
// Example: probe AA:BB:CC:DD:EE:FF 0106 0108 0109 010D 0112
import Foundation
import IOBluetooth

let serviceUUID: [UInt8] = [0x00,0x00,0x07,0x9A,0xD1,0x02,0x11,0xE1,0x9B,0x23,0x00,0x02,0x5B,0x00,0xA5,0xA5]

func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }

func frame(cmd: UInt16, seq: UInt8, payload: [UInt8]) -> [UInt8] {
    var inner: [UInt8] = [UInt8(cmd & 0xFF), UInt8(cmd >> 8), seq,
                          UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)]
    inner += payload
    var len = inner.count + 2 // flags + reserved
    var varint: [UInt8] = []
    repeat {
        var b = UInt8(len & 0x7F); len >>= 7
        if len != 0 { b |= 0x80 }
        varint.append(b)
    } while len != 0
    return [0xAA] + varint + [0x00, 0x00] + inner
}

final class Delegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data ptr: UnsafeMutableRawPointer!, length: Int) {
        let bytes = Array(UnsafeBufferPointer(start: ptr.assumingMemoryBound(to: UInt8.self), count: length))
        print("RX \(hex(bytes))")
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { print("channel closed") }
}

let args = CommandLine.arguments
guard args.count >= 2, let dev = IOBluetoothDevice(addressString: args[1]) else {
    print("usage: probe <MAC> [cmd[:payload]...]"); exit(1)
}
print("device: \(dev.name ?? "?") connected=\(dev.isConnected())")
let uuid = IOBluetoothSDPUUID(bytes: serviceUUID, length: 16)
if dev.performSDPQuery(nil, uuids: [uuid]) != kIOReturnSuccess { print("SDP query failed") }
// performSDPQuery is async; wait for records
let deadline = Date().addingTimeInterval(5)
var record: IOBluetoothSDPServiceRecord?
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    record = dev.getServiceRecord(for: uuid)
    if record != nil { break }
}
var channelID: BluetoothRFCOMMChannelID = 0
if let r = record, r.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
    print("SDP: RFCOMM channel \(channelID) for 0000079A-D102-11E1-9B23-00025B00A5A5")
} else {
    print("service record not found; listing services:")
    for case let s as IOBluetoothSDPServiceRecord in dev.services ?? [] {
        var c: BluetoothRFCOMMChannelID = 0
        let hasCh = s.getRFCOMMChannelID(&c) == kIOReturnSuccess
        print("  \(s.getServiceName() ?? "?") rfcomm=\(hasCh ? String(c) : "-")")
    }
    exit(2)
}

let delegate = Delegate()
var channel: IOBluetoothRFCOMMChannel?
let rc = dev.openRFCOMMChannelSync(&channel, withChannelID: channelID, delegate: delegate)
guard rc == kIOReturnSuccess, let ch = channel else { print("open failed: \(rc)"); exit(3) }
print("RFCOMM open, mtu=\(ch.getMTU())")

var seq: UInt8 = 0
for spec in args.dropFirst(2) {
    let parts = spec.split(separator: ":")
    let cmd = UInt16(parts[0], radix: 16)!
    var payload: [UInt8] = []
    if parts.count > 1 {
        let s = Array(parts[1])
        payload = stride(from: 0, to: s.count, by: 2).map { UInt8(String(s[$0...$0+1]), radix: 16)! }
    }
    var f = frame(cmd: cmd, seq: seq, payload: payload); seq &+= 1
    print(String(format: "TX cmd=0x%04X ", cmd) + hex(f))
    _ = f.withUnsafeMutableBytes { ch.writeSync($0.baseAddress, length: UInt16($0.count)) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
}
RunLoop.current.run(until: Date().addingTimeInterval(1.5))
ch.close()
