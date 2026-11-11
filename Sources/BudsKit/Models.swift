import Foundation

public enum BudSide: UInt8, Sendable, CaseIterable {
    case left = 1, right = 2, caseBox = 3

    public var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .caseBox: "Case"
        }
    }
}

public struct BatteryLevel: Equatable, Sendable {
    public var side: UInt8
    public var percent: Int
    public var charging: Bool
}

public struct EarStatus: Equatable, Sendable {
    public var side: UInt8
    public var inCase: Bool
    public var inEar: Bool
    public var lidClosed: Bool
}

/// One gesture slot: (side, button, action) → function.
public struct KeyFunction: Hashable, Sendable, Identifiable {
    public var side: UInt8
    public var button: UInt8
    public var action: UInt8
    public var function: UInt8
    public var id: String { "\(side)-\(button)-\(action)" }

    public init(side: UInt8, button: UInt8, action: UInt8, function: UInt8) {
        self.side = side; self.button = button; self.action = action; self.function = function
    }

    var bytes: [UInt8] { [side, button, action, function] }
}

public struct ConnectedHost: Equatable, Sendable, Identifiable {
    public var address: String
    public var name: String
    public var state: UInt8
    public var flags: UInt8
    public var id: String { address }
    /// Per-host flag bits reported by the earbuds (bit0 = active).
    public var isActive: Bool { flags & 0x01 != 0 }
}

public struct FirmwareVersion: Equatable, Sendable {
    public var side: Int
    public var kind: Int
    public var version: String
}

// MARK: - Gesture vocabulary

public enum GestureAction {
    public static func title(_ action: UInt8) -> String {
        switch action {
        case 1: "Single tap"
        case 2: "Double tap"
        case 3: "Triple tap"
        case 4: "Touch and hold"
        case 5: "Slide"
        case 6: "Long touch and hold"
        case 7: "Slide up"
        case 8: "Slide down"
        case 11: "Touch and hold"
        case 16: "Quick squeeze"
        case 17: "Double squeeze"
        case 18: "Triple squeeze"
        case 20: "Squeeze and hold"
        default: "Gesture \(action)"
        }
    }
}

public struct GestureFunction: Hashable, Sendable, Identifiable {
    public var code: UInt8
    public var title: String
    public var id: UInt8 { code }
}

public enum GestureCatalog {
    /// Older models ("OnePlus Buds", "OnePlus Buds Z") shift previous/next down by one.
    public static func usesLegacyTrackCodes(deviceName: String) -> Bool {
        deviceName == "OnePlus Buds" || deviceName == "OnePlus Buds Z"
    }

    public static func all(legacy: Bool) -> [GestureFunction] {
        var list: [(UInt8, String)] = [
            (0, "None"), (1, "Play / Pause"), (3, "Voice assistant"),
            (legacy ? 4 : 5, "Previous track"), (legacy ? 5 : 6, "Next track"),
            (7, "Volume control"), (8, "Noise cancellation on/off"), (9, "Play favourites"),
            (10, "Switch track"), (11, "Volume up"), (12, "Volume down"), (13, "Switch devices"),
            (17, "Game mode"), (18, "Zen mode"), (22, "Add song to favourites"),
            (25, "AI summary"), (26, "Translation"), (27, "Real-time translation"),
            (28, "Reject call"), (29, "Answer / hang up"),
        ]
        if !legacy { list.append((2, "Music")) }
        return list.map { GestureFunction(code: $0.0, title: $0.1) }.sorted { $0.code < $1.code }
    }

    static let callCodes: Set<UInt8> = [0, 28, 29]
    static let mediaCodes: Set<UInt8> = [0, 1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17]

    /// Functions to offer for a slot. Slots that already hold a call function get call
    /// options, everything else gets media options. The slot's current value is always included.
    public static func options(for slot: KeyFunction, legacy: Bool, showAll: Bool) -> [GestureFunction] {
        let all = all(legacy: legacy)
        if showAll { return ensuring(slot.function, in: all) }
        let isCallSlot = slot.function == 28 || slot.function == 29
        let allowed = isCallSlot ? callCodes : mediaCodes
        return ensuring(slot.function, in: all.filter { allowed.contains($0.code) })
    }

    public static func title(for code: UInt8, legacy: Bool) -> String {
        all(legacy: legacy).first { $0.code == code }?.title ?? "Function \(code)"
    }

    private static func ensuring(_ code: UInt8, in list: [GestureFunction]) -> [GestureFunction] {
        if list.contains(where: { $0.code == code }) { return list }
        return (list + [GestureFunction(code: code, title: "Function \(code)")]).sorted { $0.code < $1.code }
    }
}
