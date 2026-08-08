import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var showPaywall = false
    @State private var restoreMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            Text(localization.t("settings.language"))
                                .font(.headline)

                            Spacer(minLength: 12)

                            Picker(
                                localization.t("settings.language"),
                                selection: $localization.language
                            ) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(localization.t(lang.settingsTitleKey)).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .tint(AppPalette.accent.primary)
                        }

                        Divider()

                        Text(localization.t("settings.language.note"))
                            .font(.footnote)
                            .foregroundStyle(AppPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsSection(localization.t("purchase.title")) {
                    purchaseSettings
                }

                settingsSection(localization.t("settings.information")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Link(destination: AppLinks.website) {
                            Label(localization.t("settings.website"), systemImage: "globe")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        Link(destination: AppLinks.privacyPolicy) {
                            Label(
                                localization.t("settings.privacyPolicy"),
                                systemImage: "hand.raised.fill"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .foregroundStyle(AppPalette.primaryText)
        .background(AppPalette.background)
        .tint(AppPalette.accent.primary)
        .navigationTitle(localization.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(localization)
                .environmentObject(entitlements)
        }
        .alert(
            localization.t("purchase.restore"),
            isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 4)

            settingsCard(content: content)
        }
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var purchaseSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: entitlements.isUnlocked ? "checkmark.seal.fill" : "gift.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppPalette.accent.foreground)
                    .frame(width: 46, height: 46)
                    .background(
                        AppPalette.accent.primary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.t(
                        entitlements.isUnlocked
                            ? "purchase.unlocked"
                            : "purchase.freePlan"
                    ))
                    .font(.headline)
                    .foregroundStyle(AppPalette.accent.primary)

                    Text(localization.t(
                        entitlements.isUnlocked
                            ? "purchase.unlocked.detail"
                            : "purchase.freePlan.detail"
                    ))
                    .font(.footnote)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppPalette.accent.softFill,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppPalette.accent.outline.opacity(0.35), lineWidth: 1)
            }

            if !entitlements.isUnlocked {
                Button(localization.t("purchase.unlock")) {
                    showPaywall = true
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.accent.primary)
                .foregroundStyle(AppPalette.accent.foreground)
                .controlSize(.large)
                .disabled(entitlements.isRestoring)

                Button {
                    Task {
                        let restored = await entitlements.restorePurchases()
                        restoreMessage = restored
                            ? localization.t("purchase.restore.success")
                            : entitlements.errorMessage
                                ?? localization.t("purchase.restore.none")
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
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(entitlements.isPurchasing || entitlements.isRestoring)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(AppPalette.accent.primary)
                Text(localization.t("purchase.promise"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(AppPalette.secondaryText)
        }
    }
}

private enum AppLinks {
    static let website = URL(string: "https://lenshide.reaidea.com")!
    static let privacyPolicy = website.appending(path: "privacy")
}
