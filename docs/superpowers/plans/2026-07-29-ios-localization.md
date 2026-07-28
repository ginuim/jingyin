# iOS Localization (en / ja / zh-Hant) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship zh-Hans / zh-Hant / en / ja UI with system-follow + in-app override that switches immediately, without layout breakage.

**Architecture:** `LocalizationManager` owns preferred language and a language-scoped `Bundle`. Views read strings through that bundle. `Localizable.xcstrings` holds app strings; `*.lproj/InfoPlist.strings` hold display name and photo permission copy. Enum UI labels use stable English keys + localized titles.

**Tech Stack:** SwiftUI, String Catalog (`.xcstrings`), `UserDefaults`, Xcode `knownRegions`, iOS 17+

**Spec:** `docs/superpowers/specs/2026-07-29-ios-localization-design.md`

## Global Constraints

- Languages: `zh-Hans`, `zh-Hant`, `en`, `ja` only.
- Default: follow system; Settings can override; change applies immediately (no kill).
- Unsupported system language → **English**.
- Brand: 简/繁「镜隐」; en/ja「lenshide」。
- Settings entry: home trailing gear → `SettingsView` (language only this phase).
- Layout: no misalignment / critical truncation after language switch; prefer flexible frames + short translations; segmented/subject labels may use `minimumScaleFactor`.
- Do not change mask/export/pitch pipelines except string surfaces.
- `Jingyin/` is a `PBXFileSystemSynchronizedRootGroup` — new files under `ios/Jingyin/` are picked up automatically; still update `knownRegions` in `project.pbxproj`.
- Commit messages: English conventional commits. Work-hours commits: set author/committer to morning (after last commit, +3–10 min).

---

## File map

| File | Role |
| --- | --- |
| `ios/Jingyin/App/LocalizationManager.swift` | Language preference, resolve, bundle, `t(_:)` helper |
| `ios/Jingyin/App/SettingsView.swift` | Language picker + InfoPlist note |
| `ios/Jingyin/Localizable.xcstrings` | All UI strings, 4 locales |
| `ios/Jingyin/zh-Hans.lproj/InfoPlist.strings` | 镜隐 + 权限 |
| `ios/Jingyin/zh-Hant.lproj/InfoPlist.strings` | 鏡隱 + 權限 |
| `ios/Jingyin/en.lproj/InfoPlist.strings` | lenshide + permissions |
| `ios/Jingyin/ja.lproj/InfoPlist.strings` | lenshide + 権限 |
| `ios/Jingyin/App/JingyinApp.swift` | Inject manager |
| `ios/Jingyin/App/ContentView.swift` | Gear, brand, home copy |
| `ios/Jingyin/App/Models.swift` | Stable enum ids + localized titles |
| `ios/Jingyin/App/EditorView.swift` | Editor copy + layout-safe labels |
| `ios/Jingyin/App/ProcessingView.swift` | Processing copy |
| `ios/Jingyin/App/VideoProcessor.swift` | Advisory / errors via keys |
| `ios/Jingyin/App/VoicePitchExporter.swift` | Error strings |
| `ios/Jingyin/App/VoicePreviewEngine.swift` | Preview unsupported message |
| `ios/Jingyin.xcodeproj/project.pbxproj` | `knownRegions` += `zh-Hant`, `ja` |

---

### Task 1: LocalizationManager + knownRegions

**Files:**
- Create: `ios/Jingyin/App/LocalizationManager.swift`
- Modify: `ios/Jingyin.xcodeproj/project.pbxproj` (`knownRegions`)

**Interfaces:**
- Produces:
  - `enum AppLanguage: String, CaseIterable, Identifiable` — `system`, `zhHans`, `zhHant`, `en`, `ja`
  - `LocalizationManager` — `@MainActor final class`, `ObservableObject`
  - `var language: AppLanguage` (persisted `jingyin.appLanguage`)
  - `var effectiveLanguageCode: String` — one of `zh-Hans` / `zh-Hant` / `en` / `ja`
  - `var bundle: Bundle`
  - `func t(_ key: String.LocalizationValue) -> String`
  - `static func resolveLanguageCode(preference: AppLanguage, preferredLanguages: [String]) -> String`

- [ ] **Step 1: Write the resolve mapping table (expected behavior)**

Document and keep as comments above `resolveLanguageCode`:

