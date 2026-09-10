# 镜隐 App Store Connect 配置记录

更新时间：2026-09-10

配套文档：市场与定价见 [app-store-market-and-pricing.md](./app-store-market-and-pricing.md)；首发清单见 [ios-launch-todo.md](./ios-launch-todo.md)。

## 结论

付费闭环在 Connect 侧的前置条件已齐：Paid Apps Agreement **有效**、银行 **可用**、美国税表 **使用中**、Family Sharing **已开**、IAP 与 App 定价已配好，DSA 交易商信息 **有效**。2026-09-02，iOS `1.0 (3)` 因 Guideline 2.1 要求补充人脸数据处理说明而被拒；不是功能或 IAP 故障。2026-09-03 已发布四语隐私政策的独立「人脸数据」章节并完成上一轮回复。2026-09-07 已撤回原提审的 `1.0.1 (5)`，上传当前工程归档 `1.0.1 (6)` 并重新提交；该版已通过审核，状态为**可分发**（尚未手动发布）。2026-09-10 已创建 `1.0.2`、回填四语商店文案并调整截屏顺序，上传构建 `1.0.2 (7)` 后提交审核；当前 **1.0.2 正在等待审核**。真机 Sandbox 购买与 TestFlight 商店价格验证仍待完成。

## 账号与标识

| 项 | 值 |
| --- | --- |
| Team / Account Holder | tao sun（猫 大） |
| Team ID | `48TLUK3DQ8` |
| Bundle ID | `com.reaidea.jingyin`（Developer → Identifiers 已注册，Description: Jingyin） |
| App 名称 | 镜隐 |
| App Apple ID | `6795803353` |
| SKU | `jingyin` |
| 主语言 | 简体中文 |
| 平台 | iOS |

入口：

- App：https://appstoreconnect.apple.com/apps/6795803353/distribution
- IAP：https://appstoreconnect.apple.com/apps/6795803353/distribution/iaps/6795803473
- 商务：https://appstoreconnect.apple.com/business

## App 定价与供应

| 项 | 值 |
| --- | --- |
| App 价格 | **Free**（`$0.00`） |
| 覆盖 | 175 个国家或地区 |
| 预售 | 未设置 |
| 付费方式 | 仅通过 Non-Consumable IAP，不设付费下载 |

## IAP：永久版

| 字段 | 值 |
| --- | --- |
| 类型 | Non-Consumable（非消耗型） |
| Reference Name | 镜隐永久版 |
| Product ID | `com.reaidea.jingyin.lifetime`（与工程 `EntitlementStore.lifetimeProductID` 一致） |
| IAP Apple ID | `6795803473` |
| 状态 | 等待审核（2026-09-03 随原构建重新提交） |
| Family Sharing | **已开启**（不可关闭） |
| 审核截图 | `artifacts/asc/iap-review-640x920.png`（640×920） |
| 审核备注 | 无登录；本地处理；免费前 30 秒；永久解锁路径；Restore；非订阅 |

### 价格

| 市场 | 当前价 | 备注 |
| --- | --- | --- |
| 美国（基准） | `$4.99` | 上架售价；功能稳定后再评估永久改到 `$9.99`，不排自动涨回 |
| 中国大陆 | `¥28` | 手动覆盖；与美国脱钩；先观察付费意愿，不预设涨价 |
| 其他地区 | Apple 自动换算 | 约 174 个国家或地区可自动调整；涨美国价时勿连带自动改大陆 |

定价细则与涨价条件见 [app-store-market-and-pricing.md](./app-store-market-and-pricing.md)。

### 本地化

| 语言 | 显示名称 | 描述 |
| --- | --- | --- |
| 简体中文 | 永久版 | 一次购买，永久解锁完整视频与照片批量处理 |
| 繁体中文 | 永久版 | 一次購買，永久解鎖完整影片與照片批次處理 |
| 英语（美国） | Lifetime Access | Unlock full video and batch photo exports |
| 日语 | 永久版 | 一度の購入で動画と写真一括のプライバシー処理を解放 |

