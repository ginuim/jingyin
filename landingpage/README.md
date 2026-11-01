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

## 统计

Google Analytics 4，数据流 `lenshide`（`https://lenshide.reaidea.com`，测量 ID `G-CXFVF8WSKD`），
属于 vantvox 账号下的 reaidea 媒体资源。实现见 `src/analytics.ts`：

- 只在生产构建里加载 gtag，`pnpm dev` 和 Vercel preview 部署不发送任何数据。
- `send_page_view` 关闭，首屏和语言/隐私页切换统一由 `router.afterEach` 上报一次 `page_view`，
  路径会带上语言前缀（`/en`、`/ja`、`/zh-Hant`），所以语言版本可以分开看。

## Hero 布局

首屏机器大图按 hero 自身高度（`height: 152%`）缩放、按图片自身宽度（`translateX(34%)`）横移，
hero 高度夹在 640–1200px，所以 1280×800、1440×900、1536×864、1680×1050、1920×1080、2560×1440
的构图一致：手机始终从左侧溢出、被首屏底部裁切，不会在大屏上下沉或缩到屏幕中间。

## App Store 链接

当前已连接到正式 App Store 页面：
`https://apps.apple.com/app/lenshide/id6795803353`

如 App Store 链接发生变化，只需更新 `src/config.ts` 中的 `APP_STORE_URL`。
