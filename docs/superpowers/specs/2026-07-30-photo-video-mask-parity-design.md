# 照片 / 视频遮罩与选项对齐

日期：2026-07-30  
状态：已定稿，已实现

## 目标

1. 照片批量编辑的**处理选项**与视频一致（遮盖范围、处理档位、强度、ASCII 颜色）；声音与播放器仍只属于视频。
2. 视频自动识别结果改成与照片相同的**可操作实体列表**：可单独选中、删除（关闭）某个主体，而不是只能按「人 / 脸 / 宠物」整类开关。
3. 识别与效果合成尽量共用数据形状；不做大范围 SwiftUI 组件拆分。

## 非目标

- 不开放「指定人脸跟踪」完整产品（真机矩阵未达标前仍隐藏现有原型）。
- 不把每帧全尺寸实例蒙版落盘；不做长视频中断恢复。
- 不抽一堆抽象 OptionSection 组件；只在数据层与检测输出上对齐。
- 不改付费边界、导出时长/分辨率规则。

## 决策摘要

| 项 | 选择 |
| --- | --- |
| 照片选项 | 补齐 `scope` / `quality` / `strength` / ASCII 色；沿用同一 `ProcessingOptions` |
| 视频实体 | 自动检测 → 会话内 `MaskEntity` 列表；删除 = 该实体 `isEnabled = false`（或移出启用集） |
| 跨帧关联 | 导出/预览逐帧检测 + IoU 匹配到已有实体 ID；匹配失败则新建临时实例（默认启用，除非用户整类关掉） |
| 种类开关 | 保留「人 / 脸 / 宠物」作为**检测过滤器**；过滤后的实例进入列表 |
| 效果路径 | 继续 `FrameEffectProcessor`；启用实体合成 `externalMask`（或等价），处理器内不再把「整类合并蒙版」当成唯一自动源 |
| UI 复用 | 照片页复用视频页已有控件模式（Collapsible + Picker/Slider/ASCII）；不强制抽共享 View 文件，允许小幅复制后收敛 |

---

## 1. 数据模型

```swift
struct MaskEntity: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var kind: SubjectKind          // person / face / pet
    var source: MaskTrackSource    // detected* or manual
    var isEnabled: Bool
    /// 最近一帧（或照片）的归一化外接框，供列表与点选
    var lastRect: NormalizedVideoRect
    /// 照片：引用 PhotoMaskPlane + label；视频：通常为空，蒙版按帧现算
    var maskPlaneID: UUID?
    var instanceLabel: UInt16?
}
```

- 照片现有 `PhotoMaskGroup` **映射或渐进改名为**同一语义（保留 plane/label）；手动补的椭圆/矩形仍是 `MaskTrack`，或一并收成 `MaskEntity(source: .manual)` + 几何。
- 视频：`ProcessingOptions.subjects` 仍表示「要检测哪些种类」。新增会话态 `maskEntities: [MaskEntity]`（不必 Codable 进导出设置文件；跟当前 `maskTracks` 一样挂在编辑会话）。
- 用户删某个自动实体：`isEnabled = false`，不从列表立刻抹掉（便于误删找回可选，首发也可直接 remove——实现选 **remove / disable 二选一：推荐 disable + 列表仍显示已关闭**，照片保持现有「删除即消失」也可，两边交互允许照片删、视频关）。

**首发交互定案（简单优先）**

- 照片：维持现状——删除实体即从 `maskGroups` 移除。
- 视频：删除自动实体 = 加入 `disabledEntityIDs: Set<UUID>`（或 `isEnabled = false`）；列表仍可看到并重新打开。手动 `MaskTrack` 行为不变（真删）。

跨帧：每帧检出的框与上一帧/实体 `lastRect` 算 IoU；高于阈值（建议 0.3）则继承同一 `id`；否则新 `id`（默认 enabled）。用户关掉的 id 在后续帧若 IoU 仍匹配同一轨迹，继续禁用。

---

