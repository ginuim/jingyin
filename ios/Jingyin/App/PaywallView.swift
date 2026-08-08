import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(AppPalette.accent.primary)
                        .padding(22)
                        .background(AppPalette.accent.softFill, in: RoundedRectangle(cornerRadius: 24))

                    VStack(spacing: 8) {
                        Text(localization.t("paywall.title"))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(localization.t("paywall.subtitle"))
                            .foregroundStyle(AppPalette.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("film.stack", "paywall.benefit.full")
                        benefit("4k.tv", "paywall.benefit.quality")
                        benefit("hand.raised.fill", "paywall.benefit.simple")
                        benefit("lock.shield", "paywall.benefit.privacy")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18))

                    if let errorMessage = entitlements.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppPalette.destructive)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task {
                            if await entitlements.purchaseLifetime() {
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text(purchaseButtonTitle)
                                .font(.headline)
                            Text(localization.t("paywall.oneTime"))
                                .font(.caption)
                                .opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.accent.primary)
                    .foregroundStyle(AppPalette.accent.foreground)
                    .disabled(
                        entitlements.isPurchasing
                            || entitlements.isRestoring
                            || entitlements.isLoading
                            || entitlements.lifetimeProduct == nil
                    )

                    Button {
                        Task {
                            if await entitlements.restorePurchases() {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
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
                    }
                    .disabled(entitlements.isPurchasing || entitlements.isRestoring)

                    Text(localization.t("paywall.footnote"))
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .foregroundStyle(AppPalette.primaryText)
            .background(AppPalette.background)
            .navigationTitle(localization.t("purchase.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("export.cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                await entitlements.loadProduct()
            }
        }
    }

    private var purchaseButtonTitle: String {
        if entitlements.isPurchasing {
            return localization.t("purchase.processing")
        }
        guard let price = entitlements.displayPrice else {
            return localization.t("purchase.unavailable")
        }
        return localization.format("purchase.buy", price)
    }

    private func benefit(
        _ systemImage: String,
        _ key: String.LocalizationValue
    ) -> some View {
        Label(localization.t(key), systemImage: systemImage)
            .fixedSize(horizontal: false, vertical: true)
    }
}
