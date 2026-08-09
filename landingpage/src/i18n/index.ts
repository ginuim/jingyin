import { landingEn } from './locales/en'
import { landingJa } from './locales/ja'
import { landingZhHans } from './locales/zh-Hans'
import { landingZhHant } from './locales/zh-Hant'
import { privacyEn } from './privacy/en'
import { privacyJa } from './privacy/ja'
import { privacyZhHans } from './privacy/zh-Hans'
import { privacyZhHant } from './privacy/zh-Hant'
import type { Dictionary, Locale } from './types'

const dictionaries: Record<Locale, Dictionary> = {
  'zh-Hans': { landing: landingZhHans, privacy: privacyZhHans },
  'zh-Hant': { landing: landingZhHant, privacy: privacyZhHant },
  en: { landing: landingEn, privacy: privacyEn },
  ja: { landing: landingJa, privacy: privacyJa },
}

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale]
}

export type { Locale, Dictionary, LandingCopy, PrivacyCopy } from './types'
export { LOCALES } from './types'
export * from './detect'
