import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { SITE_URL } from '../config'
import {
  LOCALES,
  getDictionary,
  htmlLang,
  homePath,
  isLocale,
  localeFromPath,
  privacyPath,
  resolveInitialLocale,
  saveLocale,
  type Locale,
} from '../i18n'
import HomePage from '../pages/HomePage.vue'
import PrivacyPage from '../pages/PrivacyPage.vue'

function setMeta(selector: string, attribute: 'name' | 'property', key: string, content: string) {
  let meta = document.querySelector<HTMLMetaElement>(selector)
  if (!meta) {
    meta = document.createElement('meta')
    meta.setAttribute(attribute, key)
    document.head.appendChild(meta)
  }
  meta.content = content
}

function setLink(selector: string, rel: string, href: string, hreflang?: string) {
  let link = document.querySelector<HTMLLinkElement>(selector)
  if (!link) {
    link = document.createElement('link')
    link.rel = rel
    if (hreflang) link.hreflang = hreflang
    document.head.appendChild(link)
  }
  link.href = href
}

function localeRoutes(): RouteRecordRaw[] {
  const routes: RouteRecordRaw[] = [
    { path: '/', name: 'home-zh-Hans', component: HomePage, meta: { locale: 'zh-Hans' as Locale } },
    { path: '/privacy', name: 'privacy-zh-Hans', component: PrivacyPage, meta: { locale: 'zh-Hans' as Locale } },
  ]

  for (const locale of LOCALES) {
    if (locale === 'zh-Hans') continue
    routes.push(
      {
        path: `/${locale}`,
        name: `home-${locale}`,
        component: HomePage,
        meta: { locale },
      },
      {
        path: `/${locale}/privacy`,
        name: `privacy-${locale}`,
        component: PrivacyPage,
        meta: { locale },
      },
    )
  }

  routes.push({
    path: '/:pathMatch(.*)*',
    redirect: () => homePath(resolveInitialLocale()),
  })

  return routes
}

export const router = createRouter({
  history: createWebHistory(),
  routes: localeRoutes(),
  scrollBehavior() {
    return { top: 0 }
  },
})

let didBootstrapLocale = false

router.beforeEach((to) => {
  if (!didBootstrapLocale) {
    didBootstrapLocale = true
    const preferred = resolveInitialLocale()
    if (to.path === '/' && preferred !== 'zh-Hans') {
      return homePath(preferred)
    }
    if (to.path === '/privacy' && preferred !== 'zh-Hans') {
      return privacyPath(preferred)
    }
  }

  const locale =
    (to.meta.locale as Locale | undefined) ?? localeFromPath(to.path) ?? 'zh-Hans'
  if (isLocale(locale)) {
    saveLocale(locale)
    document.documentElement.lang = htmlLang(locale)
    const dict = getDictionary(locale)
    const isPrivacy = String(to.name ?? '').startsWith('privacy')
    const title = isPrivacy
      ? `${dict.privacy.title}｜${dict.landing.brand}`
      : dict.landing.metaTitle
    const description = isPrivacy
      ? dict.privacy.metaDescription
      : dict.landing.metaDescription
    const canonicalURL = new URL(to.path, SITE_URL).href

    document.title = title
    setMeta('meta[name="description"]', 'name', 'description', description)
    setMeta('meta[property="og:title"]', 'property', 'og:title', title)
    setMeta('meta[property="og:description"]', 'property', 'og:description', description)
    setMeta('meta[property="og:url"]', 'property', 'og:url', canonicalURL)
    setLink('link[rel="canonical"]', 'canonical', canonicalURL)

    for (const alternateLocale of LOCALES) {
      const path = isPrivacy
        ? privacyPath(alternateLocale)
        : homePath(alternateLocale)
      setLink(
        `link[rel="alternate"][hreflang="${htmlLang(alternateLocale)}"]`,
        'alternate',
        new URL(path, SITE_URL).href,
        htmlLang(alternateLocale),
      )
    }
    setLink(
      'link[rel="alternate"][hreflang="x-default"]',
      'alternate',
      new URL(isPrivacy ? privacyPath('zh-Hans') : homePath('zh-Hans'), SITE_URL).href,
      'x-default',
    )
  }
  return true
})
