// Normalize the generated transparent cutout and derive native macOS icon sizes.
import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let input = root.appendingPathComponent("materials/portrait-cutout.png")
let data = try Data(contentsOf: input)
let bitmap = NSBitmapImageRep(data: data)!
// Find significant opaque content, ignoring isolated transparent-edge speckles.
var minX = bitmap.pixelsWide, maxX = 0, minY = bitmap.pixelsHigh, maxY = 0
for y in 0..<bitmap.pixelsHigh {
    var count = 0, rowMin = bitmap.pixelsWide, rowMax = 0
    for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
        count += 1; rowMin = min(rowMin, x); rowMax = max(rowMax, x)
    }
    if count >= 20 { minX = min(minX, rowMin); maxX = max(maxX, rowMax); minY = min(minY, y); maxY = max(maxY, y) }
}
let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let crop = bitmap.cgImage!.cropping(to: bounds)!
let portrait = NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
func writePNG(_ image: NSImage, _ url: URL) throws {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
// A small transparent inset keeps all four corners transparent in the app asset.
let padded = NSImage(size: NSSize(width: crop.width + 24, height: crop.height + 24))
padded.lockFocus()
portrait.draw(in: NSRect(x: 12, y: 12, width: crop.width, height: crop.height))
padded.unlockFocus()
try writePNG(padded, root.appendingPathComponent("Assets/face.png"))
let iconset = root.appendingPathComponent("tmp/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let icon = NSImage(size: NSSize(width: pixels, height: pixels))
        icon.lockFocus()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pixels, height: pixels), xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22).fill()
        let margin = CGFloat(pixels) * 0.06
        let factor = min((CGFloat(pixels) - margin * 2) / portrait.size.width, (CGFloat(pixels) - margin * 2) / portrait.size.height)
        let size = NSSize(width: portrait.size.width * factor, height: portrait.size.height * factor)
        portrait.draw(in: NSRect(x: (CGFloat(pixels) - size.width) / 2, y: margin, width: size.width, height: size.height))
        icon.unlockFocus()
        try writePNG(icon, iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
print("Portrait crop \(bounds); face and iconset written")
