import SwiftUI

/// Semantic colors shared by the whole app.
///
/// Keep screens coupled to these roles instead of a specific brand color so a
/// future accent experiment does not also change canvas, status, or mask colors.
enum AppPalette {
    /// The only switch needed when trying another brand accent family.
    static let accent = AccentPalette.signalOrange

    // MARK: - Backgrounds

    static let background = color(0x1C1614)
    static let surface = color(0x2A211E)
    static let elevatedSurface = color(0x3A2C27)
    static let mediaCanvas = Color.black

    // MARK: - Content

    static let primaryText = color(0xFFF4EE)
    static let secondaryText = color(0xC2A89C)
    static let disabledText = color(0x8A7368)
    static let divider = color(0x5A433A)

    // MARK: - Feedback

    static let warning = color(0xD59A3A)
    static let destructive = color(0xC95D58)
    static let success = color(0x78A985)

    // MARK: - Media overlays

    /// Media annotations must remain legible regardless of the selected accent.
    static let maskOutline = Color.white
    static let maskOutlineShadow = Color.black.opacity(0.85)
    static let mediaScrim = Color.black.opacity(0.62)

    private static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct AccentPalette {
    let primary: Color
    let pressed: Color
    let softFill: Color
    let outline: Color
    let foreground: Color

    /// Soft peach leftover from earlier brand trials; kept for A/B switching.
    static let apricotRose = AccentPalette(
        primary: color(0xD58B7B),
        pressed: color(0xB96F61),
        softFill: color(0xD58B7B, opacity: 0.18),
        outline: color(0xE2A89B),
        foreground: color(0x20201F)
    )

    /// Brand orange sampled from the 2026-08-08 privacy character icon.
    static let signalOrange = AccentPalette(
        primary: color(0xE83810),
        pressed: color(0xC0280C),
        softFill: color(0xE83810, opacity: 0.20),
        outline: color(0xF77937),
        foreground: color(0xFFF7F2)
    )

    private static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
