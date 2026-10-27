import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius = size * 0.2237
NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()

NSGradient(
    starting: NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1),
    ending: NSColor(srgbRed: 0.06, green: 0.15, blue: 0.38, alpha: 1)
)!.draw(in: rect, angle: -90)

let configuration = NSImage.SymbolConfiguration(pointSize: 600, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "steeringwheel", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) else {
    FileHandle.standardError.write("failed to load the steeringwheel symbol\n".data(using: .utf8)!)
    exit(1)
}
symbol.draw(
    at: NSPoint(x: (size - symbol.size.width) / 2, y: (size - symbol.size.height) / 2),
    from: .zero, operation: .sourceOver, fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
