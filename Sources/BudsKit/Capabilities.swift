import Foundation

/// Command IDs (see docs/PROTOCOL.md).
public enum Command {
    public static let getCapability: UInt16 = 0x0100
    public static let getVersion: UInt16 = 0x0105
    public static let getBattery: UInt16 = 0x0106
    public static let getKeyFunction: UInt16 = 0x0108
    public static let getEarStatus: UInt16 = 0x0109
    public static let getColorID: UInt16 = 0x010B
    public static let getFeatureSwitch: UInt16 = 0x010D
    public static let getMultiConnect: UInt16 = 0x0112

    public static let getNotificationCapability: UInt16 = 0x0200
    public static let registerNotification: UInt16 = 0x0201
    public static let notificationEvent: UInt16 = 0x0204
    public static let registerMultiNotification: UInt16 = 0x0205

    public static let setKeyFunction: UInt16 = 0x0401
    public static let setSwitchFeature: UInt16 = 0x0403

    public static let deviceRequestsUTCTime: UInt16 = 0x0500
    public static let deviceFeatureSwitchSync: UInt16 = 0x0503
    public static let deviceMultiConnectChanged: UInt16 = 0x0507
}

/// Feature IDs used with getFeatureSwitch / setSwitchFeature.
public enum Feature: UInt8, CaseIterable, Sendable {
    case wearDetection = 4
    case gameMode = 6
    case vocalEnhance = 9
    case zenMode = 15
    case dualConnection = 17
    case voiceAssistant = 20
    case safeRemind = 22
    case longPowerMode = 23
    case hiQualityAudio = 24
    case spatialSound = 27
    case autoVolume = 28
    case bassEngine = 29
    case adaptiveVolume = 48
    case swiftPair = 55

    public var title: String {
        switch self {
        case .wearDetection: "In-ear detection"
        case .gameMode: "Game mode"
        case .vocalEnhance: "Vocal enhancement"
        case .zenMode: "Zen mode"
        case .dualConnection: "Dual connection"
        case .voiceAssistant: "Voice assistant"
        case .safeRemind: "Hearing safety reminder"
        case .longPowerMode: "Long battery mode"
        case .hiQualityAudio: "High-quality audio"
        case .spatialSound: "Spatial sound"
        case .autoVolume: "Auto volume"
        case .bassEngine: "Bass engine"
        case .adaptiveVolume: "Adaptive volume"
        case .swiftPair: "Swift Pair"
        }
    }
}

/// Capability bitmap: bit index → command IDs it enables.
public let capabilityTable: [[UInt16]] = [
    [261], [262], [263], [264, 1025, 1046], [265], [1024], [1026], [1027], [268, 1028], [1029],
    [1030, 271], [1031], [], [1032], [1033], [], [], [276], [], [1038, 1037, 277, 278],
    [1039], [1040, 281], [517], [3840], [], [280, 1041], [282, 1042], [284, 1043], [], [274, 1035],
    [286, 287, 1045], [1037], [], [289, 1047], [290, 1048], [1049], [285, 1044], [291, 1050], [292, 1051],
    [293, 1052, 295, 1053, 1055], [1057, 35, 36, 34, 294, 297], [61185], [61186], [61187, 1054], [1056],
    [28], [], [1058, 298], [61188], [1059, 299], [], [1060], [61190], [], [], [1061, 302, 1062], [303],
    [1063, 304], [305, 1064], [1065, 306], [20], [1069, 307], [1070], [61191], [61192, 310, 1075],
    [61193], [1073, 308], [1074, 309, 1077], [279],
]

/// Commands that are available regardless of the capability bitmap.
public let alwaysSupportedCommands: Set<UInt16> = [256, 257, 258, 259, 260, 267, 3840, 3844, 269, 3843, 262]

public struct Capabilities: Equatable, Sendable {
    public var commands: Set<UInt16>

    public init(commands: Set<UInt16>) { self.commands = commands }

    /// Parses a 0x8100 payload (status already stripped).
    public init(bitmap: [UInt8]) {
        var set = alwaysSupportedCommands
        let bits = min(bitmap.count * 8, capabilityTable.count)
        for bit in 0..<bits where bitmap[bit / 8] & (1 << (bit % 8)) != 0 {
            set.formUnion(capabilityTable[bit])
        }
        commands = set
    }

    public func supports(_ command: UInt16) -> Bool { commands.contains(command) }
}
