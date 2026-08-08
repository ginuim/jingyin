# 镜隐 App Landing Page

独立于根目录 `app/` 的 iOS App 营销站。不提供在线视频处理。

## 开发

```bash
cd landingpage
pnpm install
pnpm dev
```

默认本地：`http://localhost:5174`

## 构建

```bash
pnpm build
pnpm preview
```

## 语言

简中 `/` · 繁中 `/zh-Hant` · 英文 `/en` · 日文 `/ja`  
隐私：`/privacy`、`/zh-Hant/privacy`、`/en/privacy`、`/ja/privacy`

首访按 localStorage → 浏览器语言跳转；语言切换会写入 localStorage。

## App Store 链接

编辑 `src/config.ts` 中的 `APP_STORE_URL`。空字符串时 CTA 显示「即将上架」。
