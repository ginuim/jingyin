import SwiftUI

struct PurchaseStatusCard: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore

    let onUnlock: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entitlements.isUnlocked ? "checkmark.seal.fill" : "gift.fill")
                .font(.title2)
                .foregroundStyle(AppPalette.accent.primary)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    localization.t(
                        entitlements.isUnlocked
                            ? "purchase.unlocked"
                            : "purchase.freePlan"
                    )
                )
                .font(.headline)
                .foregroundStyle(AppPalette.accent.primary)

                Text(
                    localization.t(
                        entitlements.isUnlocked
                            ? "purchase.unlocked.detail"
                            : "purchase.freePlan.detail"
                    )
                )
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !entitlements.isUnlocked {
                Button(localization.t("purchase.unlock"), action: onUnlock)
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.accent.primary)
                    .foregroundStyle(AppPalette.accent.foreground)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.accent.softFill, in: RoundedRectangle(cornerRadius: 18))
    }
}
