# 照片/视频遮罩与选项对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 照片编辑选项与视频对齐；视频自动遮盖改为可单独开关的实体列表（IoU 跨帧继承）。

**Architecture:** `MaskEntity` 挂在 `ProcessingOptions`；`MaskEntityAssociation` 做 IoU 匹配；`FrameEffectProcessor` 按启用实体合成自动蒙版；照片页补齐 scope/quality/strength/ASCII；视频编辑页展示实体芯片并可开关。

**Tech Stack:** Swift 6、SwiftUI、Vision、Core Image、String Catalog

## Global Constraints

- 最低 iOS 17；改动限 `ios/`、`docs/ios-launch-todo.md`、本 plan/spec
- 用户可见新文案必须四语：简中 / 繁中 / 英文 / 日文
- 预览与导出共用同一 `ProcessingOptions.maskEntities` 启用状态
- 不开放指定人脸跟踪产品入口；不改付费边界
- 不提交 git，除非用户明确要求

---

### Task 1: MaskEntity 数据模型与 IoU 关联

**Files:**
- Modify: `ios/Jingyin/App/Models.swift`
- Create: `ios/Jingyin/App/MaskEntityAssociation.swift`
- Modify: `ios/Jingyin.xcodeproj/project.pbxproj`（若工程非文件夹自动引用则加入新文件）

**Interfaces:**
- Produces: `MaskEntity`, `ProcessingOptions.maskEntities`, `MaskEntityAssociation.associate(existing:detections:)` → `[MaskEntity]`
- IoU 阈值 `0.3`；同 kind 一对一匹配；未匹配检测 → 新实体 `isEnabled: true`；已有实体保留 `isEnabled`

- [ ] **Step 1:** 在 `Models.swift` 的 `ProcessingOptions` 前加入：

```swift
struct MaskEntity: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var kind: SubjectKind
    var source: MaskTrackSource
    var isEnabled: Bool
    var lastRect: NormalizedVideoRect

    init(
        id: UUID = UUID(),
        kind: SubjectKind,
        source: MaskTrackSource,
        isEnabled: Bool = true,
        lastRect: NormalizedVideoRect
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.isEnabled = isEnabled
        self.lastRect = lastRect
    }
}
```

并在 `ProcessingOptions` 增加 `var maskEntities: [MaskEntity] = []`。

- [ ] **Step 2:** 新建 `MaskEntityAssociation.swift`：

```swift
import CoreGraphics
import Foundation

enum MaskEntityAssociation {
    static let iouThreshold = 0.3

    struct Detection: Equatable {
        var kind: SubjectKind
        var source: MaskTrackSource
        var rect: NormalizedVideoRect
    }

    static func associate(
        existing: [MaskEntity],
        detections: [Detection]
    ) -> [MaskEntity] {
        var unmatched = existing
        var result: [MaskEntity] = []
        var usedExisting = Set<UUID>()

        for detection in detections {
            var bestIndex: Int?
            var bestIoU = iouThreshold
            for (index, entity) in unmatched.enumerated() {
                guard entity.kind == detection.kind,
                      !usedExisting.contains(entity.id) else { continue }
                let score = iou(entity.lastRect, detection.rect)
                if score >= bestIoU {
                    bestIoU = score
                    bestIndex = index
                }
            }
            if let bestIndex {
                var matched = unmatched[bestIndex]
                usedExisting.insert(matched.id)
                matched.lastRect = detection.rect
                matched.source = detection.source
                result.append(matched)
            } else {
                result.append(
                    MaskEntity(
                        kind: detection.kind,
                        source: detection.source,
                        lastRect: detection.rect
                    )
                )
            }
        }

        // Keep disabled entities that temporarily left the frame so scrubbing
        // can re-associate without resetting the user's off switch.
        for entity in existing where !usedExisting.contains(entity.id) && !entity.isEnabled {
            if !result.contains(where: { $0.id == entity.id }) {
                result.append(entity)
            }
        }
        return result
    }

    static func iou(_ a: NormalizedVideoRect, _ b: NormalizedVideoRect) -> Double {
        let ar = a.cgRect
        let br = b.cgRect
        let inter = ar.intersection(br)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let union = ar.width * ar.height + br.width * br.height - interArea
        guard union > 0 else { return 0 }
        return Double(interArea / union)
    }
}
```

确认 `NormalizedVideoRect` 已有 `cgRect`（若无则用现有转换）。

- [ ] **Step 3:** 用小段 smoke 或编译确认类型可用（随 Task 4 的 xcodebuild）。

---

### Task 2: 照片选项对齐（scope / quality / strength / ASCII）

