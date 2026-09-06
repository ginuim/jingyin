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

## 发布

目标生产域名：`https://lenshide.reaidea.com`。

原先发根目录 `app/`（vinext 网页工作室）到 **Vercel**。现改为发布本目录营销站；`app/` 源码保留，不再作为该域名内容。

### 已就绪：Cloudflare Pages

项目：`lenshide`  
生产预览：https://lenshide.pages.dev  

```bash
cd landingpage && pnpm build
cd .. && pnpm exec wrangler pages deploy landingpage/dist --project-name=lenshide --branch=main
```

自定义域名 `lenshide.reaidea.com` 已在 Pages 侧添加，但 DNS 目前仍指向 Vercel。要切正式流量，把该主机记录改为 CNAME → `lenshide.pages.dev`（或按 CF 控制台提示），并在 Vercel 解绑同名域名以免冲突。

### 备选：继续走 Vercel

仓库根 `vercel.json` 已改为只构建本目录静态产物（`landingpage/dist` + SPA 回退）。本地无 Vercel 登录态时，推送到已连接的生产分支或 Dashboard Redeploy 即可。

```bash
npx vercel login
npx vercel --prod
```

## 语言

简中 `/` · 繁中 `/zh-Hant` · 英文 `/en` · 日文 `/ja`  
隐私：`/privacy`、`/zh-Hant/privacy`、`/en/privacy`、`/ja/privacy`

首访按 localStorage → 浏览器语言跳转；语言切换会写入 localStorage。

## App Store 链接

当前已连接到正式 App Store 页面：
`https://apps.apple.com/app/lenshide/id6795803353`

如 App Store 链接发生变化，只需更新 `src/config.ts` 中的 `APP_STORE_URL`。
