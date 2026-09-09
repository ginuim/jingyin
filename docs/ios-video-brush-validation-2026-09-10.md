# 视频画笔与全屏预览验证（2026-09-10）

## 当前实现

- 主编辑页“添加蒙版”与照片使用相同入口文案，支持椭圆、矩形和手绘区域；画笔大小在绘制时显示，松手完成一笔，再次添加可继续补充。
- `NormalizedMaskPath` 移到 `MaskTrack.swift` 供照片和视频共用。视频轨迹可携带手绘路径，固定位置默认覆盖整段，位置记录通过同一归一化矩形变换笔触。移动/缩放/时段/撤销继续使用现有轨迹逻辑。
- 视频复用 `PhotoFreehandMaskOverlay` 和照片蒙版栅格化；最终导出与播放器预览均进入 `FrameEffectProcessor`。固定笔触缓存一张蒙版，动画变更替换缓存，不累计保存逐帧图片。
- 贴纸模式的手绘区域按照片的画笔贴纸处理，不把手绘包围盒当成人脸贴纸框。
- 进入画笔时提高画面占比，完成后恢复常规区域工具布局。
- “出现时段与移动”折叠展示，移除重复标题及展开入口。手绘选中框仅作为变换边界，不填充矩形覆盖色。
- 全屏仅保留视频与播放进度，手动编辑留在主工作区。使用可用高度扣除播放控制栏，不再固定只占 45%。
- 新增文案包含简中、繁中、英文、日文；没有修改付费边界、识别数据存储或网络行为。

## 已完成

- Swift 6 / iPhone 16 / iOS 18.1 模拟器 `xcodebuild` 编译通过。
- 原有 `MaskTrackValidation.swift` 通过：归一化坐标、固定位置、时段、插值、旧数据解码和撤销所需的数据往返。
- 新增 `FreehandTrackValidation.swift` 通过：画笔固定位置、移动、关键帧缩放、出现时段、Codable 往返、边缘单点。
- 独立模拟器验证 App（`ios/Validation/VideoBrushExportValidation.swift`，不编入正式 App）：360×640 / 640×360 上照片和视频手绘蒙版像素一致。
- 实际 `VideoProcessor` 导出：30 秒竖屏原声（免费）、60 秒横屏静音（调试永久权限）、180 秒横屏原声（调试永久权限）、30 秒竖屏变音均成功。180 秒源片容器输出为 180.0467 秒。
- 处理中取消后未发布输出；无效输入失败后，用有效素材重试成功。`cancel()` 保留旧阶段值，因此验证以不发布结果为准，不把阶段字符串作为取消终态。
- 模拟器界面检查：添加菜单包含三种蒙版、画笔参数和完成一笔后的区域选择，撤销可移除新区域；全屏竖屏完整视频与播放控制可见，未出现手动编辑面板。

结果日志：`artifacts/ios-video-brush-2026-09-10/export-results.txt`。

## 未通过及待验收

- **180 秒横屏变音导出失败**，错误为“无法完成导出：这项操作无法完成”。同一素材移除全部手动轨迹后仍失败，不能计为本次画笔回归通过；需后续定位现有变音/分段导出链路。30 秒变音成功。
- 真机连续手绘手感、笔触边缘、移动/缩放和逐段位置动画仍须真实 iPhone 验收；模拟器不能替代触屏手感。
- 90°/180° `preferredTransform` 的最终像素检查、四语完整界面、VoiceOver、大字体和小屏交互矩阵尚未完成。
- 未进行 App Store Connect 操作。真实购买、恢复及 TestFlight 仍按发布 TODO 验收；上述 `.lifetime` 测试只用于处理器分支验证。

## 重跑模型测试

```bash
swiftc ios/Jingyin/App/MaskTrack.swift ios/Validation/MaskTrackValidation.swift -o /tmp/jingyin-mask-validation
/tmp/jingyin-mask-validation
swiftc ios/Jingyin/App/MaskTrack.swift ios/Validation/FreehandTrackValidation.swift -o /tmp/jingyin-freehand-validation
/tmp/jingyin-freehand-validation
```

独立导出验证 App 使用 `/tmp/jingyin-brush-fixtures/` 中的 `portrait30.mp4`、`landscape60.mp4`、`landscape180.mp4`；合成素材为 12 fps 测试图加 440 Hz 音轨，180 秒片由 60 秒片循环复制。将 `App/` 下除 `JingyinApp.swift` 外的源码与验证入口一起编译为模拟器可执行文件，放入独立 bundle ID `com.reaidea.jingyin.brushvalidation` 的临时 App。日志输出 `/tmp/jingyin-brush-results.txt`，不修改正式 App 的启动入口。

界面截图：[手动面板](../artifacts/ios-video-brush-2026-09-10/manual-panel.png) · [全屏预览](../artifacts/ios-video-brush-2026-09-10/fullscreen.png)。
