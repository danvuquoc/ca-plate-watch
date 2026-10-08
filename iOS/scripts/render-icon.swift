import AppKit

@main
struct RenderIcon {
    static func main() throws {
        let size = 1024
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.38, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        PlateArtwork.plate(size: NSSize(width: 820, height: 437))
            .draw(in: NSRect(x: 102, y: 294, width: 820, height: 437))
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
