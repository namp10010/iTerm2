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
    let sc = s / 170            // scale from 170×170 reference canvas

    func scale(_ v: CGFloat) -> CGFloat { v * sc }

    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    defer { img.unlockFocus() }

    let ctx = NSGraphicsContext.current!.cgContext

    // Flip to top-left origin (NSImage default is bottom-up)
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // --- Background ---
    NSColor.hex("#bcc8d8").setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: s, height: s)).fill()

    // --- Ear bolts ---
    NSColor.hex("#a8b8cc", alpha: 0.75).setFill()
    NSBezierPath(ovalIn: CGRect(x: scale(7),   y: scale(81), width: scale(14), height: scale(14))).fill()
    NSBezierPath(ovalIn: CGRect(x: scale(149), y: scale(81), width: scale(14), height: scale(14))).fill()

    // --- Screen panel ---
    NSColor.hex("#a8b8cc", alpha: 0.55).setFill()
    NSBezierPath(roundedRect: CGRect(x: scale(24), y: scale(42), width: scale(122), height: scale(88)),
                 xRadius: scale(16), yRadius: scale(16)).fill()

    // --- Antenna stem + ball ---
    NSColor.hex("#263e58", alpha: 0.50).setStroke()
    let stem = NSBezierPath()
    stem.move(to: CGPoint(x: scale(85), y: scale(19)))
    stem.line(to: CGPoint(x: scale(85), y: scale(42)))
    stem.lineWidth = scale(1.8)
    stem.lineCapStyle = .round
    stem.stroke()

    NSColor.hex("#263e58", alpha: 0.50).setFill()
    NSBezierPath(ovalIn: CGRect(x: scale(79), y: scale(7), width: scale(12), height: scale(12))).fill()

    // --- >_ glyph ---
    let fontSize = scale(42)
    let font = NSFont(name: "SFMono-Light", size: fontSize)
            ?? NSFont(name: "Menlo-Regular", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .light)

    let str = NSAttributedString(string: ">_", attributes: [
        .font: font,
        .foregroundColor: NSColor.hex("#1e3048", alpha: 0.80)
    ])
    let textSize = str.size()

    // Horizontal: centre in screen panel
    let textX = scale(24) + scale(122) / 2 - textSize.width / 2

    // Vertical: centre cap height at the panel midpoint (screen y from top = scale(86)).
    // draw(at:) in normal AppKit (bottom-up) places the DESCENT LINE at the given y.
    // So: descentLine_appkit = s - (panelMidY + capHeight/2 + |descender|)
    //     → actual baseline lands at panelMidY + capHeight/2
    //     → cap height spans panelMidY ± capHeight/2  ✓
    let panelMidY     = scale(86)
    // draw(at:) in non-flipped AppKit places the descent line at the given y.
    // To land the baseline at panelMidY + capHeight/2, offset by |descender|.
    let descentAppkit = s - (panelMidY + font.capHeight / 2 + abs(font.descender))

    // Undo CTM flip for text — NSAttributedString.draw() mirrors glyphs
    // when the CTM is flipped, making _ appear above > instead of beside it.
    ctx.saveGState()
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: 0, y: -s)
    str.draw(at: NSPoint(x: textX, y: descentAppkit))
    ctx.restoreGState()

    // --- Cursor block ---
    // Spans cap-top to baseline, aligned with the text
    let cursorTop  = panelMidY - font.capHeight / 2
    let cursorLeft = textX + textSize.width + scale(2)
    NSColor.hex("#1e3048", alpha: 0.42).setFill()
    NSBezierPath(roundedRect: CGRect(x: cursorLeft, y: cursorTop,
                                     width: scale(12), height: font.capHeight),
                 xRadius: scale(2.5), yRadius: scale(2.5)).fill()

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
