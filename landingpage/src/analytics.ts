/** GA4 测量 ID：vantvox 账号下 reaidea 媒体资源的 `lenshide` 网站数据流。 */
const GA_MEASUREMENT_ID = 'G-CXFVF8WSKD'

declare global {
  interface Window {
    dataLayer?: unknown[]
    gtag?: (...args: unknown[]) => void
  }
}

let enabled = false

/** 本地预览和 Vercel preview 部署不计数，避免脏数据。 */
const isLocalOrPreview =
  /^(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])$/.test(location.hostname) ||
  location.hostname.endsWith('.vercel.app')

/**
 * 只在生产构建里挂 gtag：`pnpm dev` 的本地预览不发任何统计请求。
 * `send_page_view` 关掉，首屏和路由切换统一由 router 的 afterEach 上报，避免重复计数。
 */
export function initAnalytics() {
  if (enabled || !import.meta.env.PROD || isLocalOrPreview) return
  enabled = true

  window.dataLayer = window.dataLayer || []
  window.gtag = function gtag() {
    window.dataLayer!.push(arguments)
  }
  window.gtag('js', new Date())
  window.gtag('config', GA_MEASUREMENT_ID, { send_page_view: false })

  const script = document.createElement('script')
  script.async = true
  script.src = `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`
  document.head.appendChild(script)
}

/** 每次路由切换上报一次 page_view，语言版本记在 page_path 里（/en、/ja、/zh-Hant）。 */
export function trackPageView(path: string) {
  window.gtag?.('event', 'page_view', {
    page_path: path,
    page_location: window.location.href,
    page_title: document.title,
  })
}
