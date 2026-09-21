import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190).fill()
        NSColor.red.setFill()
        NSBezierPath(roundedRect: NSRect(x: 180, y: 278, width: 664, height: 468), xRadius: 108, yRadius: 108).fill()
        NSColor.white.setFill()
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: 446, y: 408))
        triangle.line(to: NSPoint(x: 446, y: 616))
        triangle.line(to: NSPoint(x: 632, y: 512))
        triangle.close()
        triangle.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
