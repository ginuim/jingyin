# iOS ASCII 自定义颜色

日期：2026-07-30  
状态：已定稿，待实现计划

## 目标

1. ASCII 效果支持用户自定义**字符色**与**背景色**。
2. 提供成套主题色板（一键写入双色）+「自定义」入口（两个 ColorPicker）。
3. 预览与最终导出使用同一组颜色，无第二条路径。
4. 默认外观保持现有近白字符 + 深底，切换到 ASCII 时观感不变。
5. 缓存用户最近用过的成对颜色（字符色+背景色），跨启动可复用。

## 非目标

- 不按原视频上色（彩色 ASCII / 源色保留）。
- 不为模糊、像素化增加颜色控件。
- 不持久化整份 `ProcessingOptions`；当前项目里的双色仍是会话态。
- 不单独调节字符透明度、渐变或描边。
- 不引入「主题 ID + 覆盖色」双轨状态。
- 不记住「上次离开编辑页时的 ASCII 双色」作为新项目默认（只靠最近色板复用）。

## 决策摘要

| 项 | 选择 |
| --- | --- |
| 可调颜色 | 字符色 + 背景色 |
| 选色方式 | 成套主题色板 + 最近成对色 + ColorPicker 自定义 |
| 色板组织 | 成套主题（一点换双色），不拆成两套独立色板 |
| 数据模型 | options 只存两个 RGBA；主题只是快捷写入 |
| 最近色 | UserDefaults 存最多 5 组成对 RGBA，跨启动保留 |
| 默认色 | 保持现有硬编码值 |
| 作用范围 | 仅 `EffectStyle.ascii` |

## 1. 数据模型

```swift
struct EffectRGBA: Equatable, Sendable, Codable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

struct ASCIIColorPair: Equatable, Sendable, Codable {
    var foreground: EffectRGBA
    var background: EffectRGBA
}

struct ProcessingOptions {
    // existing fields...
    var asciiForeground: EffectRGBA  // default 0.957, 0.969, 0.961, 1
    var asciiBackground: EffectRGBA  // default 0.02, 0.027, 0.024, 1
}

struct ASCIIColorTheme: Identifiable, Equatable {
    let id: String
    let foreground: EffectRGBA
    let background: EffectRGBA
}

enum ASCIIColorRecentStore {
    static let maxCount = 5
    static func load() -> [ASCIIColorPair]
    static func remember(_ pair: ASCIIColorPair)  // 去重置顶，截断到 maxCount
}
```

- 处理管线只读 `EffectRGBA`，不依赖 `SwiftUI.Color`。
- 内置 5–6 组成套主题常量（经典、琥珀、蓝白、纸墨、终端绿等）；点主题 = 写入 `asciiForeground` / `asciiBackground`。
- 不另存 `themeID`。当前双色与某主题相等（容差比较）则高亮该主题；否则视为自定义。
- `ASCIIColorRecentStore` 跟 `VoicePitchStore` 一样用 `UserDefaults`；存 JSON/`Codable` 数组即可。

**何时写入最近色**

- ColorPicker 改完前景或背景后，对当前 `ASCIIColorPair` 调用 `remember`。
- 若该对已在列表中：移到最前，不重复。
- 若与某内置主题完全相同：仍可写入最近列表（用户主动调到同色也算一次使用）；UI 上最近区与主题区可并存，点谁用谁。
- 点主题或点最近色：只写入当前 `ProcessingOptions`，**不**因此再 `remember`（避免点一下主题就污染最近列表；主题本身常驻）。
- 不在预览重跑路径里写磁盘。

## 2. 处理层

- `makeASCIIGlyphTiles(cellSize:foreground:)` 用传入前景色绘制字形，去掉写死的 `UIColor`。
- `asciiImage(for:)` 背景改为 `CIImage(color: asciiBackground)`。
- `FrameEffectProcessor` 初始化时按当前 options 的颜色与 `strength` 建 tile；颜色或 cell 尺寸变化时需重建（与现有 strength 行为一致）。
- 导出与预览都经同一 `ProcessingOptions` / `FrameEffectProcessor`，无单独着色路径。
- 最近色存储不参与处理管线，只服务 UI。

## 3. 编辑页 UI

仅在 `options.style == .ascii` 时，强度滑条下方显示「ASCII 颜色」区块：

1. **主题色点行**：每个主题一个圆点，用内外圈或上下半表示前景/背景；选中有描边。点击写入双色。
2. **最近色**：主题右侧或下一行（有条目才显示）；同样成对色点，点击写入双色；选中高亮规则与主题相同（按当前双色匹配）。
3. **自定义入口**：同行末尾按钮；展开后两个 `ColorPicker`（字符色、背景色）。任一变更写入 options，并 `remember` 当前成对色；主题/最近高亮按匹配刷新。
4. **文案**：`Localizable.xcstrings` 增加简中 / 繁中 / 英文 / 日文（区块标题、前景/背景、最近、自定义、主题名）。
5. **不变**：强度滑条仍表示 cell 尺寸；模糊 / 像素化不出现颜色控件。

预览刷新：`videoEffectToken`（或等价依赖）拼接 foreground / background，改色立即重跑预览。

## 4. 文件改动（预期）

| 文件 | 改动 |
| --- | --- |
| `ios/Jingyin/App/Models.swift` | `EffectRGBA`、`ASCIIColorPair`、`ASCIIColorTheme`、`ASCIIColorRecentStore`、options 双色字段 |
| `ios/Jingyin/App/VideoProcessor.swift` | glyph / 背景使用 options 颜色 |
| `ios/Jingyin/App/EditorView.swift` | ASCII 颜色 UI（主题 + 最近 + ColorPicker）；`videoEffectToken` 含颜色 |
| `ios/Jingyin/Localizable.xcstrings` | 四语文案 |

## 5. 验收

1. 切到 ASCII，默认外观与改前一致。
2. 点主题 → 预览立刻变色；导出同色；最近列表不被主题点击改写。
3. ColorPicker 改前景/背景 → 预览更新；该成对色进入最近列表（去重置顶，最多 5）。
4. 杀进程重开 App → 最近色仍在；点最近色可恢复到 options。
5. 再点某主题 → 覆盖当前双色；最近列表保留。
6. 切到模糊再回 ASCII → 当前会话内颜色仍在。
7. `xcodebuild` 针对 iOS Simulator 编译通过。

## 6. 明确依赖真机 / ASC 的项

无。本功能不涉及 StoreKit、App Store Connect 或必须真机才能验证的能力；真机仅作观感确认可选。
