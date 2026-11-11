import AppKit
import BudsKit

/// `BudsControl --selftest`: connects to the first compatible earbuds, prints what it reads,
/// performs reversible writes, then exits. Used to verify the app against real hardware.
@MainActor
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }

    static func run(_ manager: BudsManager) async {
        func out(_ s: String) { print(s); fflush(stdout) }
        manager.start()
        var device: BudsDevice?
        for _ in 0..<40 {
            if let d = manager.devices.first(where: { $0.linkState == .connected }), !d.busy { device = d; break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Wait for the initial sync to finish.
        for _ in 0..<40 where device?.keyFunctions.isEmpty ?? false { try? await Task.sleep(for: .milliseconds(250)) }
        guard let device else {
            out("FAIL no connected earbuds; devices=\(manager.devices.map { "\($0.name) \($0.linkState)" })")
            exit(1)
        }
        out("device: \(device.name) [\(device.id)]")
        out("capabilities: \(device.capabilities.commands.count) commands")
        out("battery: " + device.battery.map { "\(BudSide(rawValue: $0.side)?.title ?? "\($0.side)")=\($0.percent)%\($0.charging ? "⚡" : "")" }.joined(separator: " "))
        out("ear status: " + device.earStatus.map { "\($0.side): inCase=\($0.inCase) inEar=\($0.inEar)" }.joined(separator: ", "))
        out("firmware: " + device.versions.map { "\($0.side)=\($0.version)" }.joined(separator: " "))
        out("dual connection supported=\(device.supportsDualConnection) enabled=\(device.dualConnectionEnabled)")
        out("hosts: " + device.hosts.map { "\($0.name) (\($0.address)) flags=\($0.flags)" }.joined(separator: ", "))
        out("key functions (\(device.keyFunctions.count)):")
        for k in device.keyFunctions {
            out("  side=\(k.side) button=\(k.button) \(GestureAction.title(k.action)): \(GestureCatalog.title(for: k.function, legacy: device.usesLegacyTrackCodes))")
        }

        var failures = 0
        // Reversible write 1: set dual connection to its current value.
        if device.supportsDualConnection {
            let current = device.dualConnectionEnabled
            await device.setFeature(.dualConnection, enabled: current)
            let ok = device.lastError == nil && device.dualConnectionEnabled == current
            out("\(ok ? "PASS" : "FAIL") setSwitchFeature(dual=\(current)) error=\(device.lastError ?? "none")")
            if !ok { failures += 1 }
        }
        // Reversible write 2: change one media gesture slot and restore it.
        if let slot = device.keyFunctions.first(where: { $0.function != 28 && $0.function != 29 }) {
            let original = slot.function
            let probe: UInt8 = original == 1 ? 0 : 1
            await device.setKeyFunction(slot, function: probe)
            let changed = device.keyFunctions.first { $0.id == slot.id }?.function
            out("\(changed == probe ? "PASS" : "FAIL") setKeyFunction \(slot.id) \(original)→\(probe) readback=\(changed.map(String.init) ?? "nil") error=\(device.lastError ?? "none")")
            if changed != probe { failures += 1 }
            await device.setKeyFunction(slot, function: original)
            let restored = device.keyFunctions.first { $0.id == slot.id }?.function
            out("\(restored == original ? "PASS" : "FAIL") restore \(slot.id) →\(original) readback=\(restored.map(String.init) ?? "nil")")
            if restored != original { failures += 1 }
        }
        device.disconnect()
        out(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
