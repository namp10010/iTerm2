#!/usr/bin/env swift
import Cocoa

// MARK: - Colour helpers
extension NSColor {
    static func hex(_ hex: String, alpha: CGFloat = 1) -> NSColor {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt32(h, radix: 16)!
        return NSColor(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat(v         & 0xFF) / 255,
            alpha: alpha)
    }
}

// MARK: - Drawing

func drawRobotIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let ref: CGFloat = 170          // reference canvas
    let sc = s / ref                // scale factor

    func scale(_ v: CGFloat) -> CGFloat { v * sc }

    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    defer { img.unlockFocus() }

    let ctx = NSGraphicsContext.current!.cgContext

    // Flip to top-left origin (NSImage is bottom-up)
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // Background
    NSColor.hex("#bcc8d8").setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: s, height: s)).fill()

    if size > 16 {
        // Ear bolts
        NSColor.hex("#a8b8cc", alpha: 0.75).setFill()
        NSBezierPath(ovalIn: CGRect(x: scale(14)-scale(7), y: scale(88)-scale(7), width: scale(14), height: scale(14))).fill()
        NSBezierPath(ovalIn: CGRect(x: scale(156)-scale(7), y: scale(88)-scale(7), width: scale(14), height: scale(14))).fill()

        // Screen panel
        NSColor.hex("#a8b8cc", alpha: 0.55).setFill()
        let screen = NSBezierPath(roundedRect: CGRect(x: scale(24), y: scale(42), width: scale(122), height: scale(88)),
                                  xRadius: scale(16), yRadius: scale(16))
        screen.fill()
    }

    if size > 32 {
        // Antenna stem
        NSColor.hex("#263e58", alpha: 0.50).setStroke()
        let stem = NSBezierPath()
        stem.move(to: CGPoint(x: scale(85), y: scale(19)))
        stem.line(to: CGPoint(x: scale(85), y: scale(42)))
        stem.lineWidth = scale(1.8)
        stem.lineCapStyle = .round
        stem.stroke()

        // Antenna ball
        NSColor.hex("#263e58", alpha: 0.50).setFill()
        NSBezierPath(ovalIn: CGRect(x: scale(85)-scale(6), y: scale(13)-scale(6), width: scale(12), height: scale(12))).fill()
    }

    // >_ glyph — centred in screen panel (or full icon if size <= 16)
    let fontSize = scale(42)
    let font = NSFont(name: "SFMono-Light", size: fontSize)
            ?? NSFont(name: "Menlo-Regular", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .light)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.hex("#1e3048", alpha: 0.80)
    ]
    let str = NSAttributedString(string: ">_", attributes: attrs)
    let textSize = str.size()

    let textOriginX: CGFloat
    let textOriginY: CGFloat
    if size <= 16 {
        textOriginX = (s - textSize.width) / 2
        textOriginY = (s - textSize.height) / 2
    } else {
        let screenMidX = scale(24) + scale(122) / 2
        let screenMidY = scale(42) + scale(88) / 2
        textOriginX = screenMidX - textSize.width / 2
        textOriginY = screenMidY - textSize.height / 2
    }
    str.draw(at: NSPoint(x: textOriginX, y: textOriginY))

    // Cursor block (full detail only)
    if size > 32 {
        NSColor.hex("#1e3048", alpha: 0.42).setFill()
        let cursor = NSBezierPath(roundedRect: CGRect(x: scale(115), y: scale(74), width: scale(14), height: scale(22)),
                                  xRadius: scale(2.5), yRadius: scale(2.5))
        cursor.fill()
    }

    return img
}

// MARK: - Export

func exportPNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// Usage: swift render-icon.swift <output-dir>
let args = CommandLine.arguments
guard args.count == 2 else {
    print("Usage: swift render-icon.swift <output-dir>")
    exit(1)
}
let outDir = args[1]
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x",  1024),
]

for (name, px) in sizes {
    let img = drawRobotIcon(size: px)
    exportPNG(img, to: "\(outDir)/\(name).png")
}
