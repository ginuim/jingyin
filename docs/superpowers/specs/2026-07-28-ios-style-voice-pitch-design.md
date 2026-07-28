# iOS 样式轻量打磨 + 变音（实时试听与导出）

日期：2026-07-28  
状态：已定稿，待实现计划

## 目标

1. 编辑页与首页做样式 A：轻量打磨现有深绿 / mint 视觉，不重做品牌气质。
2. 补齐 web 已有的变音能力：原声 / 变音 / 静音，音调 -8～+8 半音（默认 -4），真正改音调不改语速。
3. 变音支持编辑页实时试听，以及导出时写入结果文件。
4. 上次音调半音值持久化到 `UserDefaults`。

## 非目标

- 大幅重做视觉（新色板、新字体、首页大改版）。
- 引入 SoundTouch 或其他第三方变调库。
- 重写整条 `AVAssetWriter` 画面编码管线。
- 持久化声音模式（原声 / 变音 / 静音）；只持久化音调。
- 广播级音画同步精度。

## 决策摘要

| 项 | 选择 |
| --- | --- |
| 样式范围 | A：间距、分区标题、声音区布局 |
| 变音范围 | B：导出 + 实时试听 |
| 实现路径 | 方案 1：`AVAudioEngine` + `AVAudioUnitTimePitch` |
| 音调持久化 | `UserDefaults`，key `jingyin.voicePitch` |

## 1. 数据模型

```swift
enum AudioMode: String, CaseIterable, Identifiable {
    case original = "原声"
    case voice = "变音"
    case mute = "静音"
}

struct ProcessingOptions: Equatable {
    var quality: QualityMode = .balanced
    var scope: MaskScope = .subjects
    var style: EffectStyle = .blur
    var audio: AudioMode = .original
    var voicePitch: Int = VoicePitchStore.load() // -8...8，缺省 -4
    var strength = 32.0
    var subjects: Set<SubjectKind> = [.person]
}
```

### VoicePitchStore

- key：`jingyin.voicePitch`
- `load()`：越界或未写入 → `-4`
- `save(_:)`：钳制到 `-8...8` 后写入
- 写入时机：滑条 `onChange` 立即保存
- 不持久化 `audio`；进入编辑页默认仍为原声

### 不变量

- 仅当 `audio == .voice` 时 `voicePitch` 参与预览与导出。
- 预览与导出共用同一份 `ProcessingOptions`，禁止第二套音调状态。
- 切离变音时保留滑条值（内存 + 已落盘）。

## 2. 编辑页 UI（样式 A）

色板、圆角、mint 主色保持不变。

### 全局轻量调整

- 外层设置区 `VStack` 间距统一为 16。
- `OptionSection`：标题与内容间距 12，内边距 14。
- 首页：按钮区上下留白略收；副文案与隐私提示仍用 secondary，仅微调对比，不改色相。

### 声音区

结构对齐 web，视觉保持 iOS 原生分段控件：

```
声音处理                         <元信息>
[ 原声 | 变音 | 静音 ]
[ 低 ———●——— 高 ]               // 仅变音
真正改变音调，不改变语速；播放时拖动可实时试听。
```

元信息：

- 变音：`音调 {±N} 半音`
- 静音：`导出无音轨`
- 原声：`保留视频原声`

交互：

- 切到变音：挂上预览变音轨。
- 拖滑条：实时改 `TimePitch.pitch`，并 `VoicePitchStore.save`。
- 处理页无此控件。

## 3. 预览同步

新增 `VoicePreviewEngine`，由 `EditorView` 持有。`AVPlayer` / `VideoPlayer` 继续负责画面。

### 模式行为

| `audio` | `AVPlayer` 声音 | `VoicePreviewEngine` |
| --- | --- | --- |
| 原声 | 开 | 停止并卸图 |
| 变音 | `isMuted = true` | 播放同源文件，经 TimePitch |
| 静音 | `isMuted = true` | 停止 |

### 音频图

```
AVAudioPlayerNode → AVAudioUnitTimePitch (rate=1, pitch=semitones*100)
  → mainMixer → output
```

### 同步规则

1. 进入变音或换源：按 `player.currentTime()` schedule/seek 音频；视频在播则引擎 `play()`。
2. 监听播放/暂停/seek：引擎跟随 play / pause / reschedule。
3. 滑条变化：只更新 `timePitch.pitch`，不断流。
4. 画面遮盖预览重建 `AVPlayerItem` 后：保持 mute，并重新对齐引擎时间。
5. `onDisappear`：停止引擎并释放 audio session 占用。

### 失败兜底

Engine 初始化失败：footnote 提示「当前无法实时试听变音」；变音模式仍可选，导出走离线管线；预览画面静音。

## 4. 导出管线

画面路径保持：`AVVideoComposition` + `FrameEffectProcessor` + `AVAssetExportSession`。

### 分支

| `audio` | 行为 |
| --- | --- |
| 原声 | 现状不变 |
| 静音 | 现状 `mutedAudioMix` |
| 变音 | 离线渲变音轨，再与处理后视频合成 |

### 变音导出步骤

1. 画面仍走现有 composition（不动）。
2. `VoicePitchExporter`：`AVAudioEngine` 手动渲染，源音轨 → TimePitch（`rate=1`，`pitch=semitones*100`）→ 临时音频文件。
3. 用 `AVMutableComposition`（或等价混流）把变音轨替换原音轨；时长与源对齐，超出裁切、不足补静音。
4. 最终导出 mp4。进度：变音渲染占用编码进度区间的前一小段，避免长时间停在同一百分比。

### 错误与清理

- 无音轨却选变音：按无声成功导出，`advisory`：「视频无音轨，已按无声导出」。
- 变音渲染失败：`stage = failed`，「变音处理失败，可改选原声或静音后重试」。
- 临时变音文件与中间产物在成功 / 失败 / 取消后删除。

## 5. 文件与职责

| 文件 | 职责 |
| --- | --- |
| `Models.swift` | `AudioMode` 增加变音；`voicePitch`；`VoicePitchStore` |
| `EditorView.swift` | 声音区 UI、间距打磨、挂接预览引擎 |
| `ContentView.swift` | 首页轻微留白/对比度 |
| `VoicePreviewEngine.swift`（新） | 实时试听图与同步 |
| `VoicePitchExporter.swift`（新） | 离线变音渲染 |
| `VideoProcessor.swift` | 变音分支接入导出；临时文件清理 |
| `ios/README.md` | 能力列表补上变音与实时试听 |

## 6. 验收

- 编辑页声音三项可选；变音时出现 -8～+8 滑条，默认/恢复为上次或 -4。
- 播放中拖滑条可立即听到音调变化，语速不明显变化。
- 切原声恢复视频原声；切静音无声；切变音再次试听。
- 导出变音结果文件音调与预览方向一致（低半音更低，高等更高）。
- 杀掉 App 再进，滑条恢复上次音调；声音模式仍默认原声。
- 无音轨视频选变音可完成导出并有 advisory。
- 取消处理后临时音频文件不残留。
- 样式：深绿 / mint 未换色；设置区更整齐，无大视觉推翻。

## 7. 测试建议

- 模拟器：带人声短片（仓库 `work/trump-test-h264.mp4`）跑原声 / 变音 / 静音各一趟导出。
- 变音：-8、0、+8、默认 -4 各听预览并抽一档导出对比。
- 重建画面预览（改模糊强度）时确认变音试听不断、时间仍对齐。
- 无音轨或纯画面素材覆盖 advisory 路径。
