import AppKit

struct IconFile {
    let filename: String
    let pixels: Int
}

let outputDirectory = URL(fileURLWithPath: "QuickMeeting/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let iconFiles = [
    IconFile(filename: "icon_16x16.png", pixels: 16),
    IconFile(filename: "icon_16x16@2x.png", pixels: 32),
    IconFile(filename: "icon_32x32.png", pixels: 32),
    IconFile(filename: "icon_32x32@2x.png", pixels: 64),
    IconFile(filename: "icon_128x128.png", pixels: 128),
    IconFile(filename: "icon_128x128@2x.png", pixels: 256),
    IconFile(filename: "icon_256x256.png", pixels: 256),
    IconFile(filename: "icon_256x256@2x.png", pixels: 512),
    IconFile(filename: "icon_512x512.png", pixels: 512),
    IconFile(filename: "icon_512x512@2x.png", pixels: 1024),
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap")
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    guard NSGraphicsContext.current?.cgContext != nil else {
        fatalError("Missing graphics context")
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.23
    let backgroundPath = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(colors: [
        color(20, 92, 255),
        color(48, 140, 255)
    ])!
    gradient.draw(in: backgroundPath, angle: 90)

    let glowRect = canvas.insetBy(dx: size * 0.11, dy: size * 0.11)
    let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: size * 0.18, yRadius: size * 0.18)
    color(255, 255, 255, alpha: 0.08).setFill()
    glowPath.fill()

    let bubbleRect = CGRect(
        x: size * 0.185,
        y: size * 0.27,
        width: size * 0.63,
        height: size * 0.47
    )
    let bubbleRadius = size * 0.14
    let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: bubbleRadius, yRadius: bubbleRadius)

    bubblePath.move(to: CGPoint(x: size * 0.36, y: size * 0.27))
    bubblePath.line(to: CGPoint(x: size * 0.31, y: size * 0.14))
    bubblePath.line(to: CGPoint(x: size * 0.47, y: size * 0.25))
    bubblePath.close()

    color(255, 255, 255).setFill()
    bubblePath.fill()

    let barWidth = size * 0.065
    let barGap = size * 0.052
    let barsLeft = size * 0.355
    let barBottom = size * 0.405
    let barHeights: [CGFloat] = [size * 0.11, size * 0.18, size * 0.135]

    for (index, height) in barHeights.enumerated() {
        let x = barsLeft + CGFloat(index) * (barWidth + barGap)
        let barRect = CGRect(x: x, y: barBottom, width: barWidth, height: height)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        color(20, 92, 255).setFill()
        barPath.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(bitmap: NSBitmapImageRep, to url: URL, pixels: Int) throws {
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }

    try pngData.write(to: url)
    print("wrote \(pixels)x\(pixels) -> \(url.path)")
}

for icon in iconFiles {
    let image = drawIcon(size: CGFloat(icon.pixels))
    let destination = outputDirectory.appendingPathComponent(icon.filename)
    try writePNG(bitmap: image, to: destination, pixels: icon.pixels)
}
