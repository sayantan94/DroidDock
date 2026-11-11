import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.48, blue: 0.38, alpha: 1), ending: NSColor(srgbRed: 0.07, green: 0.25, blue: 0.23, alpha: 1))!.draw(in: background, angle: -65)
        NSColor(srgbRed: 0.87, green: 0.96, blue: 0.86, alpha: 1).setStroke()
        let phone = NSBezierPath(roundedRect: NSRect(x: 265, y: 260, width: 265, height: 490), xRadius: 45, yRadius: 45)
        phone.lineWidth = 26; phone.stroke()
        let speaker = NSBezierPath(); speaker.move(to: NSPoint(x: 360, y: 700)); speaker.line(to: NSPoint(x: 435, y: 700)); speaker.lineWidth = 18; speaker.lineCapStyle = .round; speaker.stroke()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 610, y: 690)); arrow.line(to: NSPoint(x: 610, y: 355))
        arrow.move(to: NSPoint(x: 535, y: 430)); arrow.line(to: NSPoint(x: 610, y: 355)); arrow.line(to: NSPoint(x: 685, y: 430))
        arrow.lineWidth = 31; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
        let dock = NSBezierPath(); dock.move(to: NSPoint(x: 550, y: 265)); dock.line(to: NSPoint(x: 735, y: 265)); dock.lineWidth = 24; dock.lineCapStyle = .round; dock.stroke()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = rep.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: output.appendingPathComponent(name))
    }
}
