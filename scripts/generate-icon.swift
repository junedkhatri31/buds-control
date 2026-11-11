// Draws the app icon (two earbuds on a blue squircle) and writes AppIcon.icns into the given folder.
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func earbud(at origin: NSPoint, mirrored: Bool) {
    let t = NSAffineTransform()
    t.translateX(by: origin.x, yBy: origin.y)
    if mirrored { t.scaleX(by: -1, yBy: 1) }
    NSGraphicsContext.saveGraphicsState()
    t.concat()
    // Bud head.
    let head = NSBezierPath(ovalIn: NSRect(x: -95, y: 60, width: 190, height: 190))
    NSColor.white.withAlphaComponent(0.96).setFill(); head.fill()
    // Speaker tip.
    let tip = NSBezierPath(ovalIn: NSRect(x: 40, y: 120, width: 90, height: 90))
    NSColor(white: 0.86, alpha: 1).setFill(); tip.fill()
    // Stem.
    let stem = NSBezierPath(roundedRect: NSRect(x: -70, y: -230, width: 72, height: 330), xRadius: 36, yRadius: 36)
    NSColor.white.withAlphaComponent(0.96).setFill(); stem.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let rect = NSRect(x: 90, y: 90, width: 844, height: 844)
    let background = NSBezierPath(roundedRect: rect, xRadius: 188, yRadius: 188)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -15)
    shadow.set()
    NSGradient(starting: NSColor(red: 0.27, green: 0.55, blue: 0.98, alpha: 1),
               ending: NSColor(red: 0.12, green: 0.25, blue: 0.70, alpha: 1))!.draw(in: background, angle: -90)
    NSShadow().set()
    NSColor.white.withAlphaComponent(0.2).setStroke()
    background.lineWidth = 3
    background.stroke()
    earbud(at: NSPoint(x: 360, y: 520), mirrored: false)
    earbud(at: NSPoint(x: 664, y: 520), mirrored: true)
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    // Render at precisely the requested pixel dimensions, independent of the display scale.
    let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: result)
    NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: size, height: size))
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return result.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
