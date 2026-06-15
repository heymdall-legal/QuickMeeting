//
//  MenuBarIconImageBuilder.swift
//  QuickMeeting
//

import AppKit

enum MenuBarIconImageBuilder {
    private struct SVGBar {
        let x, y, w, h: CGFloat
    }

    // SVG bar definitions — viewBox 0 0 28 26
    private static let svgBars: [SVGBar] = [
        SVGBar(x: 2.5, y: 8,  w: 3, h: 10),
        SVGBar(x: 7.5, y: 5,  w: 3, h: 16),
        SVGBar(x: 12.5, y: 2, w: 3, h: 22),
        SVGBar(x: 17.5, y: 5, w: 3, h: 16),
        SVGBar(x: 22.5, y: 8, w: 3, h: 10),
    ]

    static func makeImage(for state: MenuBarIconState) -> NSImage {
        switch state {
        case .idle:             return waveformImage()
        case .pendingAutoRecord: return detectedImage()
        case .recording:        return recordingImage()
        }
    }

    // Reusable in the panel header (template image, renders in foreground color)
    static func waveformImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 16))
        image.lockFocus()
        drawBars(svgW: 28, svgH: 26, ptW: 17, ptH: 16)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func detectedImage() -> NSImage {
        let svgW: CGFloat = 32, svgH: CGFloat = 26
        let ptW:  CGFloat = 20, ptH:  CGFloat = 16
        let image = NSImage(size: NSSize(width: ptW, height: ptH))
        image.lockFocus()

        drawBars(svgW: svgW, svgH: svgH, ptW: ptW, ptH: ptH)

        // Ring: SVG cx=28, cy=5.5, r=2.7, stroke-width=1.8
        let sx = ptW / svgW, sy = ptH / svgH
        let scale = min(sx, sy)
        let cgCX = 28 * sx
        let cgCY = (svgH - 5.5) * sy
        let cgR  = 2.7 * scale
        let ring = NSBezierPath(ovalIn: NSRect(x: cgCX - cgR, y: cgCY - cgR, width: cgR * 2, height: cgR * 2))
        ring.lineWidth = 1.8 * scale
        NSColor.black.setStroke()
        ring.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func recordingImage() -> NSImage {
        let pt: CGFloat = 16
        let image = NSImage(size: NSSize(width: pt, height: pt))
        image.lockFocus()
        // Terracotta #c0573f
        let r2: CGFloat = 192.0 / 255.0
        let g2: CGFloat = 87.0 / 255.0
        let b2: CGFloat = 63.0 / 255.0
        NSColor(srgbRed: r2, green: g2, blue: b2, alpha: 1.0).setFill()
        let r: CGFloat = 6.5
        NSBezierPath(ovalIn: NSRect(x: pt/2 - r, y: pt/2 - r, width: r * 2, height: r * 2)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // Draws the 5 waveform bars in CG coordinate space (Y-up from bottom-left).
    private static func drawBars(svgW: CGFloat, svgH: CGFloat, ptW: CGFloat, ptH: CGFloat) {
        let sx = ptW / svgW
        let sy = ptH / svgH
        let rx = 1.5 * min(sx, sy)
        NSColor.black.setFill()
        for bar in svgBars {
            let rect = NSRect(
                x: bar.x * sx,
                y: (svgH - bar.y - bar.h) * sy,  // flip Y: SVG origin is top-left, CG is bottom-left
                width: bar.w * sx,
                height: bar.h * sy
            )
            NSBezierPath(roundedRect: rect, xRadius: rx, yRadius: rx).fill()
        }
    }
}
