import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icons: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in icons {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18).fill()

    let pageRect = NSRect(x: size * 0.19, y: size * 0.13, width: size * 0.62, height: size * 0.74)
    NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: pageRect, xRadius: size * 0.06, yRadius: size * 0.06).fill()

    NSColor(calibratedRed: 0.11, green: 0.56, blue: 0.76, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: pageRect.minX, y: pageRect.maxY - size * 0.2, width: pageRect.width, height: size * 0.16)).fill()

    let paragraphColor = NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.31, alpha: 1)
    paragraphColor.setFill()
    for index in 0..<4 {
        let y = pageRect.minY + size * (0.2 + CGFloat(index) * 0.105)
        let width = pageRect.width * (index == 2 ? 0.56 : 0.72)
        NSBezierPath(roundedRect: NSRect(x: pageRect.minX + size * 0.08, y: y, width: width, height: max(1.5, size * 0.018)), xRadius: size * 0.01, yRadius: size * 0.01).fill()
    }

    let text = "MD" as NSString
    let fontSize = size * 0.22
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .black),
        .foregroundColor: NSColor.white
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: pageRect.maxY - size * 0.16), withAttributes: attributes)

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Could not render \(name)")
    }

    try png.write(to: outputURL.appendingPathComponent(name))
}
