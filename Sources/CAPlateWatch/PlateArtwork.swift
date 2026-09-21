import AppKit

/// Drawn as vectors so the small menu bar mark remains crisp on Retina displays.
enum PlateArtwork {
    enum Badge { case none, available, error }

    static func menuIcon(badge: Badge = .none) -> NSImage {
        let image = NSImage(size: NSSize(width: 30, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 27, height: 14), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            outline.stroke()
            NSColor.black.setFill()
            for x in [4.0, 25.0] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 12.5, width: 1.5, height: 1.5)).fill()
            }
            let text = badge == .none ? "CA" : (badge == .available ? "✓" : "!")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .heavy),
                .foregroundColor: NSColor.black
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: 14.5 - size.width / 2, y: 4), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CA Plate Watch"
        return image
    }

    static func plate(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let scale = rect.width / 120
            let transform = NSAffineTransform()
            transform.scaleX(by: scale, yBy: rect.height / 64)
            transform.concat()
            let plate = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 117, height: 61), xRadius: 9, yRadius: 9)
            NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
            plate.fill()
            NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.43, alpha: 1).setStroke()
            plate.lineWidth = 3
            plate.stroke()
            for x in [10.0, 107.0] {
                NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: 49, width: 3, height: 3)).fill()
            }
            drawCentered("California", y: 40, font: .systemFont(ofSize: 13, weight: .semibold), color: .systemRed)
            drawCentered("WATCH", y: 12, font: .monospacedSystemFont(ofSize: 25, weight: .bold),
                         color: NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.46, alpha: 1))
            return true
        }
    }

    private static func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = (text as NSString).size(withAttributes: attributes).width
        (text as NSString).draw(at: NSPoint(x: (120 - width) / 2, y: y), withAttributes: attributes)
    }

    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.38, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06),
                         xRadius: size * 0.19, yRadius: size * 0.19).fill()
            plate(size: NSSize(width: size * 0.78, height: size * 0.416))
                .draw(in: NSRect(x: size * 0.11, y: size * 0.292, width: size * 0.78, height: size * 0.416))
            return true
        }
    }
}