| preference | preferredLanguages[0] | expected code |
| --- | --- | --- |
| `.en` | any | `en` |
| `.zhHans` | any | `zh-Hans` |
| `.zhHant` | any | `zh-Hant` |
| `.ja` | any | `ja` |
| `.system` | `zh-Hans-CN` | `zh-Hans` |
| `.system` | `zh-Hant-TW` | `zh-Hant` |
| `.system` | `zh-HK` | `zh-Hant` |
| `.system` | `en-US` | `en` |
| `.system` | `ja-JP` | `ja` |
| `.system` | `ko-KR` | `en` |
| `.system` | `fr-FR` | `en` |
| `.system` | `[]` | `en` |

- [ ] **Step 2: Implement `LocalizationManager.swift`**

```swift
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
        self.language = initial
        let code = Self.resolveLanguageCode(
            preference: initial,
            preferredLanguages: preferredLanguages
        )
        self.effectiveLanguageCode = code
        self.bundle = Self.bundle(for: code)
    }

    func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle)
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
            if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") { return "zh-Hans" }
            if lower.hasPrefix("zh-hant")
                || lower.hasPrefix("zh-tw")
                || lower.hasPrefix("zh-hk")
                || lower.hasPrefix("zh-mo")
                || lower == "zh-hk"
                || lower.hasPrefix("zh") && (lower.contains("hant") || lower.contains("tw") || lower.contains("hk")) {
                return "zh-Hant"
            }
            // Generic "zh" without Hans/Hant → Hans is common on mainland devices;
            // but Spec says unknown → English. Only map clear families.
            if lower.hasPrefix("zh") { return "zh-Hans" }
            if lower.hasPrefix("ja") { return "ja" }
            if lower.hasPrefix("en") { return "en" }
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
```

Note on `zh` mapping: clear `zh-Hans*` / `zh-CN` → Hans; clear Hant/TW/HK/MO → Hant; bare `zh` → Hans (common); everything else → `en`.

- [ ] **Step 3: Verify resolve table with a quick script**

Run from repo root:

```bash
# Paste resolveLanguageCode into a temporary swift file or evaluate mentally against the table.
# Preferred: add a DEBUG-only unit check in LocalizationManager.init in DEBUG builds:
#if DEBUG
enum LocalizationResolverSmoke {
    static func run() {
        let cases: [(AppLanguage, [String], String)] = [
            (.en, ["ko-KR"], "en"),
            (.system, ["ko-KR"], "en"),
            (.system, ["zh-Hant-TW"], "zh-Hant"),
            (.system, ["zh-Hans-CN"], "zh-Hans"),
            (.system, ["ja-JP"], "ja"),
            (.system, ["fr-FR"], "en"),
            (.system, [], "en"),
            (.ja, ["en"], "ja"),
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
```

Call `LocalizationResolverSmoke.run()` once from `JingyinApp.init` under `#if DEBUG`.

- [ ] **Step 4: Update `knownRegions`**

In `ios/Jingyin.xcodeproj/project.pbxproj`:

```
knownRegions = (
    "zh-Hans",
    "zh-Hant",
    en,
    ja,
    Base,
);
```

- [ ] **Step 5: Build**

```bash
cd ios && xcodebuild -scheme Jingyin -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: BUILD SUCCEEDED (manager compiles even before catalog exists if no `t` call sites yet).

- [ ] **Step 6: Commit**

```bash
git add ios/Jingyin/App/LocalizationManager.swift ios/Jingyin.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(ios): add LocalizationManager and language regions

