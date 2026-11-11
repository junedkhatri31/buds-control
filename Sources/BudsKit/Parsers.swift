import Foundation

/// Response payload parsers. Inputs exclude the status byte.
public enum Parse {
    /// `n, (side, level|charging<<7)×n`
    public static func battery(_ d: [UInt8]) -> [BatteryLevel] {
        pairs(d).map { BatteryLevel(side: $0.0, percent: Int($0.1 & 0x7F), charging: $0.1 & 0x80 != 0) }
    }

    /// `n, (side, flags)×n`
    public static func earStatus(_ d: [UInt8]) -> [EarStatus] {
        pairs(d).map { EarStatus(side: $0.0, inCase: $0.1 & 1 == 0, inEar: $0.1 & 2 != 0, lidClosed: $0.1 & 4 == 0) }
    }

    /// `n, (featureId, on)×n`
    public static func featureSwitches(_ d: [UInt8]) -> [UInt8: Bool] {
        Dictionary(pairs(d).map { ($0.0, $0.1 == 1) }, uniquingKeysWith: { _, b in b })
    }

    /// `n, (side, button, action, function)×n`
    public static func keyFunctions(_ d: [UInt8]) -> [KeyFunction] {
        guard let n = d.first.map(Int.init), d.count >= 1 + n * 4 else { return [] }
        return (0..<n).map { i in
            let o = 1 + i * 4
            return KeyFunction(side: d[o], button: d[o + 1], action: d[o + 2], function: d[o + 3])
        }
    }

    /// `n, (mac[6] reversed, len, state, flags, nameLen, name, extra…)×n`
    public static func multiConnect(_ d: [UInt8]) -> [ConnectedHost] {
        guard let n = d.first.map(Int.init), n > 0 else { return [] }
        var hosts: [ConnectedHost] = []
        var o = 1
        for _ in 0..<n {
            guard o + 10 <= d.count else { break }
            let wire = d[o..<o + 6].map { String(format: "%02X", $0) }
            let mac = wire.reversed().joined(separator: ":")
            let entryLen = Int(d[o + 6]), state = d[o + 7], flags = d[o + 8], nameLen = Int(d[o + 9])
            let nameStart = o + 10
            guard nameStart + nameLen <= d.count else { break }
            let name = String(decoding: d[nameStart..<nameStart + nameLen], as: UTF8.self)
            if mac != "00:00:00:00:00:00" {
                hosts.append(ConnectedHost(address: mac, addressAsSent: wire.joined(separator: ":"),
                                           name: name, state: state, flags: flags))
            }
            o = nameStart + nameLen + max(0, entryLen - nameLen - 3)
        }
        return hosts
    }

    /// `n, ASCII "side,kind,version,…"` (n triples).
    public static func versions(_ d: [UInt8]) -> [FirmwareVersion] {
        guard d.count > 1 else { return [] }
        let parts = String(decoding: d.dropFirst(), as: UTF8.self).split(separator: ",").map(String.init)
        return stride(from: 0, to: parts.count - parts.count % 3, by: 3).compactMap { i in
            guard let side = Int(parts[i]), let kind = Int(parts[i + 1]) else { return nil }
            return FirmwareVersion(side: side, kind: kind, version: parts[i + 2])
        }
    }

    /// `n, eventId×n`
    public static func idList(_ d: [UInt8]) -> [UInt8] {
        guard let n = d.first.map(Int.init), d.count >= 1 + n else { return [] }
        return Array(d[1...n])
    }

    private static func pairs(_ d: [UInt8]) -> [(UInt8, UInt8)] {
        guard let n = d.first.map(Int.init), n > 0, d.count >= 1 + n * 2 else { return [] }
        return (0..<n).map { (d[1 + $0 * 2], d[2 + $0 * 2]) }
    }
}
