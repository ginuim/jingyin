import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case zhHant
    case en
    case ja

    var id: String { rawValue }

    var settingsTitleKey: String.LocalizationValue {
        switch self {
        case .system: "settings.language.system"
        case .zhHans: "settings.language.zhHans"
        case .zhHant: "settings.language.zhHant"
        case .en: "settings.language.en"
        case .ja: "settings.language.ja"
        }
    }
}

#if DEBUG
enum LocalizationResolverSmoke {
    static func run() {
        let cases: [(AppLanguage, [String], String)] = [
            (.en, ["ko-KR"], "en"),
            (.system, ["ko-KR"], "en"),
            (.system, ["zh-Hant-TW"], "zh-Hant"),
            (.system, ["zh-Hans-CN"], "zh-Hans"),
            (.system, ["zh-HK"], "zh-Hant"),
            (.system, ["ja-JP"], "ja"),
            (.system, ["fr-FR"], "en"),
            (.system, [], "en"),
            (.ja, ["en"], "ja"),
            (.zhHans, ["ja"], "zh-Hans"),
            (.zhHant, ["en"], "zh-Hant"),
        ]
        for (pref, langs, expected) in cases {
            let got = LocalizationManager.resolveLanguageCode(
                preference: pref,
                preferredLanguages: langs
            )
            precondition(got == expected, "\(pref) \(langs) -> \(got) expected \(expected)")
        }
    }
}
#endif

@MainActor
final class LocalizationManager: ObservableObject {
    static let storageKey = "jingyin.appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            refreshBundle()
        }
    }

    @Published private(set) var effectiveLanguageCode: String
    @Published private(set) var bundle: Bundle

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        let raw = defaults.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        let initial = AppLanguage(rawValue: raw) ?? .system
        let code = Self.resolveLanguageCode(
            preference: initial,
            preferredLanguages: preferredLanguages
        )
        self.language = initial
        self.effectiveLanguageCode = code
        self.bundle = Self.bundle(for: code)
    }

    func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle)
    }

    func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let template = String(localized: key, bundle: bundle)
        return String(format: template, locale: Locale(identifier: effectiveLanguageCode), arguments: arguments)
    }

    func refreshFromSystemIfNeeded() {
        guard language == .system else { return }
        refreshBundle()
    }

    private func refreshBundle() {
        let code = Self.resolveLanguageCode(
            preference: language,
            preferredLanguages: Locale.preferredLanguages
        )
        effectiveLanguageCode = code
        bundle = Self.bundle(for: code)
    }

    /// Resolve mapping:
    /// preference override → fixed code;
    /// system + zh-Hans*/zh-CN → zh-Hans;
    /// system + zh-Hant*/zh-TW/HK/MO → zh-Hant;
    /// system + bare zh → zh-Hans;
    /// system + ja* → ja; en* → en; else → en.
    static func resolveLanguageCode(
        preference: AppLanguage,
        preferredLanguages: [String]
    ) -> String {
        switch preference {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en: return "en"
        case .ja: return "ja"
        case .system:
            guard let raw = preferredLanguages.first else { return "en" }
            let lower = raw.lowercased()
            if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") {
                return "zh-Hans"
            }
            if lower.hasPrefix("zh-hant")
                || lower.hasPrefix("zh-tw")
                || lower.hasPrefix("zh-hk")
                || lower.hasPrefix("zh-mo")
                || lower.contains("hant") {
                return "zh-Hant"
            }
            if lower.hasPrefix("zh") {
                return "zh-Hans"
            }
            if lower.hasPrefix("ja") {
                return "ja"
            }
            if lower.hasPrefix("en") {
                return "en"
            }
            return "en"
        }
    }

    static func bundle(for languageCode: String) -> Bundle {
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
