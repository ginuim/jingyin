import SwiftUI

/// Semantic colors shared by the whole app.
///
/// Keep screens coupled to these roles instead of a specific brand color so a
/// future accent experiment does not also change canvas, status, or mask colors.
enum AppPalette {
    /// The only switch needed when trying another brand accent family.
    static let accent = AccentPalette.apricotRose

    // MARK: - Backgrounds

    static let background = color(0x20201F)
    static let surface = color(0x2B2A29)
    static let elevatedSurface = color(0x373432)
    static let mediaCanvas = Color.black

    // MARK: - Content

    static let primaryText = color(0xF4F1EC)
    static let secondaryText = color(0xAAA6A1)
    static let disabledText = color(0x77736F)
    static let divider = color(0x4A4643)

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

    static let apricotRose = AccentPalette(
        primary: color(0xD58B7B),
        pressed: color(0xB96F61),
        softFill: color(0xD58B7B, opacity: 0.18),
        outline: color(0xE2A89B),
        foreground: color(0x20201F)
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
