import AppKit

/// `BudsControl --show-window --snapshot <dir>`: after the UI settles, writes a PNG of each
/// of the app's visible windows into <dir>. Debug aid; needs no screen-recording permission.
@MainActor
enum Snapshot {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func scheduleIfRequested() {
        guard let dir = directory else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window.title.isEmpty ? "window-\(index)" : window.title.replacingOccurrences(of: " ", with: "-")
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(name).png"))
            }
            print("snapshots written to \(dir.path)")
            exit(0)
        }
    }
}
