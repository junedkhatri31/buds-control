import Foundation

/// One application-level packet: `cmd:u16le | seq:u8 | len:u16le | payload`.
public struct Packet: Equatable, Sendable {
    public var command: UInt16
    public var sequence: UInt8
    public var payload: [UInt8]

    public init(command: UInt16, sequence: UInt8, payload: [UInt8] = []) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }

    public var isResponse: Bool { command & 0x8000 != 0 }
    /// Request command this response answers (bit 15 cleared).
    public var baseCommand: UInt16 { command & 0x7FFF }

    public func encoded() -> [UInt8] {
        var out: [UInt8] = [UInt8(command & 0xFF), UInt8(command >> 8), sequence,
                            UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF)]
        out += payload
        return out
    }

    public init?(decoding bytes: [UInt8]) {
        guard bytes.count >= 5 else { return nil }
        command = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        sequence = bytes[2]
        let declared = Int(bytes[3]) | Int(bytes[4]) << 8
        // The official decoder trusts the actual length when the declared one is too large.
        payload = Array(bytes[5..<min(bytes.count, 5 + declared)])
    }
}

/// Wire framing: `AA | varint(L) | flags | 00 | [fsn] | chunk`.
public enum Framing {
    public static let startOfFrame: UInt8 = 0xAA

    static func varint(_ value: Int) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7F); v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    /// Splits a packet into frames that fit `maxFrameSize` (the official app uses 660).
    public static func frames(for packet: Packet, maxFrameSize: Int = 660) -> [[UInt8]] {
        let body = packet.encoded()
        let singleOverhead = 1 + varint(body.count + 2).count + 2
        if body.count + singleOverhead <= maxFrameSize {
            return [[startOfFrame] + varint(body.count + 2) + [0x00, 0x00] + body]
        }
        let chunkSize = maxFrameSize - 1 - 2 - 3 // AA + 2-byte varint + flags/00/fsn
        var frames: [[UInt8]] = []
        var offset = 0, fsn: UInt8 = 0
        while offset < body.count {
            let end = min(offset + chunkSize, body.count)
            let flags: UInt8 = offset == 0 ? 1 : (end == body.count ? 3 : 2)
            let chunk = Array(body[offset..<end])
            frames.append([startOfFrame] + varint(chunk.count + 3) + [flags, 0x00, fsn] + chunk)
            fsn &+= 1
            offset = end
        }
        return frames
    }
}

/// Incremental decoder for the RFCOMM byte stream. Handles partial reads and fragments.
public struct FrameDecoder {
    private var buffer: [UInt8] = []
    private var fragments: [UInt8] = []
    private var collectingFragments = false

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Packet] {
        buffer += bytes
        var packets: [Packet] = []
        while true {
            // Resynchronise on the start byte.
            if let start = buffer.firstIndex(of: Framing.startOfFrame), start > 0 {
                buffer.removeFirst(start)
            } else if buffer.first != Framing.startOfFrame {
                buffer.removeAll(); break
            }
            guard let (length, varintSize) = readVarint(at: 1) else { break }
            let total = 1 + varintSize + length
            guard buffer.count >= total else { break }
            let body = Array(buffer[(1 + varintSize)..<total])
            buffer.removeFirst(total)
            guard body.count >= 2 else { continue }
            let flags = body[0] & 0x03
            if flags == 0 {
                collectingFragments = false
                if let p = Packet(decoding: Array(body.dropFirst(2))) { packets.append(p) }
                continue
            }
            guard body.count >= 3 else { continue }
            let chunk = body.dropFirst(3)
            if flags == 1 { fragments = Array(chunk); collectingFragments = true; continue }
            guard collectingFragments else { continue }
            fragments += chunk
            if flags == 3 {
                collectingFragments = false
                if let p = Packet(decoding: fragments) { packets.append(p) }
                fragments = []
            }
        }
        return packets
    }

    private func readVarint(at index: Int) -> (Int, Int)? {
        var value = 0, shift = 0, i = index
        while i < buffer.count && i < index + 3 {
            let b = buffer[i]
            value |= Int(b & 0x7F) << shift
            if b & 0x80 == 0 { return (value, i - index + 1) }
            shift += 7; i += 1
        }
        return nil
    }
}
