import type { PrivacyCopy } from '../types'

export const privacyEn: PrivacyCopy = {
  title: 'Privacy Policy',
  kicker: 'PRIVACY POLICY',
  lead: 'This policy applies to the lenshide iOS app and this marketing website. lenshide is built around on-device processing: original media, recognition data, and exports are not uploaded to lenshide servers.',
  updated: 'Effective and last updated: August 8, 2026.',
  summaryTitle: 'The key point: your photos and videos are not uploaded to lenshide.',
  summaryBody:
    'Importing, recognition, covering, audio processing, and export all happen on your device. lenshide does not offer cloud storage or require an account, and we do not review content stored on your device.',
  sections: [
    {
      heading: '1. How the iOS app handles data',
      bullets: [
        'The app reads a photo or video only after you actively select it from Photos or Files.',
        'Original media, detections, masks, and exports are processed locally and are not uploaded to our servers.',
        'Temporary input copies, intermediates, and export files may be created in the app sandbox. The app cleans temporary files it recognizes; deleting the app removes sandbox data.',
        'The launch version requires no account, contains no ads, and does not include a cross-app tracking analytics SDK.',
      ],
    },
    {
      heading: '2. Local content and your responsibilities',
      paragraphs: [
        'lenshide does not upload media for review. You may use cover, pixelation, pitch shift, and mute features on material you have the right to use.',
        'On-device processing does not make every publication lawful. You are responsible for rights, local law, privacy duties, and platform rules.',
        'lenshide does not provide a community, public gallery, cloud sharing, or publishing service. If cloud processing or sharing is added later, this policy will be updated first.',
      ],
    },
    {
      heading: '3. Photos, Files, and permissions',
      paragraphs: [
        'Photos and Files access is used only to import media you select and to save or share results you request. You can change permissions in iOS Settings.',
      ],
    },
    {
      heading: '4. In-app purchases',
      paragraphs: [
        'Lifetime Access purchases are processed by the Apple App Store. lenshide uses StoreKit for product and entitlement information to decide export limits. We do not receive your payment card details. Apple’s handling of related data is governed by Apple’s Privacy Policy.',
      ],
    },
    {
      heading: '5. This marketing website',
      paragraphs: [
        'This website introduces the lenshide iOS app. It does not offer online video or photo processing.',
        'Hosting and security services may automatically log IP address, browser type, time, and request path. Those logs help operate and protect the site and are unrelated to in-app media processing.',
        'The iOS app itself contains no advertising.',
      ],
    },
    {
      heading: '6. Sharing, children, and safety',
      paragraphs: [
        'We do not sell your videos or recognition data. Because we do not receive video content, we cannot view, restore, or delete media on your device for you.',
        'lenshide can process family videos that include children, but it is not designed to collect personal data from children. Guardians decide what is appropriate to import and share.',
      ],
    },
    {
      heading: '7. Updates and contact',
      paragraphs: [
        'If our data practices change materially, we will update this page and the effective date. Privacy questions can be sent through the contact options at reaidea.com.',
      ],
    },
  ],
  backHome: 'Back to home',
}
