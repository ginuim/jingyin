# 镜隐 App Store Connect 配置记录

更新时间：2026-07-30

配套文档：市场与定价见 [app-store-market-and-pricing.md](./app-store-market-and-pricing.md)；首发清单见 [ios-launch-todo.md](./ios-launch-todo.md)。

## 结论

付费闭环在 Connect 侧的前置条件已齐：Paid Apps Agreement **有效**、银行 **可用**、美国税表 **使用中**、Family Sharing **已开**、IAP 与 App 定价已配好。DSA 交易商信息已提交，状态为 **正在审核**。下一步是手动创建 Sandbox 账号并做真机 / TestFlight 购买验证。

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
| 状态 | 准备提交（须随 App 版本一并提交审核） |
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
| 英语（美国） | Lifetime Access | One-time unlock for full video and batch photo privacy exports |
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
| 欧盟 DSA | 交易商已声明并提交联系信息 · **正在审核**（27 个国家或地区） |

说明：

- 银行联络信息（户名、地址）按 Apple 要求用英文/拼音，不用汉字。
- 招商银行北京建国门支行公开联行号参考：`308100005490`（以开户行确认为准）。
- DSA 审核中一般不挡中美上架；欧盟分发需等核验通过。

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
