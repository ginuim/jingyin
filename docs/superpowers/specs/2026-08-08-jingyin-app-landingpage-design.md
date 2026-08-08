# 镜隐 App Landing Page 设计

日期：2026-08-08  
状态：已批准

## 目标

在仓库新建独立目录 `landingpage/`，交付纯 iOS App 营销落地页。不提供在线视频/照片处理。根目录现有 `app/` 网页工作室完全不动。

## 约束（对话确认）

- 技术：Vite + Vue 3 + vue-router
- App Store CTA：占位「即将上架」，URL 走配置常量
- 截图：使用现有 `artifacts/sim-*`
- 语言：简中 / 繁中 / 英 / 日；路径分流 + localStorage 记忆 + 浏览器语言检测
- 隐私政策：按语言分路径、分全文；范围仅 iOS App + 本营销站访问日志

## 路由

| 路径 | 语言 |
| --- | --- |
| `/` | zh-Hans |
| `/zh-Hant` | zh-Hant |
| `/en` | en |
| `/ja` | ja |
| `/{locale}/privacy` 与 `/privacy`（简中） | 对应语言隐私全文 |

## 页面区块

顶栏 → Hero（icon + 卖点 + CTA + 手机截图）→ 信任条 → 能力卡 → 三步流程 → 免费/永久版 → 页脚（reaidea.com + 隐私）

视觉对齐 `AppPalette.signalOrange`。

## 不做

改 `app/`、在线上传/YOLO、广告、硬编码货币价格、订阅文案。
