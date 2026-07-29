# ASCII 自定义颜色 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ASCII 效果支持成套主题 + ColorPicker 自定义双色，并缓存最近 5 组成对色。

**Architecture:** `ProcessingOptions` 存会话级 `asciiForeground`/`asciiBackground`；内置主题只是快捷写入；`ASCIIColorRecentStore` 用 UserDefaults 存最近成对色；`FrameEffectProcessor` 用这两色画 glyph 与背景；编辑页仅在 ASCII 时显示色板。

**Tech Stack:** Swift 6、SwiftUI、Core Image、UserDefaults、String Catalog

## Global Constraints

- 最低 iOS 17；改动限 `ios/` 与本 plan/spec 文档
- 用户可见文案必须四语：简中 / 繁中 / 英文 / 日文
- 预览与导出共用 `ProcessingOptions`；免费限制与本功能无关
- 不提交 git，除非用户明确要求

---

### Task 1: 数据模型与最近色存储

**Files:**
- Modify: `ios/Jingyin/App/Models.swift`

**Interfaces:**
- Produces: `EffectRGBA`, `ASCIIColorPair`, `ASCIIColorTheme.all`, `ASCIIColorRecentStore.load/remember`, `ProcessingOptions.asciiForeground/asciiBackground`

- [ ] **Step 1:** 在 `VoicePitchStore` 后、`ProcessingOptions` 前加入：

```swift
struct EffectRGBA: Equatable, Sendable, Codable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    static let asciiDefaultForeground = EffectRGBA(r: 0.957, g: 0.969, b: 0.961)
    static let asciiDefaultBackground = EffectRGBA(r: 0.02, g: 0.027, b: 0.024)

    var ciColor: CIColor { CIColor(red: r, green: g, blue: b, alpha: a) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    func matches(_ other: EffectRGBA, tolerance: Double = 0.002) -> Bool {
        abs(r - other.r) <= tolerance
            && abs(g - other.g) <= tolerance
            && abs(b - other.b) <= tolerance
            && abs(a - other.a) <= tolerance
    }
}

struct ASCIIColorPair: Equatable, Sendable, Codable {
    var foreground: EffectRGBA
    var background: EffectRGBA

    func matches(_ other: ASCIIColorPair) -> Bool {
        foreground.matches(other.foreground) && background.matches(other.background)
    }
}

struct ASCIIColorTheme: Identifiable, Equatable {
    let id: String
    let foreground: EffectRGBA
    let background: EffectRGBA

    var pair: ASCIIColorPair {
        ASCIIColorPair(foreground: foreground, background: background)
    }

    func title(_ bundle: Bundle) -> String {
        String(localized: String.LocalizationValue("ascii.theme.\(id)"), bundle: bundle)
    }

    static let all: [ASCIIColorTheme] = [
        .init(id: "classic", foreground: .asciiDefaultForeground, background: .asciiDefaultBackground),
        .init(id: "amber", foreground: EffectRGBA(r: 1, g: 0.78, b: 0.28), background: EffectRGBA(r: 0.08, g: 0.05, b: 0.02)),
        .init(id: "blue", foreground: EffectRGBA(r: 0.75, g: 0.88, b: 1), background: EffectRGBA(r: 0.04, g: 0.08, b: 0.14)),
        .init(id: "paper", foreground: EffectRGBA(r: 0.12, g: 0.12, b: 0.11), background: EffectRGBA(r: 0.94, g: 0.92, b: 0.86)),
        .init(id: "matrix", foreground: EffectRGBA(r: 0.2, g: 0.95, b: 0.35), background: EffectRGBA(r: 0.02, g: 0.06, b: 0.02)),
        .init(id: "magenta", foreground: EffectRGBA(r: 1, g: 0.55, b: 0.85), background: EffectRGBA(r: 0.1, g: 0.02, b: 0.08)),
    ]
}

enum ASCIIColorRecentStore {
    static let key = "jingyin.asciiRecentColors"
    static let maxCount = 5

    static func load() -> [ASCIIColorPair] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let pairs = try? JSONDecoder().decode([ASCIIColorPair].self, from: data) else {
            return []
        }
        return Array(pairs.prefix(maxCount))
    }

    static func remember(_ pair: ASCIIColorPair) {
        var pairs = load().filter { !$0.matches(pair) }
        pairs.insert(pair, at: 0)
        if pairs.count > maxCount {
            pairs = Array(pairs.prefix(maxCount))
        }
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 2:** `ProcessingOptions` 增加：

```swift
var asciiForeground: EffectRGBA = .asciiDefaultForeground
var asciiBackground: EffectRGBA = .asciiDefaultBackground
```

- [ ] **Step 3:** `Models.swift` 顶部如无 `import UIKit` / CoreImage，为 `uiColor`/`ciColor` 增加必要 import（或把转换放 Editor/Processor，Models 只存数值）。优先：Models 只存数值与 Codable；`CIColor`/`UIColor` 转换放使用处，避免 Models 依赖 UIKit。

---

### Task 2: VideoProcessor 使用 options 颜色

**Files:**
- Modify: `ios/Jingyin/App/VideoProcessor.swift`

- [ ] **Step 1:** `init` 改为：

```swift
asciiGlyphTiles = options.style == .ascii
    ? Self.makeASCIIGlyphTiles(
        cellSize: CGFloat(options.strength),
        foreground: options.asciiForeground
      )
    : []
```

- [ ] **Step 2:** `asciiImage` 背景色改为 options：

```swift
result = CIImage(color: CIColor(
    red: options.asciiBackground.r,
    green: options.asciiBackground.g,
    blue: options.asciiBackground.b,
    alpha: options.asciiBackground.a
)).cropped(to: extent)
```

- [ ] **Step 3:** `makeASCIIGlyphTiles(cellSize:foreground:)` 用 `UIColor(red:foreground.r, ...)` 替代写死颜色。

---

### Task 3: 编辑页 UI + 预览 token + 文案

**Files:**
- Modify: `ios/Jingyin/App/EditorView.swift`
- Modify: `ios/Jingyin/Localizable.xcstrings`

- [ ] **Step 1:** `videoEffectToken` 拼接颜色：

```swift
let fg = options.asciiForeground
let bg = options.asciiBackground
return "...|\(fg.r),\(fg.g),\(fg.b)|\(bg.r),\(bg.g),\(bg.b)|..."
```

- [ ] **Step 2:** style 区块在 ASCII 时插入颜色控件（主题圆点、最近色、展开 ColorPicker）；ColorPicker `onChange` 调 `ASCIIColorRecentStore.remember` 并刷新 `@State recentPairs`。

- [ ] **Step 3:** 四语 key：`ascii.color`、`ascii.color.foreground`、`ascii.color.background`、`ascii.color.recent`、`ascii.color.custom`、`ascii.theme.classic|amber|blue|paper|matrix|magenta`。

- [ ] **Step 4:** 模拟器编译：

```bash
cd ios && xcodebuild -project Jingyin.xcodeproj -scheme Jingyin -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED
