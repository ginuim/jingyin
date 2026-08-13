import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore

    var body: some View {
        ZStack {
            AppPalette.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    hero
                    benefits
                    lifetimeCard

                    if let errorMessage = entitlements.errorMessage {
                        errorCard(errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 66)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            closeButton
        }
        .foregroundStyle(AppPalette.primaryText)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseFooter
        }
        .task {
            await entitlements.loadProduct()
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(AppPalette.surface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(AppPalette.divider, lineWidth: 1)
                        }
                }
                .foregroundStyle(AppPalette.primaryText)
                .accessibilityLabel(localization.t("export.cancel"))

                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                PaywallBadgeShape()
                    .fill(AppPalette.accent.primary)

                Image(systemName: "checkmark")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(AppPalette.accent.foreground)
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(localization.t("paywall.heroTitle"))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)

                Text(localization.t("paywall.title"))
                    .font(.title3)
                    .foregroundStyle(AppPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(AppPalette.accent.primary)
                    .frame(width: 4, height: 22)

                Text(localization.t("paywall.benefits.title"))
                    .font(.headline)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 6) {
                benefit("video.fill", "paywall.benefit.full")
                benefit("photo.fill", "paywall.benefit.quality")
                benefit("nosign", "paywall.benefit.simple")
                benefit("lock.fill", "paywall.benefit.privacy")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(
        _ systemImage: String,
        _ key: String.LocalizationValue
    ) -> some View {
        HStack(spacing: 15) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(AppPalette.accent.primary)
                .frame(width: 30)

            Text(localization.t(key))
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.divider.opacity(0.75), lineWidth: 1)
        }
    }

    private var lifetimeCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(localization.t("paywall.lifetime.title"))
                    .font(.title3.bold())

                Text(localization.t("paywall.lifetime.detail"))
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.accent.foreground)
                    .frame(width: 28, height: 28)
                    .background(AppPalette.accent.primary, in: Circle())

                priceView
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.accent.primary, lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var priceView: some View {
        if entitlements.isLoading {
            ProgressView()
                .tint(AppPalette.accent.primary)
                .frame(height: 34)
        } else if let price = entitlements.displayPrice {
            Text(price)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.accent.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            Text(localization.t("purchase.unavailable"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.disabledText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(AppPalette.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var purchaseFooter: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if entitlements.isUnlocked {
                        dismiss()
                    } else if await entitlements.purchaseLifetime() {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if entitlements.isPurchasing {
                        ProgressView()
                            .tint(AppPalette.accent.foreground)
                    } else {
                        Image(systemName: entitlements.isUnlocked ? "checkmark" : "lock.fill")
                    }

                    Text(primaryButtonTitle)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.accent.foreground)
            .background(AppPalette.accent.primary, in: Capsule())
            .disabled(isPurchaseDisabled)
            .opacity(isPurchaseDisabled ? 0.55 : 1)

            HStack(spacing: 12) {
                if !entitlements.isUnlocked {
                    Button {
                        Task {
                            if await entitlements.restorePurchases() {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if entitlements.isRestoring {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(localization.t(
                                entitlements.isRestoring
                                    ? "purchase.restore.processing"
                                    : "purchase.restore"
                            ))
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .disabled(entitlements.isPurchasing || entitlements.isRestoring)
                }

                Spacer(minLength: 4)

                Label(localization.t("paywall.appStoreSecure"), systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.disabledText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(AppPalette.elevatedSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.divider.opacity(0.7))
                .frame(height: 1)
        }
    }

    private var primaryButtonTitle: String {
        if entitlements.isUnlocked {
            return localization.t("purchase.unlocked")
        }
        if entitlements.isPurchasing {
            return localization.t("purchase.processing")
        }
        if entitlements.lifetimeProduct == nil, !entitlements.isLoading {
            return localization.t("purchase.unavailable")
        }
        return localization.t("paywall.unlockNow")
    }

    private var isPurchaseDisabled: Bool {
        if entitlements.isUnlocked {
            return false
        }
        return entitlements.isPurchasing
            || entitlements.isRestoring
            || entitlements.isLoading
            || entitlements.lifetimeProduct == nil
    }
}

/// A compact, flat seal silhouette sampled densely enough to keep the lobes smooth.
private struct PaywallBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.44
        let sampleCount = 144
        var path = Path()

        for index in 0...sampleCount {
            let progress = Double(index) / Double(sampleCount)
            let angle = progress * .pi * 2 - .pi / 2
            let ripple = 1 + 0.075 * cos(angle * 12)
            let point = CGPoint(
                x: center.x + radius * ripple * cos(angle),
                y: center.y + radius * ripple * sin(angle)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
