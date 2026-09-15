import AppKit
let destination = CommandLine.arguments[1]
let size: CGFloat = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.04, green: 0.055, blue: 0.09, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.40, alpha: 1), ending: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.09, alpha: 1))!
gradient.draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)), angle: -50)
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 512, y: 512)
context.rotate(by: .pi / 7)
NSColor(calibratedRed: 0.30, green: 0.62, blue: 1.0, alpha: 1).setFill()
func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
}
round(-280, -35, 560, 70, 25)
round(-237, -190, 95, 380, 31)
round(142, -190, 95, 380, 31)
round(-322, -118, 64, 236, 23)
round(258, -118, 64, 236, 23)
NSColor(calibratedRed: 0.68, green: 0.89, blue: 0.47, alpha: 1).setFill()
round(-46, -35, 92, 70, 0)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
