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

    func x(_ v: CGFloat) -> CGFloat { v * sc }
    func y(_ v: CGFloat) -> CGFloat { v * sc }
    func r(_ v: CGFloat) -> CGFloat { v * sc }

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
        NSBezierPath(ovalIn: CGRect(x: x(14)-r(7), y: y(88)-r(7), width: r(14), height: r(14))).fill()
        NSBezierPath(ovalIn: CGRect(x: x(156)-r(7), y: y(88)-r(7), width: r(14), height: r(14))).fill()

        // Screen panel
        NSColor.hex("#a8b8cc", alpha: 0.55).setFill()
        let screen = NSBezierPath(roundedRect: CGRect(x: x(24), y: y(42), width: x(122), height: y(88)),
                                  xRadius: r(16), yRadius: r(16))
        screen.fill()
    }

    if size > 32 {
        // Antenna stem
        NSColor.hex("#263e58", alpha: 0.50).setStroke()
        let stem = NSBezierPath()
        stem.move(to: CGPoint(x: x(85), y: y(19)))
        stem.line(to: CGPoint(x: x(85), y: y(42)))
        stem.lineWidth = r(1.8)
        stem.lineCapStyle = .round
        stem.stroke()

        // Antenna ball
        NSColor.hex("#263e58", alpha: 0.50).setFill()
        NSBezierPath(ovalIn: CGRect(x: x(85)-r(6), y: y(13)-r(6), width: r(12), height: r(12))).fill()
    }

    // >_ glyph — centred in screen panel (or full icon if size <= 16)
    let fontSize = r(42)
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
        let screenMidX = x(24) + x(122) / 2
        let screenMidY = y(42) + y(88) / 2
        textOriginX = screenMidX - textSize.width / 2
        textOriginY = screenMidY - textSize.height / 2
    }
    str.draw(at: NSPoint(x: textOriginX, y: textOriginY))

    // Cursor block (full detail only)
    if size > 32 {
        NSColor.hex("#1e3048", alpha: 0.42).setFill()
        let cursor = NSBezierPath(roundedRect: CGRect(x: x(115), y: y(74), width: x(14), height: y(22)),
                                  xRadius: r(2.5), yRadius: r(2.5))
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
