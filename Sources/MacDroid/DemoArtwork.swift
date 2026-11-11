import AppKit

/// Original vector landscapes for the explicit --demo development mode.
/// These never appear in a real phone library.
enum DemoArtwork {
    static func landscape(index: Int) -> NSImage {
        NSImage(size: NSSize(width: 600, height: 440), flipped: false) { rect in
            let palettes: [[NSColor]] = [
                [hex(0xE7D5BC), hex(0xEBC283), hex(0x889D94), hex(0x486D64)],
                [hex(0xD1E4E4), hex(0xF3DD9D), hex(0x6A9AAB), hex(0x345B73)],
                [hex(0xECD8CF), hex(0xD88260), hex(0xBA8F86), hex(0x6F6A79)],
                [hex(0xDDE5D7), hex(0xFBEDBD), hex(0x90A184), hex(0x465C50)],
                [hex(0xC9D8E3), hex(0xF2E4CB), hex(0x8294AA), hex(0x4A586F)],
                [hex(0xF1DBB7), hex(0xFFF1D2), hex(0xD5AB75), hex(0x9C795E)]
            ]
            let colors = palettes[index % palettes.count]
            colors[0].setFill(); rect.fill()
            colors[1].setFill()
            let sunX = CGFloat(85 + (index * 77) % 350)
            NSBezierPath(ovalIn: NSRect(x: sunX, y: 280, width: 78, height: 78)).fill()
            for layer in 0..<3 {
                colors[min(layer + 2, 3)].withAlphaComponent(layer == 1 ? 0.55 : 1).setFill()
                let path = NSBezierPath()
                path.move(to: .zero)
                path.line(to: NSPoint(x: 0, y: 190 - layer * 55))
                path.curve(to: NSPoint(x: 600, y: 240 - layer * 65),
                           controlPoint1: NSPoint(x: 140, y: 350 - layer * 90 + (index % 3) * 25),
                           controlPoint2: NSPoint(x: 380, y: 40 + layer * 20))
                path.line(to: NSPoint(x: 600, y: 0)); path.close(); path.fill()
            }
            return true
        }
    }
    private static func hex(_ value: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