EOF
)"
```

---

### Task 2: String Catalog + InfoPlist.strings

**Files:**
- Create: `ios/Jingyin/Localizable.xcstrings`
- Create: `ios/Jingyin/zh-Hans.lproj/InfoPlist.strings`
- Create: `ios/Jingyin/zh-Hant.lproj/InfoPlist.strings`
- Create: `ios/Jingyin/en.lproj/InfoPlist.strings`
- Create: `ios/Jingyin/ja.lproj/InfoPlist.strings`

**Interfaces:**
- Consumes: language codes from Task 1
- Produces: keys listed below (all four locales filled)

- [ ] **Step 1: Create InfoPlist.strings (4 locales)**

`zh-Hans.lproj/InfoPlist.strings`:

```
CFBundleDisplayName = "镜隐";
NSPhotoLibraryUsageDescription = "用于选择需要在设备本地处理的视频。";
NSPhotoLibraryAddUsageDescription = "用于将本地处理完成的视频保存到你的相册。";
```

`zh-Hant.lproj/InfoPlist.strings`:

```
CFBundleDisplayName = "鏡隱";
NSPhotoLibraryUsageDescription = "用於選擇需要在裝置本機處理的影片。";
NSPhotoLibraryAddUsageDescription = "用於將本機處理完成的影片儲存到你的相簿。";
```

`en.lproj/InfoPlist.strings`:

```
CFBundleDisplayName = "lenshide";
NSPhotoLibraryUsageDescription = "Used to choose videos to process on your device.";
NSPhotoLibraryAddUsageDescription = "Used to save locally processed videos to your library.";
```

`ja.lproj/InfoPlist.strings`:

```
CFBundleDisplayName = "lenshide";
NSPhotoLibraryUsageDescription = "端末上で処理する動画を選択するために使用します。";
NSPhotoLibraryAddUsageDescription = "端末で処理した動画を写真ライブラリに保存するために使用します。";
```

Keep `Config/Info.plist` Chinese values as development-region defaults (zh-Hans).

- [ ] **Step 2: Create `Localizable.xcstrings` with all keys**

Use Xcode String Catalog JSON. Source language `zh-Hans`. Every key must have `zh-Hans`, `zh-Hant`, `en`, `ja`.

Keys and translations (keep short for layout):

| key | zh-Hans | zh-Hant | en | ja |
| --- | --- | --- | --- | --- |
| `brand.name` | 镜隐 | 鏡隱 | lenshide | lenshide |
| `home.tagline` | 视频隐私，只留在你的设备里 | 影片隱私，只留在你的裝置裡 | Video privacy, stays on your device | 動画のプライバシーは端末内だけに |
| `home.pickPhotos` | 从相册选择视频 | 從相簿選擇影片 | Choose from Photos | 写真から動画を選択 |
| `home.pickFiles` | 从文件选择视频 | 從檔案選擇影片 | Choose from Files | ファイルから動画を選択 |
| `home.privacy` | 原视频、识别数据和结果均不会上传 | 原始影片、辨識資料與結果皆不會上傳 | Original video, detection data, and results never leave the device | 元動画・検出データ・結果は送信しません |
| `home.reading` | 正在读取视频… | 正在讀取影片… | Reading video… | 動画を読み込み中… |
| `settings.title` | 设置 | 設定 | Settings | 設定 |
| `settings.language` | 语言 | 語言 | Language | 言語 |
| `settings.language.system` | 跟随系统 | 跟隨系統 | System | システムに合わせる |
| `settings.language.zhHans` | 简体中文 | 簡體中文 | Simplified Chinese | 簡体字中国語 |
| `settings.language.zhHant` | 繁体中文 | 繁體中文 | Traditional Chinese | 繁体字中国語 |
| `settings.language.en` | English | English | English | English |
| `settings.language.ja` | 日本語 | 日本語 | Japanese | 日本語 |
| `settings.language.note` | 主屏幕应用名可能仍跟随系统语言 | 主畫面應用程式名稱可能仍跟隨系統語言 | Home screen name may still follow system language | ホーム画面のアプリ名はシステム言語のままの場合があります |
| `editor.title` | 编辑 | 編輯 | Edit | 編集 |
| `editor.previewBadge` | 效果预览 | 效果預覽 | Preview | プレビュー |
| `editor.start` | 开始本地处理 | 開始本機處理 | Process on Device | 端末で処理を開始 |
| `editor.preparingVoice` | 正在准备变音试听… | 正在準備變音試聽… | Preparing voice preview… | ボイスプレビュー準備中… |
| `editor.scope` | 遮盖范围 | 遮蓋範圍 | Mask Area | マスク範囲 |
| `editor.subjects` | 识别主体 | 辨識主體 | Subjects | 検出対象 |
| `editor.quality` | 处理档位 | 處理檔位 | Quality | 処理品質 |
| `editor.style` | 画面效果 | 畫面效果 | Effect | 映像効果 |
| `editor.strength` | 强度 | 強度 | Strength | 強さ |
| `editor.weak` | 弱 | 弱 | Soft | 弱 |
| `editor.strong` | 强 | 強 | Strong | 強 |
| `editor.audio` | 声音处理 | 聲音處理 | Audio | 音声 |
| `editor.pitchLow` | 低 | 低 | Low | 低 |
| `editor.pitchHigh` | 高 | 高 | High | 高 |
| `editor.pitchHint` | 真正改变音调，不改变语速；播放时拖动可实时试听。 | 真正改變音調，不改變語速；播放時拖曳可即時試聽。 | Changes pitch, not speed. Drag while playing to preview. | 音程のみ変更（速度はそのまま）。再生中にドラッグで試聴。 |
| `quality.fast` | 快速 | 快速 | Fast | 高速 |
| `quality.balanced` | 均衡 | 均衡 | Balanced | 標準 |
| `quality.precise` | 精细 | 精細 | Precise | 精密 |
| `scope.subjects` | 遮盖主体 | 遮蓋主體 | Subjects | 被写体 |
| `scope.background` | 遮盖背景 | 遮蓋背景 | Background | 背景 |
| `scope.full` | 遮盖全画面 | 遮蓋全畫面 | Full Frame | 全体 |
| `style.blur` | 模糊 | 模糊 | Blur | ぼかし |
| `style.pixel` | 像素化 | 像素化 | Pixelate | モザイク |
| `style.ascii` | ASCII | ASCII | ASCII | ASCII |
| `audio.original` | 原声 | 原聲 | Original | 原音 |
| `audio.voice` | 变音 | 變音 | Voice | ボイス |
| `audio.mute` | 静音 | 靜音 | Mute | 消音 |
| `audio.meta.original` | 保留视频原声 | 保留影片原聲 | Keep original audio | 元の音声を保持 |
| `audio.meta.voice` | 音调偏移 | 音調偏移 | Pitch shift | ピッチシフト |
| `audio.meta.mute` | 导出无音轨 | 匯出無音軌 | Export without audio | 音声なしで書き出し |
| `subject.person` | 人物 | 人物 | Person | 人物 |
| `subject.face` | 人脸 | 人臉 | Face | 顔 |
| `subject.pet` | 宠物 | 寵物 | Pet | ペット |
| `pitch.meta` | 音调 %lld 半音 | 音調 %lld 半音 | Pitch %lld st | ピッチ %lld 半音 |
| `strength.blur` | 模糊半径 %lld px | 模糊半徑 %lld px | Blur radius %lld px | ぼかし半径 %lld px |
| `strength.pixel` | 像素块 %lld px | 像素塊 %lld px | Pixel size %lld px | モザイク %lld px |
| `strength.ascii` | 黑白字符画 · 字符 %lld px | 黑白字元畫 · 字元 %lld px | ASCII · cell %lld px | アスキー · %lld px |
| `stage.idle` | 等待开始 | 等待開始 | Ready | 待機中 |
| `stage.reading` | 正在读取视频 | 正在讀取影片 | Reading video | 動画を読み込み中 |
| `stage.loadingModel` | 正在加载模型 | 正在載入模型 | Loading model | モデル読み込み中 |
| `stage.warmingUp` | 正在预热模型 | 正在預熱模型 | Warming up | モデル準備中 |
| `stage.analyzing` | 正在分析画面 | 正在分析畫面 | Analyzing | 解析中 |
| `stage.encoding` | 正在编码导出 | 正在編碼匯出 | Encoding | 書き出し中 |
| `stage.completed` | 处理完成 | 處理完成 | Done | 完了 |
| `stage.failed` | 处理失败 | 處理失敗 | Failed | 失敗 |
| `processing.title` | 处理 | 處理 | Process | 処理 |
| `processing.retry` | 重试 | 重試 | Retry | 再試行 |
| `processing.save` | 保存到相册 | 儲存到相簿 | Save to Photos | 写真に保存 |
| `processing.saved` | 已保存 | 已儲存 | Saved | 保存済み |
| `processing.share` | 分享 | 分享 | Share | 共有 |
| `processing.cancel` | 取消处理 | 取消處理 | Cancel | キャンセル |
| `advisory.resource` | 设备当前资源紧张，已自动切换为均衡档。 | 裝置目前資源緊張，已自動切換為均衡檔。 | Device busy — switched to Balanced. | 負荷が高いため標準に切り替えました。 |
| `advisory.noAudio` | 视频无音轨，已按无声导出 | 影片無音軌，已按無聲匯出 | No audio track — exported silent | 音声トラックがないため無音で書き出し |
| `error.cancelled` | 处理已取消，可返回调整后重试。 | 處理已取消，可返回調整後重試。 | Cancelled. Go back, adjust, and retry. | キャンセルしました。戻って調整後に再試行できます。 |
| `error.exportPrefix` | 无法完成导出：%@ | 無法完成匯出：%@ | Export failed: %@ | 書き出し失敗：%@ |
| `error.invalidVideo` | 视频无效或无法读取。 | 影片無效或無法讀取。 | Invalid or unreadable video. | 動画が無効、または読み込めません。 |
| `error.videoTooLong` | 首版暂时支持最长 5 分钟的视频。 | 首版暫時支援最長 5 分鐘的影片。 | First version supports videos up to 5 minutes. | 初版は最長5分まで対応です。 |
| `error.fileTooLarge` | 首版暂时支持最大 1 GB 的视频文件。 | 首版暫時支援最大 1 GB 的影片檔。 | First version supports files up to 1 GB. | 初版は最大1GBまで対応です。 |
| `error.insufficientStorage` | 可用存储空间不足，请清理空间后重试。 | 可用儲存空間不足，請清理後重試。 | Not enough storage. Free space and retry. | 空き容量が不足しています。削除して再試行してください。 |
| `error.encoderUnavailable` | 当前设备没有可用的视频编码器。 | 目前裝置沒有可用的影片編碼器。 | No video encoder available on this device. | この端末では動画エンコーダを利用できません。 |
| `error.exportFailed` | 视频编码失败，请降低档位后重试。 | 影片編碼失敗，請降低檔位後重試。 | Encoding failed. Try a lower quality. | エンコードに失敗しました。品質を下げて再試行してください。 |
| `error.noAudioTrack` | 视频无音轨 | 影片無音軌 | No audio track | 音声トラックなし |
| `error.voiceRenderFailed` | 变音处理失败，可改选原声或静音后重试 | 變音處理失敗，可改選原聲或靜音後重試 | Voice processing failed. Try Original or Mute. | ボイス処理に失敗。原音または消音で再試行 |
| `error.voiceMuxFailed` | 变音音轨合成失败，可改选原声或静音后重试 | 變音音軌合成失敗，可改選原聲或靜音後重試 | Voice mux failed. Try Original or Mute. | 音声合成に失敗。原音または消音で再試行 |
| `error.previewUnsupported` | 当前无法实时试听变音 | 目前無法即時試聽變音 | Live voice preview unavailable | リアルタイム試聴は利用できません |

Catalog file shape (example for one key — expand for all):

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {
    "brand.name" : {
      "localizations" : {
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "镜隐" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "鏡隱" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "lenshide" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "lenshide" } }
      }
    }
  },
  "version" : "1.0"
}
```

