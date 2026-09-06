import SwiftUI

/// The three shared button treatments used by primary app flows.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(AppPalette.accent.foreground)
            .background(
                configuration.isPressed ? AppPalette.accent.pressed : AppPalette.accent.primary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(AppPalette.primaryText)
            .background(
                configuration.isPressed ? AppPalette.elevatedSurface : AppPalette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppPalette.divider, lineWidth: 1)
            }
    }
}

struct TextButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .foregroundStyle(role == .destructive ? AppPalette.destructive : AppPalette.accent.primary)
            .opacity(configuration.isPressed ? 0.62 : 1)
    }
}
