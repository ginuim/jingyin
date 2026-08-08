import type { Locale } from './types'
import { LOCALES } from './types'

export const LOCALE_STORAGE_KEY = 'jingyin-landing-locale'

export function isLocale(value: string | null | undefined): value is Locale {
  return !!value && (LOCALES as readonly string[]).includes(value)
}

export function readStoredLocale(): Locale | null {
  if (typeof window === 'undefined') return null
  const stored = window.localStorage.getItem(LOCALE_STORAGE_KEY)
  return isLocale(stored) ? stored : null
}

export function saveLocale(locale: Locale) {
  window.localStorage.setItem(LOCALE_STORAGE_KEY, locale)
}

/** Map browser language tags to our four locales. */
export function detectBrowserLocale(): Locale {
  if (typeof navigator === 'undefined') return 'zh-Hans'
  const candidates = [...(navigator.languages ?? []), navigator.language]
  for (const raw of candidates) {
    const tag = raw.toLowerCase()
    if (tag.startsWith('zh-hant') || tag.startsWith('zh-tw') || tag.startsWith('zh-hk') || tag.startsWith('zh-mo')) {
      return 'zh-Hant'
    }
    if (tag.startsWith('zh')) return 'zh-Hans'
    if (tag.startsWith('ja')) return 'ja'
    if (tag.startsWith('en')) return 'en'
  }
  return 'zh-Hans'
}

export function resolveInitialLocale(): Locale {
  return readStoredLocale() ?? detectBrowserLocale()
}

export function localePrefix(locale: Locale): string {
  return locale === 'zh-Hans' ? '' : `/${locale}`
}

export function homePath(locale: Locale): string {
  return localePrefix(locale) || '/'
}

export function privacyPath(locale: Locale): string {
  const prefix = localePrefix(locale)
  return prefix ? `${prefix}/privacy` : '/privacy'
}

export function localeFromPath(path: string): Locale | null {
  if (path === '/' || path === '/privacy' || path.startsWith('/privacy/')) return 'zh-Hans'
  const seg = path.split('/').filter(Boolean)[0]
  return isLocale(seg) ? seg : null
}

export function htmlLang(locale: Locale): string {
  switch (locale) {
    case 'zh-Hans':
      return 'zh-Hans'
    case 'zh-Hant':
      return 'zh-Hant'
    case 'en':
      return 'en'
    case 'ja':
      return 'ja'
  }
}
