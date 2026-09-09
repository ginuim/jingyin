# 镜隐 iOS 首发 TODO

更新时间：2026-08-04

## P0：付费闭环

- [x] StoreKit 2 权益状态、交易监听和本地校验
- [x] Non-Consumable 永久解锁购买流程
- [x] 恢复购买
- [x] 免费版导出前 30 秒、最高 720p
- [x] 买断版完整时长与完整导出规格
- [x] 首页展示当前权益与永久解锁入口；导出设置页展示免费版边界
- [x] 设置页展示购买状态、购买和恢复购买
- [x] Developer 注册 Bundle ID `com.reaidea.jingyin`
- [x] App Store Connect 创建 App `镜隐`（Apple ID `6795803353`，SKU `jingyin`，主语言简中）
- [x] App Store Connect 创建 `com.reaidea.jingyin.lifetime`（IAP Apple ID `6795803473`，非消耗型，参考名「镜隐永久版」）
- [x] 配置中国大陆 ¥28（手动覆盖）、美国 $4.99 及其他地区自动换算价（2026-07-30：当前售价维持；美国目标 $9.99 仅稳定后永久改价；大陆先观察不预设涨价，见 [app-store-market-and-pricing.md](./app-store-market-and-pricing.md)）
- [x] IAP 本地化：简中 / 繁中 / 英文 / 日文（上架前须把描述改为「完整视频与照片批量」，见 connect 记录）
- [x] 补充 IAP 审核截图和审核说明（截图：`artifacts/asc/iap-review-640x920.png`）
- [x] App 定价设为 Free（$0.00，175 个国家或地区）
- [x] 签署 Paid Apps Agreement
- [x] 提交银行账户（招商银行，CNY；状态：可用）
- [x] 提交美国税表 W-8BEN + Certificate of Foreign Status（状态：使用中；条约 Article 12 / 10%）
- [x] 国务院令第 810 号合规（状态：有效）
- [x] 等待银行与付费 App 协议审核通过（付费协议：**有效**；DSA：**有效**）
- [x] 开启 Family Sharing（已在 App Store Connect 确认开启；开启后不能关闭）
- [x] 完成欧盟 DSA 交易商声明与联系信息（2026-08-04 核对：**有效**，覆盖欧盟 27 个国家或地区）
- [ ] 创建 Sandbox 测试账号（ASC → 用户和访问 → 沙盒；自动化创建遇 Apple unknown error，需手动建）
- [ ] 真机用 Sandbox 验证：加载商品、购买、取消、恢复、删装再恢复
- [ ] TestFlight 验证真实商店价格与产品 ID
- [ ] 处理器内强制：免费照片每次最多导出 1 张；买断解锁批量（随照片功能一并落地）

### App Store Connect

完整配置与核对记录见 **[app-store-connect.md](./app-store-connect.md)**。

摘要（2026-08-04）：付费协议有效 · 银行可用 · 税表使用中 · Family Sharing 已开 · DSA 有效 · IAP `com.reaidea.jingyin.lifetime` 当前售价 ¥28 / $4.99；美国目标 $9.99（稳定后再改）；大陆观察中。

## P0：可控遮盖

- [x] 建立 `MaskTrack`、归一化坐标和关键帧数据结构
- [ ] 当前画面检测多张人脸并逐个勾选（代码原型已完成，但 2026-07-30 对比发现其一次检测 + 向后追踪的稳定性低于导出时逐帧自动人脸检测；首发界面暂时隐藏，待转头、遮挡和人物交叉的真机矩阵达标后再开放）
- [x] 椭圆、矩形和画笔手绘蒙版（2026-09-10：视频复用照片画笔与栅格化；单个位置记录自然覆盖整段，在其他时间移动或缩放会自动记录并生成位置动画）
- [x] 拖动、缩放和删除蒙版
- [x] 单个蒙版覆盖范围扩大/缩小（当前时间写入关键帧，按中心 10% 调整并保持在归一化画面边界内；预览与导出复用同一 `NormalizedVideoRect`）
- [ ] 连续镜头指定人脸跟踪（`VNTrackObjectRequest` 原型保留，但首发暂不开放；自动人脸遮盖继续使用导出路径的逐帧检测）
- [ ] 指定人脸跟踪丢失提示与修正（交互原型保留，随指定人脸跟踪一起隐藏）
- [x] 确保预览与最终导出坐标一致（人脸检测、Vision、SwiftUI 预览和 Core Image 导出统一使用显示方向归一化坐标；2026-07-30 完成横屏、90° 竖屏与 180° `preferredTransform` 几何矩阵，并用 90° 非对称蒙版对照预览/最终导出落点）
- [x] 收口蒙版编辑交互（全屏入口固定在播放器画面右下角，与是否编辑位置无关；手动蒙版默认覆盖整段视频；出现/结束范围和位置记录收进语义明确的菜单，界面不再使用“全屏 K 帧”等术语）

