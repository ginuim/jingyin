import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    navigationBar
                    hero
                    benefitsCard
                    purchaseButton

                    if let errorMessage = entitlements.errorMessage {
                        errorCard(errorMessage)
                    }

                    restoreButton
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 12))
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(AppPalette.primaryText)
        .background(AppPalette.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await entitlements.loadProduct()
        }
    }

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text(localization.t("paywall.close"))
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(TextButtonStyle())

            Spacer()

            Text(localization.t("purchase.title"))
            .font(.headline)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppPalette.accent.softFill.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppPalette.divider.opacity(0.45), lineWidth: 1)
                    }

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppPalette.accent.primary)
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)

            Text(localization.t("paywall.title"))
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(.top, 30)

            Text(localization.t("paywall.subtitle"))
                .font(.body)
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefitsCard: some View {
        VStack(spacing: 0) {
            benefit("film.stack", "paywall.benefit.full")
            benefitDivider
            benefit("rectangle.stack.badge.plus", "paywall.benefit.quality")
            benefitDivider
            benefit("hand.raised.fill", "paywall.benefit.simple")
            benefitDivider
            benefit("lock.shield", "paywall.benefit.privacy")
        }
        .padding(16)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppPalette.divider.opacity(0.5), lineWidth: 1)
        }
    }

    private var benefitDivider: some View {
        Rectangle()
            .fill(AppPalette.divider.opacity(0.34))
            .frame(height: 1)
            .padding(.leading, 47)
    }

    private func benefit(
        _ systemImage: String,
        _ key: String.LocalizationValue
    ) -> some View {
        HStack(spacing: 15) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppPalette.primaryText)
                .frame(width: 32)

            Text(localization.t(key))
                .font(.subheadline)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    }

    private var purchaseButton: some View {
        Button {
            Task {
                if entitlements.isUnlocked {
                    dismiss()
                } else if await entitlements.purchaseLifetime() {
                    dismiss()
                }
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 9) {
                    if entitlements.isPurchasing {
                        ProgressView()
                            .tint(AppPalette.accent.foreground)
                    }

                    Text(primaryButtonTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                if !entitlements.isUnlocked {
                    Text(localization.t("paywall.oneTime"))
                        .font(.footnote)
                        .opacity(0.82)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isPurchaseDisabled)
        .opacity(isPurchaseDisabled ? 0.55 : 1)
    }

    @ViewBuilder
    private var restoreButton: some View {
        if !entitlements.isUnlocked {
            Button {
                Task {
                    if await entitlements.restorePurchases() {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
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
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
            .buttonStyle(TextButtonStyle())
            .disabled(entitlements.isPurchasing || entitlements.isRestoring)
        }
    }

    private var footnote: some View {
        Text(localization.t("paywall.footnote"))
            .font(.footnote)
            .foregroundStyle(AppPalette.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(AppPalette.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var primaryButtonTitle: String {
        if entitlements.isUnlocked {
            return localization.t("purchase.unlocked")
        }
        if entitlements.isPurchasing {
            return localization.t("purchase.processing")
        }
        if !entitlements.canPresentPurchase, !entitlements.isLoading {
            return localization.t("purchase.unavailable")
        }
        if let price = entitlements.displayPrice {
            return localization.format("purchase.buy", price)
        }
        return localization.t("paywall.unlockNow")
    }

    private var isPurchaseDisabled: Bool {
        if entitlements.isUnlocked {
            return false
        }
        return entitlements.isPurchasing
            || entitlements.isRestoring
            || !entitlements.canPresentPurchase
    }
}
