import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
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
    document.title = isPrivacy
      ? `${dict.privacy.title}｜${dict.landing.brand}`
      : dict.landing.metaTitle

    let desc = document.querySelector('meta[name="description"]')
    if (!desc) {
      desc = document.createElement('meta')
      desc.setAttribute('name', 'description')
      document.head.appendChild(desc)
    }
    desc.setAttribute('content', dict.landing.metaDescription)
  }
  return true
})
