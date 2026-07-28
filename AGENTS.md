# 镜隐仓库开发规则

## 开始任何 iOS 工作前

先完整阅读以下两份文档，并以它们的最新内容为产品和发布依据：

1. [`docs/ios-app-plan.md`](docs/ios-app-plan.md)：iOS 首发目标、技术架构、设备策略和验收指标。
2. [`docs/ios-launch-todo.md`](docs/ios-launch-todo.md)：当前 P0/P1 TODO、StoreKit 2 付费边界和 App Store Connect 操作步骤。

如果代码、旧对话或旧 README 与这两份文档冲突，先指出冲突，再按文档中的当前决策执行；不要自行恢复已放弃的产品方向。

## 当前产品决策

- 首发平台是 iOS；Android、鸿蒙和 vlog 专项都延后。
- 产品是端侧视频隐私处理工具：原视频、识别数据和导出结果不上传服务器。
- 首发重点是短视频可靠完成，不承诺十几分钟 vlog、后台处理、4K/HDR 保留或中断恢复。
- 付费模型是免费下载安装 + Non-Consumable 一次买断，不做订阅、不加广告。
- 永久版 Product ID 固定为 `com.reaidea.jingyin.lifetime`。
- 免费用户可以完整编辑和预览，但只能导出前 30 秒、最高 720p、无水印；买断后解除这些限制。
- ¥28 / $4.99 是当前首发价格决策。需要改价格、付费边界或产品类型时，必须同步更新 `docs/ios-launch-todo.md`，不能只改 UI。
- “指定人脸、手动椭圆/矩形蒙版、拖动缩放、单个蒙版扩大/缩小和简单跟踪修正”是当前最重要的下一阶段能力。

## iOS 技术约束

- 工程位于 `ios/`，使用 Swift 6、SwiftUI，最低支持 iOS 17。
- 视频处理使用 AVFoundation/AVKit，图像效果使用 Core Image，Vision/Core ML 只在设备本地运行。
- 模型加载、视频帧读取、Vision 推理、蒙版合成、音频离线渲染和编码不能阻塞主线程。
- 所有导出能力必须同时在预览和最终导出路径中生效，不能只做界面展示。
- 免费版限制必须在 `VideoProcessor` 等处理器内部再次强制，不能只依赖导出设置页隐藏选项。
- 付费权益应通过 StoreKit 2 的当前交易权益判断；不要用 UserDefaults 伪造生产权益。
- IAP 产品价格显示使用 StoreKit 返回的本地化价格，不要在代码中硬编码货币字符串。
- 导出取消、失败、重试、成功和离开项目时清理输入副本、输出临时文件和中间文件。
- 预览坐标、视频坐标和导出坐标必须使用明确的归一化转换；横屏、竖屏和 preferredTransform 都要验证。

## 功能开发优先级

按以下顺序推进，不要为了扩大功能范围跳过稳定性：

1. 可靠导入、预览、导出、取消、重试、临时文件清理和预计耗时。
2. 可控遮盖：`MaskTrack` 数据模型、指定人脸、手动形状、拖动/缩放、关键帧和跟踪丢失修正。
3. StoreKit 2：买断、免费 30 秒/720p、恢复购买、Sandbox/TestFlight 验证。
4. 隐私表达：默认推荐像素化、区分视觉模糊和隐私级像素化、清除导出 metadata。
5. 真机矩阵测试和商店提交材料。

除非用户明确要求，否则不要把工作切换到长 vlog、4K/HDR、后台处理、复杂全身人物身份追踪或 Android。

## 修改代码时的协作规则

- 先检查 `git status`，保留用户已有的未提交改动；不要 reset、checkout 或覆盖无关文件。
- 修改前先定位现有实现，不要重复创建已有的处理、定位或清理逻辑。
- 新增用户可见文本时，同时更新 `ios/Jingyin/Localizable.xcstrings` 的简中、繁中、英文和日文。
- 完成一个 P0 TODO 后，更新 `docs/ios-launch-todo.md` 的勾选状态和必要说明。
- 发现源码与文档不一致时，优先修正文档或在交付说明中明确未完成项；不要默默改变产品承诺。
- 不要把 Sandbox、Xcode `-storekitUnlocked` 调试钩子或本地 StoreKit Configuration 当成真实生产购买验证。

## 验证要求

至少完成与改动规模匹配的验证：

```bash
cd ios
xcodebuild -project Jingyin.xcodeproj \
  -scheme Jingyin \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  CODE_SIGNING_ALLOWED=NO build
```

涉及导出时，至少验证 30 秒、1 分钟和 3 分钟素材，以及横屏/竖屏、原声/静音/变音、取消和失败重试。涉及付费时，至少验证免费路径、买断路径、购买取消、恢复购买和产品不可用时的降级提示。

最终交付必须说明：改了哪些文件、哪些测试通过、哪些仍依赖 App Store Connect 或真实 iPhone，不能只说“已完成”。
