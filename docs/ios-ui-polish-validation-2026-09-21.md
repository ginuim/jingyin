# iOS 界面优化第一轮验证（2026-09-21）

## 本轮改动

- `PhotoBatchEditorView.swift`：同一照片更新保留上一次处理效果；切图清除上一张缓存；预览请求使用独立 ID 校验，过期任务不修改结果和加载状态；失败提示与重试；添加独立只读放大检查入口。
- `ZoomablePhotoPreview.swift`（新增）、`PhotoExportSuccessView.swift`：编辑检查和照片结果复用缩放组件，支持 1–4 倍、拖动边界、双击还原、44pt 缩放操作及可访问的倍率。保留完整图片边缘、圆角和轻阴影。检查模式不写入蒙版坐标。
- `ProcessingView.swift`：读取成品的显示方向尺寸，按素材比例和可用高度显示预览；复用全屏预览；进入检查不清理输出，返回不重新开始导出。
- `AppButtonStyles.swift`、`EditorView.swift`、照片工具栏：共享选中与按压样式，未选中工具使用次文本色，当前工具保留橙色。
- `Localizable.xcstrings`：6 个新增键，简中、繁中、英文、日文完整。
- `ios-launch-todo.md`：记录本轮已实现范围与后续项。没有修改购买、隐私数据持久化或处理器算法。

## 构建和静态检查

- iPhone 16 / iOS 18.1 Simulator，Swift 6 Debug `xcodebuild` 通过。
- `git diff --check` 通过。
- 新增 6 个文案键均包含四语非空翻译，字符串目录编译通过。
- Xcode 报告未依赖 AppIntents 时跳过元数据提取的提示；没有 Swift 编译错误。

```bash
xcodebuild -project ios/Jingyin.xcodeproj -scheme Jingyin \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=2F3A1365-63EA-4D65-93C3-1B30625CE00E' \
  -derivedDataPath /tmp/jingyin-ui-review-build \
  CODE_SIGNING_ALLOWED=NO build
```

## 实际模拟器操作

- 双图编辑进入「放大检查」，按钮放大至 250%，拖动、双击回到 100%，关闭后返回原编辑页。
- 临时移走模拟器内两张测试输入副本，切换效果触发读取失败：上一版画面保留，出现本地化错误与「重试」。恢复测试副本后重试成功，错误提示消失。
- 全画面 ASCII 效果切换照片后显示当前照片的处理结果，未停留在前一张照片。
- 免费双图输入实际只生成当前一张，结果页显示 `1/1` 及剩余 1 张未导出，共享缩放操作可见。
- 60 秒横屏结果预览和保存/分享/重新处理操作均可见。
- 30 秒竖屏视频结果预览完整显示，进入全屏可以播放，退出后保留进度及保存/分享操作。进出全屏前后成品文件 SHA-256 相同。
- 深色英文 Accessibility Large 的新增检查页标题、完成按钮、缩放和还原操作可见。

## 导出回归

复用 `ios/Validation/VideoBrushExportValidation.swift`，仅将临时素材和日志路径替换为本轮路径，编译为独立模拟器验证 App；不修改正式 App 的入口。素材是 12fps 合成测试图加 440Hz 音轨，270×480 竖屏、480×270 横屏。

| 用例 | 结果 |
| --- | --- |
| 30 秒竖屏、原声、免费路径 | 通过，成品 30 秒 |
| 60 秒横屏、静音、调试永久路径 | 通过，成品 60 秒 |
| 180 秒横屏、原声、调试永久路径 | 通过，成品 180 秒 |
| 30 秒竖屏、变音、调试永久路径 | 通过，成品 30 秒 |
| 180 秒无手动轨迹的变音基线 | 本轮合成素材通过 |
| 处理中取消 | 通过，未发布输出 |
| 无效输入失败后重试有效输入 | 通过 |
| 照片/视频手绘蒙版栅格一致性 | 360×640、640×360 通过 |

音轨抽样通过：静音低于 −80 dB，原声约 440 Hz，变音约 349.5 Hz；结构和音轨检测分别保存在 `output-probes.json`、`audio-checks.json`。

日志：[export-results.txt](../artifacts/ios-ui-polish-2026-09-21/export-results.txt)。本轮 180 秒变音基线通过不等同于修复此前长视频变音问题：素材、分辨率不同，本次也未改导出算法。

## 截图

- [照片编辑](../artifacts/ios-ui-polish-2026-09-21/photo-editor.png)
- [预览失败与重试](../artifacts/ios-ui-polish-2026-09-21/photo-preview-failure.png)
- [深色英文大字体检查页](../artifacts/ios-ui-polish-2026-09-21/photo-inspection-dark-accessibility.png)
- [竖屏视频结果](../artifacts/ios-ui-polish-2026-09-21/video-portrait-result.png)
- [横屏视频结果](../artifacts/ios-ui-polish-2026-09-21/video-landscape-result.png)

## 仍待验证或后续改动

- 真 iPhone 双指缩放手感、VoiceOver、真实素材和较低性能设备；四语完整界面矩阵。
- 原照片编辑参数面板在大字体下仍拥挤，本轮没有重排该面板。
- 照片撤销、自动识别开关恢复上次选择、首页提示语义属于后续优化。
- 未执行 App Store Connect 操作；真实购买、恢复购买、退款、Family Sharing 仍按发布 TODO 验收。调试永久路径仅验证本地处理分支。
