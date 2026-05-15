//
//  MenuBarIconImageBuilder.swift
//  QuickMeeting
//
//  Created by Codex on 15.05.2026.
//

import AppKit

enum MenuBarIconImageBuilder {
    static func makeImage(for state: MenuBarIconState) -> NSImage? {
        switch state {
        case .idle:
            return baseImage()
        case .pendingAutoRecord:
            return badgedImage(badgeDiameter: 5.5, badgeColor: .systemOrange)
        case .recording:
            return badgedImage(badgeDiameter: 7, badgeColor: .systemRed)
        }
    }

    private static func baseImage() -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: "waveform.circle",
            accessibilityDescription: "QuickMeeting"
        ) else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let configuredSymbol = symbol.withSymbolConfiguration(configuration) else {
            return nil
        }

        let image = NSImage(size: configuredSymbol.size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: configuredSymbol.size)
        configuredSymbol.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func badgedImage(
        badgeDiameter: CGFloat,
        badgeColor: NSColor
    ) -> NSImage? {
        guard let image = baseImage() else {
            return nil
        }

        image.lockFocus()

        let badgeRect = NSRect(
            x: image.size.width - badgeDiameter - 1,
            y: 1,
            width: badgeDiameter,
            height: badgeDiameter
        )

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()

        badgeColor.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
