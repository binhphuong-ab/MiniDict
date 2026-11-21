import AppKit

// Renders the app icon from an SF Symbol into an .iconset directory.
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
    let copy = symbol.copy() as! NSImage
    copy.lockFocus()
    color.set()
    NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
    copy.unlockFocus()
    return copy
}

func render(_ px: Int) -> Data? {
    let side = CGFloat(px)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    let plate = NSRect(x: side * 0.055, y: side * 0.055, width: side * 0.89, height: side * 0.89)
    let path = NSBezierPath(roundedRect: plate, xRadius: side * 0.22, yRadius: side * 0.22)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.47, blue: 0.85, alpha: 1),
                              ending: NSColor(srgbRed: 0.06, green: 0.13, blue: 0.33, alpha: 1))
    gradient?.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let white = tinted(symbol, .white)
        let size = white.size
        let origin = NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
        white.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: side, height: side)
    return rep.representation(using: .png, properties: [:])
}

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in variants {
    guard let data = render(px) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png"))
}
print("iconset written to \(outputDir)")