ASC 上若仍是「仅视频」旧描述，照片批量上线前提交版本前改成上表文案。

## 协议、银行、税务、合规

| 项 | 状态（2026-07-29 晚核对） |
| --- | --- |
| 免费 App 协议 | 有效 |
| 付费 App 协议 | **有效** |
| 银行账户 | China Merchants Bank · 中国大陆 · CNY · 版税 USD · **可用** |
| U.S. Form W-8BEN | **使用中**（个人；中国大陆居民；条约 Article 12 / 10%；Income from the sale of applications） |
| U.S. Certificate of Foreign Status | **使用中**（Individual/Sole proprietor；Title: Owner） |
| 国务院令第 810 号 | **有效** |
| 欧盟 DSA | 交易商已声明并完成核验 · **有效**（27 个国家或地区） |

说明：

- 银行联络信息（户名、地址）按 Apple 要求用英文/拼音，不用汉字。
- 招商银行北京建国门支行公开联行号参考：`308100005490`（以开户行确认为准）。
- DSA 已于 2026-08-04 在 App Store Connect 核对为有效。

## TestFlight 内部测试

| 项 | 状态 |
| --- | --- |
| 历史内测构建 | `0.1.0 (1)`（Internal Testing Only） |
| 当前送审构建 | `1.0.2 (7)`（2026-09-10 上传并处理完成；状态：正在等待审核）。`1.0.1 (6)` 已通过审核，仍为可分发、未手动发布 |
| 分发范围 | **Internal Testing Only**（不能转为外部测试或正式 App Store 构建） |
| 出口合规 | 不使用专有、标准或其他非豁免加密；App Store Connect 已接受声明 |
| 内部群组 | 「内部测试」；自动访问全部构建 |
| 测试员 | 已加入 1 位现有 App Store Connect 内部用户 |

## Sandbox / 真机验证（待办）

自动化在 ASC「添加测试账户」时多次遇到 `An unknown error has occurred`，需手动创建。

### 手动创建 Sandbox

1. https://appstoreconnect.apple.com/access/users/sandbox  
2. 添加测试账户  
3. 邮箱：建议 `你的Gmail+别名@gmail.com`（不能已是正式 Apple ID）  
4. 国家或地区：先建 **中国大陆**（测 ¥28）；若要测 `$4.99` 再建美国店面账号  
5. 密码需足够复杂（大小写 + 数字 + 符号）

### 真机测试顺序

1. 设置 → App Store：退出正式账户（或仅在购买弹窗使用 Sandbox）  
2. 按 `RUNNING.md` 安装 Debug 包到真机（**不要**带 `-storekitUnlocked`）  
3. 验证：商品加载与价格 → 购买成功 → 取消购买 → 恢复购买 → 删 App 重装后再恢复  
4. Family Sharing（可选）：购买者开启购买共享后，家庭成员另一台设备恢复购买，确认 `Transaction.currentEntitlements` 仍有权益  
5. TestFlight：再验真实商店价格展示与产品 ID  

工程侧已有 `Transaction.currentEntitlements` + `revocationDate == nil` + `Transaction.updates`；退款与家庭组变动由 StoreKit 推送，无需自建家庭组状态机。

## 版本提交时注意

- 首个 Non-Consumable 必须随新 App 版本提交。  
- 版本页勾选该 IAP（`In-App Purchases and Subscriptions`）后再送审。  
- App 保持 Free；付费只走 `com.reaidea.jingyin.lifetime`。  
- 审核备注避免写「订阅」「自动续费」「云端处理」。

## 2026-09-02 Guideline 2.1：人脸数据说明

审核环境：iPad Air 11-inch (M3)；版本 `1.0 (3)`；Submission ID
`511e7fb8-e1ca-4571-a9a9-e083f0a04b71`。

