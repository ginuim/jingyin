# iOS 多语言：英 / 日 / 繁体 + App 内覆盖

日期：2026-07-29  
状态：已定稿，待实现计划

## 目标

1. 支持简体中文、繁体中文（通用 `zh-Hant`）、English、日本語。
2. 默认跟随系统语言；设置页可覆盖，且**即时生效**（无需杀进程）。
3. 品牌显示名：中文（简/繁）为「镜隐」，英/日为「lenshide」。
4. 覆盖首页、编辑页、处理页、枚举选项、错误/提示文案，以及 Info.plist 权限说明。

## 非目标

- 台/港两套繁体分词。
- App Store Connect 元数据本地化（本阶段只做 App 内）。
- 设置页里塞隐私政策、版本号以外的新功能（设置页本阶段只做语言）。
- 依赖第三方本地化库。

## 决策摘要

| 项 | 选择 |
| --- | --- |
| 切换模式 | 跟随系统 + App 内覆盖（即时生效） |
| 繁体 | 通用 `zh-Hant` |
| 品牌名 | 简/繁「镜隐」；en/ja「lenshide」 |
| 设置入口 | 首页右上角齿轮 → SettingsView |
| 文案载体 | String Catalog `Localizable.xcstrings` |
| 未知系统语言回落 | **English**（不在四语内时） |

## 1. 数据模型

```swift
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans   // zh-Hans
    case zhHant   // zh-Hant
    case en
    case ja
}

@MainActor
final class LocalizationManager: ObservableObject {
    @Published var language: AppLanguage  // UserDefaults key: jingyin.appLanguage
    var effectiveLocale: Locale           // 解析后的实际 locale
    var bundle: Bundle                    // 指向对应 .lproj 的资源 Bundle
}
```

**解析规则**

- `system`：读 `Locale.preferredLanguages` 首项，映射到 `zh-Hans` / `zh-Hant` / `en` / `ja`。
- 无法映射（如韩语、法语）→ **en**。
- 非 `system`：直接用所选语言的 locale id。

**枚举展示文案**

`QualityMode` / `MaskScope` / `EffectStyle` / `AudioMode` / `SubjectKind` / `ProcessStage` 等去掉中文 `rawValue` 当 UI 文案的做法；case 用稳定英文 id（或保持现有 case 名），展示走 localization key。

## 2. 架构

```
JingyinApp
  └─ LocalizationManager (@EnvironmentObject / @StateObject)
       ├─ SettingsView（语言 Picker）
       ├─ ContentView / EditorView / ProcessingView
       └─ Models / VideoProcessor 等错误与阶段文案
```

- UI 字符串统一经 `LocalizationManager.bundle` 取文案（`String(localized:bundle:)` 或薄封装 `L10n`）。
- 改语言时：写 `UserDefaults` → 重建 `bundle` → `@Published` 触发 SwiftUI 刷新。
- 不依赖改 `AppleLanguages` 再杀进程；用 Bundle 热切换保证即时生效。

## 3. 文件与工程

**新增**

- `Jingyin/App/LocalizationManager.swift`
- `Jingyin/App/SettingsView.swift`
- `Jingyin/Resources/Localizable.xcstrings`
- `zh-Hans.lproj/InfoPlist.strings`、`zh-Hant.lproj/`、`en.lproj/`、`ja.lproj/`  
  （`CFBundleDisplayName`、相册权限 `NSPhotoLibrary*`）

**改动**

- `ContentView`：齿轮入口；品牌标题本地化
- `EditorView` / `ProcessingView` / `Models` / `VideoProcessor` / `VoicePitchExporter` / `VoicePreviewEngine`：硬编码中文 → key
- `JingyinApp`：注入 `LocalizationManager`
- `project.pbxproj`：`knownRegions` 增加 `zh-Hant`、`ja`；纳入新资源

**不改**

- 分割、编码、变音管线逻辑本身

## 4. 文案范围（首版）

覆盖现有用户可见中文，至少包括：

- 首页：标语、选视频、隐私提示、读取中
- 编辑：分区标题、选项、强度/音调说明、开始处理、试听状态
- 处理：阶段标题、重试/保存/分享/取消、advisory
- 错误：时长/体积/存储/编码器/导出/变音失败等
- Info.plist：显示名、相册读/写说明

插值句（模糊半径、半音、错误 `localizedDescription`）用带 format 的本地化模板。

## 5. 边界与限制

- **Info.plist / 桌面显示名**：受系统 App 语言影响，不完全跟随 App 内覆盖；App 内 UI 即时切，主屏幕图标名可能仍跟系统。实现时在设置页语言项下用一行小字说明即可。
- **未知系统语言**：回落 English。
- **持久化**：只存 `AppLanguage`；不把翻译字符串写入磁盘。

## 6. 验收

1. 系统为 en / ja / zh-Hant / zh-Hans，「跟随系统」时 UI 语言正确。
2. 系统为其他语言，「跟随系统」→ English。
3. App 内强制切换 → 首页/编辑/处理/错误文案即时更新。
4. 简/繁标题为「镜隐」，英/日为「lenshide」。
5. 系统语言下相册权限弹窗文案为对应语言。
6. 冷启动后仍记住上次 App 内语言偏好。

## 7. 实现顺序建议

1. `LocalizationManager` + 工程区域 + 空 catalog / InfoPlist.strings
2. 接入 `JingyinApp` / `SettingsView` / 首页齿轮
3. 逐屏替换硬编码字符串并填四语翻译
4. 枚举展示文案改造
5. 模拟器切换系统语言 + App 内覆盖验收