## P0：隐私与稳定性

- [x] 默认推荐像素化和高强度遮盖（默认隐私级像素化，像素块 24 px）
- [x] 区分“视觉模糊”和“隐私级像素化”（简中 / 繁中 / 英文 / 日文）
- [x] 导出时清除位置、设备和拍摄时间等元数据（所有视频导出、分段合并和变音复用路径均显式清空 metadata；2026-07-30 合成标签视频验证位置与源拍摄时间不再保留）
- [x] 离开项目、取消、失败和完成后清理输入副本与临时文件（结果页内保留成品供保存/分享，离开时删除；启动时兜底清理 `jingyin-` 前缀遗留文件）
- [x] 统一 README、界面和实际视频时长限制（导入层与 `VideoProcessor` 双重强制最长 5 分钟、最大 1 GB）
- [x] 免费/买断导出均覆盖原声、静音和变音（2026-07-30 iOS 18.1 模拟器 35 秒竖屏素材六路径通过：免费版均为 30 秒 / 720p，永久版均保留 35 秒；静音约 -91 dB，-4 半音将 440 Hz 测试音降至约 350–357 Hz；2026-08-25：编辑页和结果预览统一启用 `.playback / .moviePlayback` 声音会话，原声预览不再依赖静音键；真实 iPhone 仍在下方真机矩阵验收）

## P0：照片批量打码（上架硬门槛）

路线：批量统一设置 + 逐张复核；免费每次导出 1 张，买断解锁多图批量。2026-09-09：人脸贴纸（Emoji）已实现并纳入当前商店文案，详见下方已完成项；不改变照片批量的上架验收要求。

2026-09-09 照片复核体验收口：自动分析与查看状态已分离，照片预览成功显示即视为已查看，不增加单独确认按钮和顶部状态条；全批设置与当前照片区域调整已标出作用范围，自动/手动区域分组，画笔参数按上下文显示；免费/永久导出按钮显示实际数量边界，免费结果说明未导出的剩余照片；导出进度改为屏幕中央遮罩卡片，结果页改为无黑底的完整边缘、逐张切换和缩放检查。iPhone 16 / iOS 18.1 模拟器免费双图及调试永久权益 9 图批量路径通过，四语、大字体、真实购买与真实 iPhone 手势仍列入下方验收。

- [x] 首页区分「处理视频」与「处理照片」；照片支持系统相册多选（单批最多 20 张）
- [x] 抽离帧级识别与效果合成，供视频帧与静态图共用（静态图已复用 `FrameEffectProcessor`；视频自动遮盖改为 `MaskEntity` 列表 + IoU 跨帧继承，可单独开关；照片仍用 `PhotoMaskGroup` 逐组删除。2026-08-08：照片编辑页保留 scope / strength / ASCII 等实际生效设置，不提供视频处理档位）
- [x] 顺序处理多图（避免同时解码多张原图）；状态：待处理 / 已识别 / 需复核 / 完成 / 失败
- [x] 批量统一主体与效果；复核页可逐张补充、移动、调整范围、删除蒙版（手动蒙版通过统一“添加蒙版”入口选择椭圆 / 矩形 / 手绘区域，手绘路径使用归一化图片坐标并复用于预览与导出；人物使用 `VNGeneratePersonInstanceMaskRequest` 并与独立的 `VNGeneratePersonSegmentationRequest` 人体语义结果求交，过滤整图误判与边缘离群像素；猫狗检测框匹配 `VNGenerateForegroundInstanceMaskRequest`；人脸使用 `VNDetectFaceRectanglesRequest` 的独立椭圆范围，不绑定可能包含身体的整人前景实例，右下角手柄只调整作用范围而不缩放遮盖纹理；每个精细实体引用共享标签图中的独立实例编号，避免重复保存全尺寸蒙版；失败时回退扩大椭圆 / 矩形安全区；画面点选和蒙版编号列表均可选中；批量统一含遮盖范围 / 强度 / ASCII 色；照片不提供视频处理档位）
- [ ] 导出保持方向与合理分辨率，清除位置 / 设备 / 拍摄时间等 metadata（2026-09-10 发现 `CIContext.writeJPEGRepresentation` 会继承源图 EXIF；已改用 `CGImageDestination` 以空属性字典写入新 JPEG，并在保存到相册时使用当前日期。仍须用真实含 GPS 的照片在 iPhone 相册及导出文件中验收）
- [x] 单张保存或分享；批量逐张报告成败，失败可重试；临时文件清理
- [x] 处理器内强制免费最多 1 张、买断可批量；预览不限（模拟器分别验证免费单张与 `-storekitUnlocked` 两张批量输出）
- [ ] 更新永久版说明、商店文案与 Paywall：永久版 = 完整视频 + 照片批量（App 内四语与文档已更新；App Store Connect 的 IAP 本地化待上架前手工更新）
- [ ] 验收：单张/多图、横竖图、HEIC/JPEG/PNG、旋转、超大图、部分损坏、漏检后手动补充

