import AppKit
import SwiftUI

/// Dock / ⌘-Tab presence and Dock-icon clicks.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showInDockKey = "showInDock"

    /// Set by a view that's always alive (the menu-bar label) so AppKit callbacks can open SwiftUI windows.
    static var openWindow: OpenWindowAction?

    static var showInDock: Bool {
        UserDefaults.standard.object(forKey: showInDockKey) as? Bool ?? true
    }

    /// Regular apps appear in the Dock and ⌘-Tab; accessory apps live only in the menu bar.
    static func applyDockPreference() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !Self.showInDock { NSApp.setActivationPolicy(.accessory) }
    }

    /// Clicking the Dock icon with no window open shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.openWindow?(id: "main") }
        return true
    }

    /// Closing the settings window keeps the menu-bar app running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