Apple 要求说明人脸数据的类型、用途、共享、存储、保留、删除，以及隐私政策中的具体章节和原文。
代码核对结论：人脸检测使用设备端 Apple Vision，只临时生成检测框、归一化坐标、蒙版或关键帧；
不生成身份识别特征，不上传服务器，不提供给第三方，检测结果也不写入持久化偏好。

四语隐私政策已新增并发布第 2 节「人脸数据 / Face data」。英文线上地址为：
`https://lenshide.reaidea.com/en/privacy`。

### 给 App Review 的英文回复

Hello App Review Team,

Thank you for your message. Below are the requested details about face data in lenshide.

1. **What face data does the app access or process?**

lenshide does not collect face data on our servers. When a user selects a photo for photo processing,
face masking is enabled by default. For video processing, face detection runs when the user selects
Faces as the subject to cover. The app processes the selected media locally using Apple Vision APIs
and may temporarily derive face bounding rectangles, normalized coordinates, and masks or keyframes
needed to position pixelation, blur, or stickers.

The app does not create facial embeddings, biometric templates, faceprints, identity labels, or
persistent facial landmark profiles. It does not recognize or identify people.

2. **How is the face data used?**

It is used solely to apply the visual privacy effect requested by the user to the selected photo or
video. It is not used for authentication, identification, advertising, marketing, analytics, user
profiling, or any unrelated purpose.

3. **Is face data shared with third parties, and where is it stored?**

No. Face detection and processing take place entirely on the user's device. Face data is not uploaded
to lenshide servers, transferred off the device, sold, shared with third parties, or made available to
the developer.

Derived face coordinates, masks, and keyframes exist only in volatile memory during the current editing
and export session. They are not stored in a persistent database or in user preferences. Temporary copies
of user-selected media and processing files may be stored in the app's local sandbox only while needed
for editing, preview, export, or displaying the result.

4. **How long is face data retained, and how is it deleted?**

Derived face coordinates, masks, and keyframes are retained only for the current editing and export
session. They are discarded when the session ends or the app terminates.

Temporary media and processing files are removed when the user leaves the project, cancels processing,
processing fails, leaves the result screen, or during cleanup on a later launch. Deleting the app removes
any remaining sandbox data. Media that the user explicitly saves to Photos or Files remains under the
user's control. Because no face data is received or stored by lenshide servers, there is no server-side
face data for the developer to retrieve or delete.

5. **Privacy Policy disclosure**

The disclosure is located in Section 2, “Face data,” of our Privacy Policy:

https://lenshide.reaidea.com/en/privacy

The relevant text states:

“When you select a photo for photo processing, face masking is enabled by default. For video processing,
face detection runs when you select Faces as the subject to cover. The app uses Apple Vision APIs on the
device to detect face locations and may temporarily derive face bounding rectangles, normalized
coordinates, and masks or keyframes needed to place pixelation, blur, or stickers.”

“All face detection and processing take place on your device. Face data is not uploaded to lenshide
servers, transferred off the device, shared with third parties, sold, or made available to the developer.”

“Derived face coordinates, masks, and keyframes are kept only in volatile memory for the current editing
and export session. They are discarded when that session ends or the app terminates, and are not stored
in a persistent database or in user preferences.”

Please let us know if any additional information is required.

Best regards


## 2026-09-08 视频工作区审核说明补充（草稿，未提交）

Video timeline navigation derives at most eight reduced full-frame thumbnails from the selected original video. The editor also retains at most forty region-edit undo states in session memory. They may contain visible faces or region coordinates. They are not uploaded, shared, or persisted to disk or preferences, and are released when the editor closes or the app terminates. They are used solely for local editing and do not identify people. Timeline thumbnails are source frames, not evidence of completed masking.

四语政策源码同次补充；上线部署与 App Store Connect 审核备注尚需同步，不能以本地文档更新视为已提交。
