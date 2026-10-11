# iOS 1.0.3 (8) 发布记录

## 本次内容

将 2026-09-21 已实现、尚未发版的界面优化纳入本次发布：照片预览请求一致性与失败重试、照片编辑和结果的共享只读缩放检查、视频结果比例与全屏返回时的文件/播放器保留、编辑工具选中和按压反馈、6 个新增四语文案。处理器、StoreKit 权益和隐私数据处理方式未改变。

版本号在 `ios/Jingyin.xcodeproj/project.pbxproj` 从 1.0.2 (7) 更新为 1.0.3 (8)。原有未提交代码与其他网页、素材实验均保留，没有整体提交或覆盖它们。

## 商店素材与文案

- 简中、繁中、英文、日文各 5 张，共 20 张，1320 × 2868 RGB PNG。
- 顺序：视频遮脸 → 照片批量 → 本地处理/不上传 → 手动补遮 → 全屏放大复核。
- 全部界面来自当前源码的 iPhone 16 Pro Max / iOS 18.1 Simulator 实际截图；使用仓库已有示例照片。视频示例是示例照片生成的 10 秒静态片段，用于界面取景，不作为跨帧跟踪验证。
- 第二张明确说明批量导出需永久版，免费每次导出 1 张。
- 素材、原始截图、HTML 排版源与总览：`artifacts/app-store-1.0.3/`。
- 本次实际文案以 `artifacts/asc/listing-1.0.3.json` 为准；本地持久化核对结果：`artifacts/app-store-1.0.3/metadata-verified.json`。名称、副标题和原描述沿用 1.0.2；新增关键词及本次更新说明，恢复新版本空白的推广文本，并在审核备注追加本次变更范围。
- 关键词依据产品功能和场景补充；没有关键词搜索量、排名或新增转化效果的验证证据。
- 本轮先完成截图；没有制作或上传 App 预览视频。

## 本次验证

- 当前源码 Debug Simulator 构建通过：`/tmp/jingyin-release-103-build.log`。
- 最终 1.0.3 (8) Release 签名归档通过：`artifacts/release/Jingyin-1.0.3-build8.xcarchive`，`/tmp/jingyin-release-103-archive.log`。
- Xcode App Store Connect 上传成功：`/tmp/jingyin-release-103-upload.log`，构建 8 已在版本选择列表中可选。
- 本轮实际操作检查了四语视频人脸遮盖、矩形手动补遮、三张照片切换与预览、照片全屏检查的 100% → 150% 放大，以及四语首页隐私提示。
- `git diff --check -- ios docs/ios-launch-todo.md` 通过。
- 30 秒 / 1 分钟 / 3 分钟、横竖屏、原声 / 静音 / 变音、取消 / 失败重试的既有回归记录见 [2026-09-21 验证](./ios-ui-polish-validation-2026-09-21.md)。这些是之前的模拟器回归，本轮没有重新跑完整导出矩阵。
- 真实 iPhone 手势与 VoiceOver、低性能设备完整矩阵、真实购买/恢复仍不由本次模拟器截图和签名归档证明，保留原 TODO。

## App Store Connect 状态

2026-10-11 23:18（Asia/Shanghai）已提交 1 个项目：iOS App `1.0.3 (8)`。界面显示「已提交 1 个项目」及「正在等待审核」，旧版 `1.0.2` 仍可分发。审核提交 ID：`c9af2561-9852-4a33-abf6-4402044bf163`。既有版本设置为审核通过后自动发布；保留已有发布方式与评分。

后台截图记录核对确认四语各 5 张，依次 `01.png` 至 `05.png`，1320 × 2868，文件大小与本地输出逐张一致，全部 placement 为 ACTIVE，素材为 PREPARE_FOR_SUBMISSION。证据保存在 `assets-verified.json`、`submission-receipt.txt`、`submission-confirmation.png`。
