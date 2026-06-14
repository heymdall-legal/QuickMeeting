//
//  QuickMeetingTheme.swift
//  QuickMeeting
//
//  Design tokens for the "soft warm paper + sage" look exported from
//  Claude Design (QuickMeeting.dc.html). One window, light only.
//

import SwiftUI

extension Color {
    /// Creates a color from a `#rrggbb` (or `#rrggbbaa`) hex string.
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)

        let r, g, b, a: Double
        switch raw.count {
        case 8:
            r = Double((value >> 24) & 0xff) / 255
            g = Double((value >> 16) & 0xff) / 255
            b = Double((value >> 8) & 0xff) / 255
            a = Double(value & 0xff) / 255
        default:
            r = Double((value >> 16) & 0xff) / 255
            g = Double((value >> 8) & 0xff) / 255
            b = Double(value & 0xff) / 255
            a = 1
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Centralised palette + helpers for the QuickMeeting redesign.
enum QMTheme {
    // Surfaces
    static let appBackground = Color(hex: "#faf8f3")
    static let detailBackground = Color(hex: "#faf8f3")
    static let sidebar = Color(hex: "#f4f1ea")
    static let titleBar = Color(hex: "#f4f1ea")
    static let card = Color(hex: "#ffffff")
    static let chip = Color(hex: "#f1ede4")
    static let searchField = Color(hex: "#ece8df")
    static let selectedRow = Color(hex: "#e3e9e3")
    static let sheetBackground = Color(hex: "#fbfaf6")

    // Hairlines / borders
    static let hairline = Color(hex: "#e6e0d4")
    static let cardBorder = Color(hex: "#ece6d9")
    static let fieldBorder = Color(hex: "#e0dacd")
    static let popoverBorder = Color(hex: "#e3ddcf")

    // Text
    static let ink = Color(hex: "#2c2a26")
    static let body = Color(hex: "#3a382f")
    static let secondary = Color(hex: "#6e685e")
    static let tertiary = Color(hex: "#8a847a")
    static let muted = Color(hex: "#a8a299")
    static let faint = Color(hex: "#b3aca0")

    // Accents
    static let sage = Color(hex: "#5b7a6b")
    static let sageHover = Color(hex: "#4f6c5e")
    static let recording = Color(hex: "#c0573f")
    static let transcribing = Color(hex: "#b07c52")
    static let recordedDot = Color(hex: "#cfc8ba")
    static let danger = Color(hex: "#b06a5a")

    static let appFont = Font.system(.body, design: .default)
}

/// A speaker's identity color (used for the name) and bubble tint.
struct QMSpeakerStyle: Equatable {
    let color: Color
    let tint: Color
}

enum QMSpeakerPalette {
    /// Named speakers from the design get hand-tuned pairs; everyone else is
    /// assigned deterministically from the same harmonious palette.
    private static let named: [String: (String, String)] = [
        "marcus lee": ("#5b7a6b", "#eef2ef"),
        "priya shah": ("#9a6b86", "#f4eef1"),
        "dana okafor": ("#b07c52", "#f5ede4"),
        "riley chen": ("#6f7c9c", "#eef0f5"),
        "you": ("#7d8a52", "#f1f3e8"),
    ]

    private static let rotation: [(String, String)] = [
        ("#5b7a6b", "#eef2ef"),
        ("#9a6b86", "#f4eef1"),
        ("#b07c52", "#f5ede4"),
        ("#6f7c9c", "#eef0f5"),
        ("#7d8a52", "#f1f3e8"),
        ("#a8694e", "#f5ece6"),
        ("#6b8a86", "#eaf1f0"),
    ]

    private static let unknown = QMSpeakerStyle(color: Color(hex: "#b3ab9e"), tint: Color(hex: "#f2efe9"))

    /// `true` for placeholder labels like "Speaker 1" that have not been named.
    static func isUnnamed(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.range(of: "^speaker", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func style(for name: String, key: String? = nil) -> QMSpeakerStyle {
        if isUnnamed(name) {
            return unknown
        }

        let lookup = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let pair = named[lookup] {
            return QMSpeakerStyle(color: Color(hex: pair.0), tint: Color(hex: pair.1))
        }

        let seed = key ?? lookup
        var hash = 0
        for scalar in seed.unicodeScalars {
            hash = (hash &+ Int(scalar.value)) % 997
        }
        let pair = rotation[hash % rotation.count]
        return QMSpeakerStyle(color: Color(hex: pair.0), tint: Color(hex: pair.1))
    }
}

/// Static sine-based waveform bar heights, matching the design's generator.
enum QMWaveform {
    static let heights: [CGFloat] = {
        (0..<74).map { i in
            let base = abs(sin(Double(i) * 0.55) * 0.62 + sin(Double(i) * 0.21) * 0.48 + sin(Double(i) * 1.3) * 0.22)
            return CGFloat(min(30, 4 + Int((base * 26).rounded())))
        }
    }()
}
