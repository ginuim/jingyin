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

                purchaseSection

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
        .fullScreenCover(isPresented: $showPaywall) {
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
            Button(localization.t("common.ok"), role: .cancel) {}
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: entitlements.isUnlocked ? "checkmark" : "gift.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppPalette.accent.primary)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.accent.softFill, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.t(
                        entitlements.isUnlocked
                            ? "purchase.unlocked"
                            : "purchase.freePlan"
                    ))
                    .font(.headline)

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

            if !entitlements.isUnlocked {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Text(localization.t("purchase.unlock"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.accent.foreground)
                .background(AppPalette.accent.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .disabled(entitlements.isPurchasing || entitlements.isRestoring)
            }

            Divider()

            Label(localization.t("purchase.promise"), systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.t("purchase.title"))
                .font(.title3.bold())
                .padding(.horizontal, 4)

            purchaseSettings
        }
    }
}

private enum AppLinks {
    static let website = URL(string: "https://lenshide.reaidea.com")!
    static let privacyPolicy = website.appending(path: "privacy")
}
