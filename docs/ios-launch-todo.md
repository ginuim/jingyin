# 镜隐 iOS 首发 TODO

更新时间：2026-07-30

## P0：付费闭环

- [x] StoreKit 2 权益状态、交易监听和本地校验
- [x] Non-Consumable 永久解锁购买流程
- [x] 恢复购买
- [x] 免费版导出前 30 秒、最高 720p
- [x] 买断版完整时长与完整导出规格
- [x] 编辑页展示免费版边界和永久解锁入口
- [x] 设置页展示购买状态、购买和恢复购买
- [x] Developer 注册 Bundle ID `com.reaidea.jingyin`
- [x] App Store Connect 创建 App `镜隐`（Apple ID `6795803353`，SKU `jingyin`，主语言简中）
- [x] App Store Connect 创建 `com.reaidea.jingyin.lifetime`（IAP Apple ID `6795803473`，非消耗型，参考名「镜隐永久版」）
- [x] 配置中国大陆 ¥28（手动覆盖）、美国 $4.99 及其他地区自动换算价
- [x] IAP 本地化：简中 / 繁中 / 英文 / 日文
- [x] 补充 IAP 审核截图和审核说明（截图：`artifacts/asc/iap-review-640x920.png`）
- [x] App 定价设为 Free（$0.00，175 个国家或地区）
- [x] 签署 Paid Apps Agreement
- [x] 提交银行账户（招商银行，CNY；状态：正在处理）
- [x] 提交美国税表 W-8BEN + Certificate of Foreign Status（状态：使用中；条约 Article 12 / 10%）
- [x] 国务院令第 810 号合规（状态：有效）
- [x] 等待银行与付费 App 协议审核通过（付费协议：**有效**；DSA：**正在审核**）
- [x] 开启 Family Sharing（已在 App Store Connect 确认开启；开启后不能关闭）
- [x] 完成欧盟 DSA 交易商声明与联系信息（已提交，ASC 显示正在审核）
- [ ] 创建 Sandbox 测试账号（ASC → 用户和访问 → 沙盒；自动化创建遇 Apple unknown error，需手动建）
- [ ] 真机用 Sandbox 验证：加载商品、购买、取消、恢复、删装再恢复
- [ ] TestFlight 验证真实商店价格与产品 ID

### App Store Connect

完整配置与核对记录见 **[app-store-connect.md](./app-store-connect.md)**。

摘要（2026-07-29）：付费协议有效 · 银行可用 · 税表使用中 · Family Sharing 已开 · DSA 正在审核 · IAP `com.reaidea.jingyin.lifetime` 准备提交（¥28 / $4.99）。

## P0：可控遮盖

- [x] 建立 `MaskTrack`、归一化坐标和关键帧数据结构
- [x] 当前画面检测多张人脸并逐个勾选（显示方向帧上使用 Vision 本地检测；选择页支持按编号点击或逐项开关，所选人脸分别生成独立 `MaskTrack`）
- [x] 椭圆和矩形手动蒙版
- [x] 拖动、缩放和删除蒙版
- [x] 单个蒙版覆盖范围扩大/缩小（当前时间写入关键帧，按中心 10% 调整并保持在归一化画面边界内；预览与导出复用同一 `NormalizedVideoRect`）
- [x] 连续镜头人脸跟踪（从当前时间向后使用 `VNTrackObjectRequest`，按视频长度自适应约 0.25–0.5 秒采样并写入自动关键帧；导出前等待轨迹完成）
- [x] 跟踪丢失提示与手动修正关键帧（低置信度或镜头切换时记录丢失时间并保留最后覆盖；用户可在丢失后拖动/缩放写入修正关键帧，再从当前画面继续跟踪）
- [x] 确保预览与最终导出坐标一致（人脸检测、Vision、SwiftUI 预览和 Core Image 导出统一使用显示方向归一化坐标；2026-07-30 完成横屏、90° 竖屏与 180° `preferredTransform` 几何矩阵，并用 90° 非对称蒙版对照预览/最终导出落点）