**Files:**
- Modify: `ios/Jingyin/App/PhotoBatchEditorView.swift`
- Modify: `ios/Jingyin/App/EditorView.swift`（将 `ASCIIColorSwatch` / 如需的辅助改为 fileprivate 可复用，或把 swatch 挪到独立小文件；优先：在 Photo 页内复制最小 ASCII UI + 共用已有 localization keys）

**Interfaces:**
- Consumes: `ProcessingOptions`、`MaskScope`、`QualityMode`、`EffectStyle`、`ASCIIColorTheme`、`ASCIIColorRecentStore`
- ASCII 默认强度与视频一致：`blur 32 / pixel 24 / ascii 14`

- [ ] **Step 1:** 在 `PhotoBatchEditorView` 的 `subjectOptions` 与 `effectOptions` 之间插入 scope + quality；在 `effectOptions` 内加 strength slider 与 ASCII 色区。
- [ ] **Step 2:** `onChange(of: options.style)` 的 ascii 默认改为 `14`；`onChange` 覆盖 scope/quality/strength/ascii 色时 `invalidateOutputs` + `refreshPreview`。
- [ ] **Step 3:** 模拟器编译通过（与 Task 4 合并亦可）。

---

### Task 3: FrameEffectProcessor 按启用实体合成

**Files:**
- Modify: `ios/Jingyin/App/VideoProcessor.swift`（`FrameEffectProcessor`）

**Interfaces:**
- Consumes: `options.maskEntities`, `MaskEntityAssociation`
- 检测帧产出 `[Detection]`（face 多框、pet 多框、person 尽量 instance；失败则单个人体语义/框）
- 每检测帧：`liveEntities = associate(existing: liveEntities, detections:)`；仅 `isEnabled` 的实体参与蒙版
- `options.maskEntities` 为空且 subjects 非空时：首帧检测后填充 liveEntities（全启用），行为兼容旧「整类遮盖」
- 处理器持有 `private var liveEntities: [MaskEntity]`，init 从 `options.maskEntities` 拷贝
- 暴露只读 `currentEntities` 或通过 callback 不必要——导出后 UI 以编辑会话实体为准；预览路径由 Editor 写入 options

- [ ] **Step 1:** 把 `subjectMask` 改为实例级：返回启用实体联合蒙版；禁用实体的框/实例不画入。
- [ ] **Step 2:** face/pet 按框分别匹配实体；person 优先 instance mask（参考 `PhotoProcessor.personGroups` 的 Vision API，视频侧可简化：有 instance 则逐 label，否则整块语义蒙版作为一个 person 实体）。
- [ ] **Step 3:** 保证 `externalMask` 与手动 `maskTracks` 合成逻辑不变。

---

### Task 4: 视频编辑页实体列表 UI + 预览同步

**Files:**
- Modify: `ios/Jingyin/App/EditorView.swift`
- Modify: `ios/Jingyin/Localizable.xcstrings`（新 key 四语）
- Modify: `docs/ios-launch-todo.md`

**Interfaces:**
- 主体区下增加实体芯片：显示 kind 图标 + 序号；点击选中；关闭/重新打开切换 `isEnabled`
- `videoEffectToken` 拼接各实体 `id+isEnabled`
- 在预览 `applyPreview` / playhead 变化时（可跟现有 mask preview 刷新），用当前帧轻量检测更新 `options.maskEntities`（保留 isEnabled）
- 种类 `subjects` 变更时：移除不再检测的 kind 的实体，或保留但检测过滤器不产生新检测

Localization keys（示例）:
- `editor.entities` / `editor.entityOn` / `editor.entityOff` / `editor.entityHint`

- [ ] **Step 1:** UI + token + 开关逻辑
- [ ] **Step 2:** 当前帧刷新实体列表（复用处理器检测或抽 `detectVideoEntities(in: CIImage) -> [Detection]` 为 FrameEffectProcessor 的 static/package 方法）
- [ ] **Step 3:** 更新 `docs/ios-launch-todo.md` 照片选项对齐与视频实体化说明；spec 状态改为已定稿
- [ ] **Step 4:**

```bash
cd ios
xcodebuild -project Jingyin.xcodeproj -scheme Jingyin -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`

---

## Spec coverage

| Spec 项 | Task |
| --- | --- |
| 照片 scope/quality/strength/ASCII | 2 |
| 视频 MaskEntity + disable | 1, 3, 4 |
| IoU 0.3 跨帧 | 1, 3 |
| 种类开关作过滤器 | 3, 4 |
| FrameEffectProcessor 启用实体 | 3 |
| 不开放指定人脸跟踪 | 4（不改隐藏状态） |
| launch-todo 更新 | 4 |

## Self-review

- 无 TBD 占位
- `NormalizedVideoRect.cgRect` 实现前先确认现有 API 名
- 新文件若 Xcode 同步组未自动包含，必须加入 pbxproj 或确认 `PBXFileSystemSynchronizedRootGroup`