For format strings (`pitch.meta`, `strength.*`, `error.exportPrefix`), mark as having substitutions in the catalog (Xcode format: `%lld` / `%@`).

Prefer concise en/ja so segmented controls and subject chips do not overflow.

- [ ] **Step 3: Build to compile string catalog**

```bash
cd ios && xcodebuild -scheme Jingyin -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: BUILD SUCCEEDED; app bundle contains `zh-Hans.lproj`, `zh-Hant.lproj`, `en.lproj`, `ja.lproj`.

- [ ] **Step 4: Commit**

```bash
git add ios/Jingyin/Localizable.xcstrings ios/Jingyin/*.lproj
git commit -m "$(cat <<'EOF'
feat(ios): add string catalog and InfoPlist localizations

EOF
)"
```

---

### Task 3: App wiring + SettingsView

**Files:**
- Create: `ios/Jingyin/App/SettingsView.swift`
- Modify: `ios/Jingyin/App/JingyinApp.swift`
- Modify: `ios/Jingyin/App/ContentView.swift` (gear + environment only; full home copy can wait for Task 5 if split — prefer do brand + gear here)

**Interfaces:**
- Consumes: `LocalizationManager` from Task 1, keys from Task 2
- Produces: settings navigation from home

- [ ] **Step 1: Wire `JingyinApp`**

```swift
import SwiftUI

@main
struct JingyinApp: App {
    @StateObject private var localization = LocalizationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .environment(\.locale, Locale(identifier: localization.effectiveLanguageCode))
                .id(localization.effectiveLanguageCode) // force refresh on language change
                .tint(.mint)
                .task {
                    #if DEBUG
                    LocalizationResolverSmoke.run()
                    #endif
                }
        }
    }
}
```

`.id(effectiveLanguageCode)` ensures SwiftUI rebuilds the tree on language change (layout remeasured).

- [ ] **Step 2: Implement `SettingsView`**

```swift
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
            }
        }
        .navigationTitle(localization.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 3: Add gear on `ContentView`**

In `ContentView` body, after NavigationStack content modifiers:

```swift
@EnvironmentObject private var localization: LocalizationManager
@State private var showSettings = false
```

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel(localization.t("settings.title"))
    }
}
.navigationDestination(isPresented: $showSettings) {
    SettingsView()
}
```

Also replace brand title temporarily with `localization.t("brand.name")` so language switch is visible.

- [ ] **Step 4: Build and manually switch language in Simulator**

Expected: Settings opens; changing language updates brand title immediately; layout of gear remains top-trailing.

- [ ] **Step 5: Commit**

```bash
git add ios/Jingyin/App/JingyinApp.swift ios/Jingyin/App/SettingsView.swift ios/Jingyin/App/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(ios): wire settings language picker with live switch

EOF
)"
```

---

### Task 4: Localize Models enums + stage/error helpers

**Files:**
- Modify: `ios/Jingyin/App/Models.swift`
- Modify: `ios/Jingyin/App/VideoProcessor.swift`
- Modify: `ios/Jingyin/App/VoicePitchExporter.swift`
- Modify: `ios/Jingyin/App/VoicePreviewEngine.swift`

**Interfaces:**
- Consumes: `LocalizationManager.t` / `String(localized:bundle:)` — Views pass manager OR helpers take `Bundle`
- Produces: `localizedTitle(bundle:)`, `meta(bundle:)`, stage titles via keys; processors emit already-localized strings using `Bundle` captured at call time

**Rule:** Processors are not Views. Prefer:

```swift
func localizedMessage(bundle: Bundle) -> String {
    String(localized: "error.invalidVideo", bundle: bundle)
}
```

`VideoProcessor.process` should accept `bundle: Bundle` (default `.main`) OR read from a weak/shared manager. Simplest: add parameter `localizationBundle: Bundle` to `process(...)` and pass `localization.bundle` from `ProcessingView`.

- [ ] **Step 1: Change enums to stable raw values**

```swift
enum QualityMode: String, CaseIterable, Identifiable {
    case fast, balanced, precise
    var id: Self { self }
    func title(_ bundle: Bundle) -> String {
        switch self {
        case .fast: String(localized: "quality.fast", bundle: bundle)
        case .balanced: String(localized: "quality.balanced", bundle: bundle)
        case .precise: String(localized: "quality.precise", bundle: bundle)
        }
    }
    // frameInterval unchanged
}
```

Same pattern for `MaskScope`, `EffectStyle`, `AudioMode` (plus `meta(bundle:)`), `SubjectKind`.

`VoicePitchStore.metaLabel(_ semitones: Int, bundle: Bundle)`:

```swift
String(
    format: String(localized: "pitch.meta", bundle: bundle),
    locale: Locale(identifier: bundle.preferredLocalizations.first ?? "en"),
    Int64(clamp(semitones)) // show sign: prefer custom format
)
```

For signed pitch, either:
- store template as `音调 %@_半音` and pass `"+4"` / `"-4"` string, or
- build in code: `String(localized: "audio.meta.voice", bundle:)` + `" \(value)"` — prefer one format string with explicit signed string argument:

Key `pitch.meta` value examples: `音调 %@ 半音` / `Pitch %@ st` where argument is `+4` / `-4` / `0`.

Update `ProcessingOptions.audioMeta` to `func audioMeta(bundle: Bundle) -> String`.

`ProcessingStage.title(bundle:)` maps to `stage.*` keys (failed/completed ignore associated value for title).

- [ ] **Step 2: Update `videoEffectToken` in EditorView**

Use enum `rawValue` (now English stable ids) — already fine after Step 1.

- [ ] **Step 3: Localize processor / exporter / preview errors**

In `VideoProcessor`, replace Chinese string literals with `String(localized:bundle:)` using a `bundle` property set at start of `process(sourceURL:options:bundle:)`.

Same for `VoicePitchExporter.ExportError` — convert `errorDescription` to method taking bundle, or localize at throw sites.

`VoicePreviewEngine`: set message via key when unsupported; inject bundle when preparing, or set key and let View localize. Prefer View-side: engine sets `previewUnsupported = true`; View shows `localization.t("error.previewUnsupported")`. That avoids bundle plumbing in the engine — **prefer this**.

- [ ] **Step 4: Build**

Fix compile errors from renamed raw values / call sites.

- [ ] **Step 5: Commit**

```bash
git add ios/Jingyin/App/Models.swift ios/Jingyin/App/VideoProcessor.swift ios/Jingyin/App/VoicePitchExporter.swift ios/Jingyin/App/VoicePreviewEngine.swift ios/Jingyin/App/EditorView.swift ios/Jingyin/App/ProcessingView.swift
git commit -m "$(cat <<'EOF'
refactor(ios): localize model labels and processing errors

EOF
)"
```

---

### Task 5: Localize ContentView + ProcessingView + EditorView (layout-safe)

**Files:**
- Modify: `ios/Jingyin/App/ContentView.swift`
- Modify: `ios/Jingyin/App/EditorView.swift`
- Modify: `ios/Jingyin/App/ProcessingView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var localization: LocalizationManager`

- [ ] **Step 1: ContentView strings**

Replace all user-visible Chinese with `localization.t(...)`.

Layout guards:

```swift
Text(localization.t("home.tagline"))
    .font(.subheadline)
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 28)

Label(localization.t("home.pickPhotos"), ...)
    .lineLimit(2)
    .minimumScaleFactor(0.85)

Label(localization.t("home.privacy"), ...)
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
```

Brand title uses `localization.t("brand.name")`.

- [ ] **Step 2: EditorView strings + layout**

Pass `localization.bundle` into enum `title` / `audioMeta`.

Segmented pickers — short labels already in catalog; still apply:

```swift
Text(scope.title(localization.bundle))
    .lineLimit(1)
    .minimumScaleFactor(0.7)
```

Subject chips:

```swift
Text(subject.title(localization.bundle))
    .font(.caption.bold())
    .lineLimit(1)
    .minimumScaleFactor(0.8)
```

`OptionSection` meta label: allow 2 lines with `fixedSize(horizontal: false, vertical: true)`.

Strength / pitch descriptions use format strings via `String(format:locale:arguments:)` with `localization.bundle`.

CTA button: `.lineLimit(1).minimumScaleFactor(0.85)`.

- [ ] **Step 3: ProcessingView strings**

```swift
@EnvironmentObject private var localization: LocalizationManager
```

Pass `bundle: localization.bundle` into `processor.process`.

Replace buttons/titles; save/share `HStack` use:

```swift
.lineLimit(1)
.minimumScaleFactor(0.8)
```

Advisory / error: `.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)`.

- [ ] **Step 4: Build + language flip smoke**

In Simulator: Settings → switch zh-Hans → en → ja → zh-Hant → system. Visit Home / Editor (need a video) / Processing cancel path. Confirm no overlapping text, no clipped primary buttons, segmented controls readable.

- [ ] **Step 5: Commit**

```bash
git add ios/Jingyin/App/ContentView.swift ios/Jingyin/App/EditorView.swift ios/Jingyin/App/ProcessingView.swift
git commit -m "$(cat <<'EOF'
feat(ios): localize home, editor, and processing UI

EOF
)"
```

---

### Task 6: Final acceptance pass

**Files:** none required unless fixes

- [ ] **Step 1: Checklist from spec §6**

1. System en/ja/zh-Hant/zh-Hans + App「跟随系统」→ correct UI.
2. System ko/fr +「跟随系统」→ English.
3. In-app override → immediate update on Home/Editor/Processing/Settings.
4. Brand 镜隐 / 鏡隱 vs lenshide.
5. Photo permission dialog matches **system** language (InfoPlist).
6. Relaunch keeps App language preference.
7. Four languages: no layout breakage on Home / Editor / Processing / Settings.

- [ ] **Step 2: Fix any overflow with shorter copy or scale factors** (do not widen chrome or invent new screens).

- [ ] **Step 3: Commit fixes if any**

```bash
git commit -m "$(cat <<'EOF'
fix(ios): tighten localized layouts across languages

EOF
)"
```

---

## Self-review (plan author)

1. **Spec coverage:** system+override, immediate switch, zh-Hant, brand rules, English fallback, settings gear, catalog, InfoPlist, enum keys, layout stability — all have tasks.
2. **Placeholders:** none; keys and code sketches are concrete.
3. **Types:** `AppLanguage`, `LocalizationManager.t`, `resolveLanguageCode`, `bundle` parameter on process — consistent across tasks.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-29-ios-localization.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
**2. Inline Execution** — run tasks in this session with executing-plans checkpoints  

Which approach?
