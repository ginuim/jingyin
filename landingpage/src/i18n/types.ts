export const LOCALES = ['zh-Hans', 'zh-Hant', 'en', 'ja'] as const
export type Locale = (typeof LOCALES)[number]

export type PrivacyCopy = {
  title: string
  kicker: string
  lead: string
  updated: string
  summaryTitle: string
  summaryBody: string
  sections: { heading: string; paragraphs?: string[]; bullets?: string[] }[]
  backHome: string
}

export type LandingCopy = {
  metaTitle: string
  metaDescription: string
  brand: string
  navDownload: string
  navPrivacy: string
  comingSoon: string
  heroEyebrow: string
  heroTitle: string
  heroHighlight: string
  heroBody: string
  heroCta: string
  heroSecondary: string
  trust: string[]
  featuresTitle: string
  featuresLead: string
  features: { title: string; body: string }[]
  stepsTitle: string
  stepsLead: string
  steps: { title: string; body: string }[]
  pricingTitle: string
  pricingLead: string
  freeTitle: string
  freeBody: string
  freePoints: string[]
  proTitle: string
  proBody: string
  proBadge: string
  proPoints: string[]
  footerTagline: string
  footerPrivacy: string
  footerHome: string
  langLabel: string
  langNames: Record<Locale, string>
}

export type Dictionary = {
  landing: LandingCopy
  privacy: PrivacyCopy
}
