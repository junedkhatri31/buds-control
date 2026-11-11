import XCTest
@testable import BudsKit

/// Byte sequences captured live from a OnePlus Nord Buds 3r (see docs/PROTOCOL.md).
final class ProtocolTests: XCTestCase {
    func hex(_ s: String) -> [UInt8] { s.split(separator: " ").map { UInt8($0, radix: 16)! } }

    func testEncodeMatchesCapturedRequest() {
        let frames = Framing.frames(for: Packet(command: 0x0106, sequence: 2))
        XCTAssertEqual(frames, [hex("AA 07 00 00 06 01 02 00 00")])
        let feature = Framing.frames(for: Packet(command: 0x010D, sequence: 0, payload: [1, 0x11]))
        XCTAssertEqual(feature, [hex("AA 09 00 00 0D 01 00 02 00 01 11")])
    }

    func testDecodeBatteryResponse() throws {
        var decoder = FrameDecoder()
        let packets = decoder.feed(hex("AA 0F 00 00 06 81 02 08 00 00 03 01 64 02 64 03 00"))
        let p = try XCTUnwrap(packets.first)
        XCTAssertEqual(p.command, 0x8106)
        XCTAssertEqual(p.baseCommand, Command.getBattery)
        XCTAssertEqual(p.sequence, 2)
        let battery = Parse.battery(Array(p.payload.dropFirst()))
        XCTAssertEqual(battery, [BatteryLevel(side: 1, percent: 100, charging: false),
                                 BatteryLevel(side: 2, percent: 100, charging: false),
                                 BatteryLevel(side: 3, percent: 0, charging: false)])
    }

    func testDecoderHandlesSplitAndConcatenatedReads() {
        var decoder = FrameDecoder()
        let a = hex("AA 0C 00 00 00 05 03 05 00 00 00 00 00 00")
        let b = hex("AA 0B 00 00 0D 81 00 04 00 00 01 11 01")
        let stream = a + b
        var packets = decoder.feed(Array(stream[0..<5]))
        XCTAssertTrue(packets.isEmpty)
        packets = decoder.feed(Array(stream[5...]))
        XCTAssertEqual(packets.map(\.command), [0x0500, 0x810D])
        XCTAssertEqual(Parse.featureSwitches(Array(packets[1].payload.dropFirst())), [17: true])
    }

    func testFragmentRoundTrip() {
        let big = Packet(command: 0x0401, sequence: 9, payload: (0..<1500).map { UInt8($0 & 0xFF) })
        let frames = Framing.frames(for: big, maxFrameSize: 660)
        XCTAssertGreaterThan(frames.count, 1)
        var decoder = FrameDecoder()
        XCTAssertEqual(frames.flatMap { decoder.feed($0) }, [big])
    }

    func testCapabilityBitmap() {
        let caps = Capabilities(bitmap: hex("FF 74 D0 A3 05 14 00 06"))
        XCTAssertTrue(caps.supports(Command.getKeyFunction))
        XCTAssertTrue(caps.supports(Command.setKeyFunction))
        XCTAssertTrue(caps.supports(Command.setSwitchFeature))
        XCTAssertTrue(caps.supports(Command.getMultiConnect))
        XCTAssertTrue(caps.supports(Command.getBattery))
    }

    func testKeyFunctionsAndMultiConnect() {
        let keys = Parse.keyFunctions(hex("04 01 01 02 06 01 01 06 0C 02 06 02 1D 02 06 06 1C"))
        XCTAssertEqual(keys.count, 4)
        XCTAssertEqual(keys[1], KeyFunction(side: 1, button: 1, action: 6, function: 12))

        let hosts = Parse.multiConnect(hex(
            "02 66 55 44 33 22 11 0A 02 00 07 50 69 78 65 6C 20 38 FF EE DD CC BB AA 11 02 01 0E 4D 79 20 4D 61 63 42 6F 6F 6B 20 50 72 6F"))
        XCTAssertEqual(hosts.map(\.name), ["Pixel 8", "My MacBook Pro"])
        XCTAssertEqual(hosts.map(\.address), ["11:22:33:44:55:66", "AA:BB:CC:DD:EE:FF"])
        XCTAssertEqual(hosts.map(\.isActive), [false, true])
    }

    func testVersions() {
        let v = Parse.versions([3] + Array("1,2,112,2,2,112,3,2,101".utf8))
        XCTAssertEqual(v.map(\.side), [1, 2, 3])
        XCTAssertEqual(v.map(\.version), ["112", "112", "101"])
    }
}