## 2. 处理层

### 照片（增量）

- 预览/导出已走 `FrameEffectProcessor` + `externalMask`：保持。
- UI 写入完整 `ProcessingOptions`（scope、quality、strength、ascii 色）；`optionsForPhoto` 仍清空 `subjects`、只留无 edge 的几何 track。
- quality 影响照片安全膨胀/羽化（已由 FrameEffectProcessor 读取）；档位 UI 出现即可。

### 视频（行为变化）

当前：`subjectMask` 按种类合并 → 一张位图 + 全部 `maskTracks`。

改为：

1. 按 `subjects` 过滤种类，逐帧检出实例框/蒙版。
2. IoU 关联到 `maskEntities`；跳过 `!isEnabled`。
3. 启用实例的蒙版 OR 在一起，再与手动 `maskTracks` 合成。
4. `scope == .background / .full` 逻辑不变（先得主体联合蒙版再反相或全画面效果）。

预览路径必须与导出同一套「实体启用」规则，避免预览能删、导出又糊回去。

性能：precise 档可继续用现有高精度分割；fast/balanced 可用框或较低频检测。不在此方案引入新模型。

---

## 3. UI

### 照片 `PhotoBatchEditorView`

在主体与效果之间或效果区内补齐：

- 遮盖范围 `MaskScope`（segmented）
- 处理档位 `QualityMode` + detail 文案
- 强度 Slider（随 style 切换默认值，与视频一致：blur 32 / pixel 24 / ascii 14）
- `style == .ascii` 时 ASCII 主题 + 最近色 + ColorPicker（可直接搬 `EditorView` 的 `asciiColorControls` 逻辑，允许暂时复制）

不出现：音频、播放器、时间轴、蒙版出现/结束时间。

### 视频 `EditorView`

- 主体种类开关保留。
- 增加与照片类似的「蒙版 / 实体」条：自动实体 + 手动 track 统一编号展示；选中后可删（自动）或进入现有手动编辑。
- 指定人脸跟踪入口继续按 TODO 隐藏。

---

## 4. 文件改动（预期）

| 文件 | 改动 |
| --- | --- |
| `Models.swift` | 如需：`MaskEntity` 或视频会话用的禁用 ID 集合说明 |
| `PhotoBatchEditorView.swift` | scope / quality / strength / ASCII |
| `EditorView.swift` | 自动实体列表 UI；预览 token 含实体启用状态 |
| `VideoProcessor.swift` / `FrameEffectProcessor` | 按实体启用合成蒙版；IoU 关联 |
| `PhotoProcessor.swift` | 尽量少改；必要时与共享检测辅助对齐 |
| `Localizable.xcstrings` | 若有新文案则四语 |
| `docs/ios-launch-todo.md` | 勾选/注明照片选项对齐与视频实体化进度 |

可选后续（本方案不强制本轮做完）：抽出 `SubjectDetection.swift` 供照片与单帧共用。

---

## 5. 验收

1. 照片：改 scope / quality / strength / ASCII 色后预览与导出一致；无音频控件。
2. 视频：多人画面能在列表看到多个自动实体；删除其中一个后，预览与导出仅其余主体被遮盖。
3. 关掉某实体后 scrub 时间轴，该人再次出现仍保持关闭（IoU 继承）。
4. 手动椭圆/矩形仍可加、拖、删；与自动实体同时生效。
5. `xcodebuild` simulator 编译通过。
6. 横竖视频各至少一条短素材目视确认。

## 6. 依赖真机 / ASC

- IoU 在交叉、快速出入画时的误关联：需真机矩阵再收；首发以「能单独关掉且多数镜头可用」为准，不承诺指定人脸跟踪级稳定。
- 无 ASC / StoreKit 依赖。

## 7. 明确不做的退路

若视频实体化在实现中发现必须重写半条导出管线且威胁上架排期：本轮只交付**照片选项对齐**，视频实体化单开后续计划；设计决策仍保留。
