import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var showPaywall = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section {
                Picker(localization.t("settings.language"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(localization.t(lang.settingsTitleKey)).tag(lang)
                    }
                }
                Text(localization.t("settings.language.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(localization.t("purchase.title")) {
                LabeledContent(localization.t("purchase.status")) {
                    Label(
                        localization.t(
                            entitlements.isUnlocked
                                ? "purchase.unlocked"
                                : "purchase.freePlan"
                        ),
                        systemImage: entitlements.isUnlocked
                            ? "checkmark.seal.fill"
                            : "gift.fill"
                    )
                    .foregroundStyle(entitlements.isUnlocked ? .mint : .secondary)
                }

                if !entitlements.isUnlocked {
                    Button(localization.t("purchase.unlock")) {
                        showPaywall = true
                    }
                }

                Button(localization.t("purchase.restore")) {
                    Task {
                        let restored = await entitlements.restorePurchases()
                        restoreMessage = restored
                            ? localization.t("purchase.restore.success")
                            : entitlements.errorMessage
                                ?? localization.t("purchase.restore.none")
                    }
                }
                .disabled(entitlements.isPurchasing)

                Text(localization.t("purchase.promise"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
}
