import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager

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
        }
        .navigationTitle(localization.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