## P0：隐私与稳定性

- [x] 默认推荐像素化和高强度遮盖（默认隐私级像素化，像素块 24 px）
- [x] 区分“视觉模糊”和“隐私级像素化”（简中 / 繁中 / 英文 / 日文）
- [x] 导出时清除位置、设备和拍摄时间等元数据（所有视频导出、分段合并和变音复用路径均显式清空 metadata；2026-07-30 合成标签视频验证位置与源拍摄时间不再保留）
- [x] 离开项目、取消、失败和完成后清理输入副本与临时文件（结果页内保留成品供保存/分享，离开时删除；启动时兜底清理 `jingyin-` 前缀遗留文件）
- [x] 统一 README、界面和实际视频时长限制（导入层与 `VideoProcessor` 双重强制最长 5 分钟、最大 1 GB）
- [x] 免费/买断导出均覆盖原声、静音和变音（2026-07-30 iOS 18.1 模拟器 35 秒竖屏素材六路径通过：免费版均为 30 秒 / 720p，永久版均保留 35 秒；静音约 -91 dB，-4 半音将 440 Hz 测试音降至约 350–357 Hz；真实 iPhone 仍在下方真机矩阵验收）

## P0：真机验收

- [ ] 30 秒、1 分钟、3 分钟视频端到端验证
- [ ] 横屏、竖屏、多人、遮挡、转头和人物进出画面
- [ ] 至少两台不同性能档位的真实 iPhone
- [ ] 购买成功、取消、待批准、恢复、退款和 Family Sharing
- [ ] 导出取消、失败重试、存储不足和临时文件清理

## P1：商店发布

- [ ] 隐私政策与 App Privacy 填写（公开页面已实现：`https://lenshide.reaidea.com/privacy`；待部署确认并填写 App Store Connect）
- [ ] 简中、繁中、英文、日文商店文案（[四语草稿已完成](./app-store-listing.md)，待填写 App Store Connect）
- [ ] 免费版与永久版截图
- [ ] TestFlight 内测
- [ ] App Review Notes 说明完全本地处理和 IAP 测试路径（[英文草稿已完成](./app-store-listing.md#app-review-notes英文可直接粘贴)，待随构建填写）

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
| Description（简中） | `一次购买，永久解锁完整视频隐私处理` |
| Display Name（英文） | `Lifetime Access` |
| Description（英文） | `One-time purchase for full video privacy exports` |
| Display Name（日文） | `永久版` |
| Display Name（繁中） | `永久版` |

Product ID 保存后不可编辑，也不能在同一个 App 中复用已删除的 ID，因此必须先核对
拼写和大小写。工程当前 StoreKit 代码已经固定使用这个 ID。

参考：[IAP 字段说明](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)。

### 3. 设置价格和销售地区

进入该 IAP 的 `Price Schedule → Add Pricing`：

- 中国大陆目标价：`¥28`
- 美国目标价：`$4.99`
- 其他国家/地区先使用 Apple 自动生成的可比价格
- Availability 至少包含 China mainland、United States，以及实际计划上架的地区
- Start Date 设为立即可用；End Date 选择 No End Date
- 不要设置订阅、试用期、Offer Code 或 Promotional Offer

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
  - 免费用户可预览并导出前 30 秒
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

- [ ] 指定整个人物的实例分割与身份关联
- [ ] 指定任意物体的交互式视频分割：用户可在关键帧点击、框选、涂抹或圈出目标，模型在设备端生成遮罩并向前后帧传播
- [ ] 支持在不同帧追加提示以修正遮罩漂移；将修正保存为 `MaskTrack` 关键帧，不在 App 内为单个视频重新训练模型
- [ ] 评估图片样例/视觉提示用于指定物体匹配；优先验证端侧轻量模型（如 EdgeTAM 类 Core ML 方案），处理遮挡、相似物体和转场误匹配
- [ ] 推理缩放和更低频率 Vision 调用
- [ ] 4K/HDR 保留验证
- [ ] 后台处理与中断恢复
- [ ] 十几分钟 vlog 专项模式