## P0：真机验收

- [ ] 30 秒、1 分钟、3 分钟视频端到端验证
- [ ] 横屏、竖屏、多人、遮挡、转头和人物进出画面
- [ ] 至少两台不同性能档位的真实 iPhone
- [ ] 购买成功、取消、待批准、恢复、退款和 Family Sharing
- [ ] 导出取消、失败重试、存储不足和临时文件清理

## P1：商店发布

- [x] 隐私政策与 App Privacy 填写（2026-09-03：针对 Guideline 2.1，在简中、繁中、英文、日文政策中新增独立人脸数据章节，明确类型、用途、共享、存储、保留与删除；App Privacy 继续按开发者不收集数据填写）
- [x] 简中、繁中、英文、日文商店文案（2026-08-25：已填写 App Store Connect；文案见 [四语草稿](./app-store-listing.md)）
- [x] 免费版与永久版截图（2026-08-25：四语 iPhone 6.9 英寸截屏及永久版 IAP 审核截图已上传；前三张展示顺序已按当前素材调整）
- [x] TestFlight 内测（2026-08-04：上传 `0.1.0 (1)`，标记为 Internal Testing Only；创建「内部测试」群组并加入 1 位内部测试员，群组自动访问全部构建）
- [x] App Review Notes 说明完全本地处理和 IAP 测试路径（2026-08-25：已随构建 1.0 (3) 填写并提交；[英文草稿](./app-store-listing.md#app-review-notes英文可直接粘贴)）
- [x] 部署更新后的四语隐私政策（2026-09-03：四个线上路径均已核对第 2 节和更新日期）
- [x] 回复 2026-09-02 Guideline 2.1 人脸数据问题并重新提交（2026-09-03 09:15 发送英文回复，09:17 使用原构建 `1.0 (3)` 更新审核；2026-09-07 撤回旧提审的 `1.0.1 (5)`，上传当前工程 `1.0.1 (6)` 并重新提交；当前状态「等待审核」。回复稿见 [App Store Connect 记录](./app-store-connect.md#2026-09-02-guideline-21人脸数据说明)）

## 给负责 App Store Connect 的 LLM：具体操作

### 1. 先完成销售前置条件

在开始创建 IAP 前，确认使用 Account Holder 或 App Manager 角色登录正确的
App Store Connect 团队，并检查以下项目：

- `Business → Agreements` 中的 **Paid Apps Agreement** 已签署且状态为 Active
- `Business → Tax` 中的税务表单已提交
- `Business → Banking` 中的收款银行信息已提交并通过审核
- App 已经在 `Apps` 中创建，Bundle ID 与工程的 `com.reaidea.jingyin` 一致
- App 本身保持 Free 下载，不要把 App 设置成付费下载

Apple 要求签署 Paid Apps Agreement 后才能提供 IAP；收款还需要税务和银行信息。
参考：[签署协议](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/)、
[税务信息](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information)、
[银行信息](https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information)。

### 2. 创建永久买断产品

路径：`Apps → 镜隐 → Monetization → In-App Purchases → +`。

创建 **Non-Consumable In-App Purchase**，严格使用以下字段：

| 字段 | 值 |
| --- | --- |
| Reference Name | `镜隐永久版`（仅内部可见） |
| Product ID | `com.reaidea.jingyin.lifetime` |
| 类型 | Non-Consumable |
| Display Name（简中） | `永久版` |
| Description（简中） | `一次购买，永久解锁完整视频与照片批量处理` |
| Display Name（英文） | `Lifetime Access` |
| Description（英文） | `Unlock full video and batch photo exports` |
| Display Name（日文） | `永久版` |
| Display Name（繁中） | `永久版` |

Product ID 保存后不可编辑，也不能在同一个 App 中复用已删除的 ID，因此必须先核对
拼写和大小写。工程当前 StoreKit 代码已经固定使用这个 ID。

参考：[IAP 字段说明](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)。

### 3. 设置价格和销售地区

进入该 IAP 的 `Price Schedule → Add Pricing`：

- 中国大陆当前价：`¥28`（手动覆盖；先观察，不预设涨到 ¥48/¥68）
- 美国等当前价：`$4.99`（稳定后再评估永久改到 `$9.99`；不排 Temporary 自动涨回）
- 其他国家/地区先使用 Apple 自动生成的可比价格；改美国价时勿连带自动改大陆手动价
- Availability 至少包含 China mainland、United States，以及实际计划上架的地区
- Start Date 设为立即可用；End Date 选择 No End Date
- 不要设置订阅、试用期、Offer Code 或 Promotional Offer 作为首发全站折扣手段
- 定价决策全文见 [app-store-market-and-pricing.md](./app-store-market-and-pricing.md)

如果 Apple 自动生成的价格与目标市场不一致，再单独覆盖对应地区。手动覆盖后，Apple
不会继续自动调整该地区价格。参考：[IAP 价格设置](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/)。

### 4. Family Sharing：先确认再开启

如果产品决定支持家庭共享，在 IAP 详情页的 `Family Sharing` 区域点击 `Turn On`。

这是不可逆操作：开启后不能关闭。开启前必须确认产品 ID、价格和买断模型已经最终确定。
开启后用家庭成员 Apple Account 验证：购买者开启 Purchase Sharing，家庭成员在另一台
设备中恢复购买，检查 `Transaction.currentEntitlements` 能否获得权益。

参考：[开启 Family Sharing](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/)。

### 5. IAP 审核资料

在 IAP 的 `App Review Information` 中填写：

- 上传一张审核截图：展示编辑页和“永久版/免费版”导出设置
- Review Notes 说明：
  - App 不需要登录
  - 视频完全在设备本地处理，不上传服务器
  - 免费用户可预览；视频导出前 30 秒 / 720p；照片每次 1 张
  - 永久版一次解锁完整视频导出与照片批量
  - 点击“永久解锁”即可触发 Non-Consumable 购买
  - Settings → Lifetime Access → Restore Purchases 可恢复购买
  - 若使用 Sandbox，提供测试 Apple Account 和测试步骤
- 审核文案不要写“订阅”“自动续费”或“云端处理”

IAP 必须在提交 App 版本审核前设置好价格，并在版本的 `In-App Purchases and
Subscriptions` 区域勾选该产品一并提交审核。

### 6. Sandbox / TestFlight 验证顺序

1. 等待 IAP 状态从 Draft/Ready to Submit 变为可供 Sandbox 使用；Family Sharing
   或产品元数据变化可能需要等待一段时间。
2. 在 `Users and Access → Sandbox → Test Accounts` 创建 Sandbox Apple Account。
3. 真机退出 App Store 的正式账户；购买弹窗出现时使用 Sandbox 账户，不要使用真实账户。
4. 依次验证：产品加载、购买成功、取消购买、网络失败、重复购买、恢复购买。
5. 删除 App 后重新安装，使用同一 Sandbox 账户点击 Restore Purchases，确认仍解锁。
6. 用 TestFlight 验证真实 App Store 商品价格、中文/英文价格显示和审核版本的产品 ID。
7. 最后再提交 App Review；不要只用 Xcode 本地 StoreKit Configuration 作为最终验证。

工程侧已有 `-storekitUnlocked` Debug 启动参数，只用于不依赖商店的完整导出路径测试；
它不能代替 Sandbox 购买测试。

### 7. App 本身的上架设置

IAP 之外，还要在 App 的版本和通用信息中完成：

- `Pricing and Availability`：App 价格选择 **Free**；Availability 选择计划上架的地区，
  暂不设置预售
- `App Information`：应用名称、字幕、类别、年龄分级、版权和支持 URL
- `App Privacy`：如果当前版本确实没有分析、广告、账号系统或服务器上传，按“Data Not
  Collected”填写；视频、识别结果和导出文件只在设备本地处理，不属于向开发者收集
- `Privacy Policy URL`：填写可公开访问的隐私政策页面，内容要明确“不上传视频”、临时文件
  清理、照片权限和 IAP 处理方式
- `Version → App Review Information`：补充联系方式、审核备注、IAP 测试步骤和截图
- `Version → In-App Purchases and Subscriptions`：勾选永久版产品后，再提交该版本审核

App 定价保持 Free，付费只通过 Non-Consumable IAP 完成。参考：[App 价格与可用性](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability/)、
[App 与 IAP 字段总览](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/)。

## 后续版本

- [x] 人脸贴纸（仅“遮盖范围 = 遮盖主体”且“识别主体 = 人脸”时开放；每张脸按检测框放置一个 Emoji；内置 32 个系统 Emoji，以每页 16 个的两屏左右滑动选择；视频/照片共用选择组件及预览与导出渲染路径；默认仍推荐隐私级像素化；不单独 IAP）
- [ ] 指定整个人物的实例分割与身份关联
- [ ] 指定任意物体的交互式视频分割：用户可在关键帧点击、框选、涂抹或圈出目标，模型在设备端生成遮罩并向前后帧传播
- [ ] 支持在不同帧追加提示以修正遮罩漂移；将修正保存为 `MaskTrack` 关键帧，不在 App 内为单个视频重新训练模型
- [ ] 评估图片样例/视觉提示用于指定物体匹配；优先验证端侧轻量模型（如 EdgeTAM 类 Core ML 方案），处理遮挡、相似物体和转场误匹配
- [ ] 推理缩放和更低频率 Vision 调用
- [ ] 4K/HDR 保留验证
- [ ] 后台处理与中断恢复
- [ ] 十几分钟 vlog 专项模式
- [ ] 车辆识别（当前代码无车辆；勿借照片功能顺带扩张）

## 2026-09-09 视频编辑工作区进展

- [x] 四工具单面板、固定下一步、当前帧对象对应与缩略时间轴。2026-09-10 全屏改为纯预览，手动区域编辑统一留在主工作区。
- [x] 手动区域不再暴露“固定 / 移动”模式；一个位置记录时自然固定，在其他时间拖动或缩放会自动增加记录并插值；时段修改不生成位置记录；会话撤销与旧数据兼容通过模型验证。
- [x] 按用户反馈移除重复主体入口、收紧间距和圆角；连续寻帧与预览检测刷新已接入。
- [ ] 完整导出、真机性能与四语无障碍矩阵，详见 [验证记录](./ios-video-refactor-validation-2026-09-09.md)。2026-09-09 已完成模拟器中的取消/完成竞争、失败重试、运行中重启与分段文件清理，并完成 iPhone SE 深色英文 Accessibility Large/XXXL 布局修复；真实 iPhone、其余三语、VoiceOver、存储不足及完整音频/方向交叉矩阵仍未完成。

### 下一对话执行顺序（2026-09-09）

- [ ] 继续收尾视频：取消/完成竞争与失败重试已完成模拟器验证；剩余连续寻帧真机性能、手动区域最终像素落点、完整音频/方向矩阵、四语与无障碍适配。
- [ ] 视频稳定性完成后，另做照片复核状态与免费导出表达；首页和 Paywall 再后置。

详细任务、验收与新对话启动说明统一维护在 [视频开发计划第 14–15 节](./ios-video-editor-development-plan-2026-09-08.md#14-下一轮开发先完成视频稳定性收尾2026-09-09)，避免新任务重复重构已完成的工具布局。

## 2026-09-10 视频手动区域与全屏预览

- [x] “添加蒙版”统一提供椭圆 / 矩形 / 手绘区域；画笔复用照片的归一化路径、手势组件和 Core Image 蒙版生成。
- [x] 压缩手动面板，移除重复标题和常驻帮助，时段与位置动画收进“出现时段与移动”；删除沿用确认与撤销。
- [x] 全屏移除手动编辑面板，以剩余高度显示完整视频和播放进度。
- [x] 根据首次操作反馈移除“固定 / 移动”模式开关，拖动或缩放始终在当前时间自动记录；蒙版删除确认改为居中警告框。
- [ ] 真机连续绘画、边缘笔触、旋转素材、大字体与四语交互验收；模拟器构建及回归见 [验证记录](./ios-video-brush-validation-2026-09-10.md)。
