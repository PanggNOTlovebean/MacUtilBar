import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 64
        let transform = AffineTransform(scale: factor); (transform as NSAffineTransform).concat()
        let bg = NSBezierPath(roundedRect: NSRect(x: 3, y: 3, width: 58, height: 58), xRadius: 14, yRadius: 14)
        NSGradient(starting: NSColor(srgbRed: 0.64, green: 0.48, blue: 1, alpha: 1), ending: NSColor(srgbRed: 0.42, green: 0.25, blue: 0.84, alpha: 1))!.draw(in: bg, angle: -90)
        NSColor.white.setStroke(); NSColor.white.setFill()
        let bar = NSBezierPath(roundedRect: NSRect(x: 12, y: 20, width: 40, height: 25), xRadius: 5, yRadius: 5); bar.lineWidth = 3; bar.stroke()
        let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 26, y: 26)); arrow.line(to: NSPoint(x: 20, y: 32.5)); arrow.line(to: NSPoint(x: 26, y: 39)); arrow.lineWidth = 3; arrow.stroke()
        for x in [33, 42] { NSBezierPath(roundedRect: NSRect(x: x, y: 27, width: 5, height: 11), xRadius: 1.5, yRadius: 1.5).fill() }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
