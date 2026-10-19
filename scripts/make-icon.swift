// Draws the app icon (two panes on a blue tile) and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
import AppKit

let iconset = "build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Draw on a 1024-point canvas and scale to the requested size.
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    let deepBlue = NSColor(calibratedRed: 0.09, green: 0.29, blue: 0.82, alpha: 1)
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.27, green: 0.62, blue: 1, alpha: 1), ending: deepBlue)!
        .draw(in: tile, angle: -90)

    for x in [190.0, 527.0] {
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 230, width: 307, height: 520), xRadius: 40, yRadius: 40).fill()

        deepBlue.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: x + 30, y: 655, width: 247, height: 52), xRadius: 14, yRadius: 14).fill()

        deepBlue.withAlphaComponent(0.16).setFill()
        for row in 0..<5 {
            let width: Double = row % 2 == 0 ? 247 : 175
            let rect = NSRect(x: x + 30, y: 570 - Double(row) * 70, width: width, height: 36)
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
    (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x"),
]
for (pixels, name) in sizes {
    try render(pixels: pixels).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}

try FileManager.default.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
