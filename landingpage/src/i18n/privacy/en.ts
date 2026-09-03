import type { PrivacyCopy } from '../types'

export const privacyEn: PrivacyCopy = {
  title: 'Privacy Policy',
  metaDescription: 'lenshide Privacy Policy: videos, photos, recognition data, and exports are processed on your device and are not uploaded to lenshide servers.',
  kicker: 'PRIVACY POLICY',
  lead: 'This policy applies to the lenshide iOS app and this marketing website. lenshide is built around on-device processing: original media, recognition data, and exports are not uploaded to lenshide servers.',
  updated: 'Effective and last updated: September 3, 2026.',
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
      heading: '2. Face data',
      paragraphs: [
        'When you select a photo for photo processing, face masking is enabled by default. For video processing, face detection runs when you select Faces as the subject to cover. The app uses Apple Vision APIs on the device to detect face locations and may temporarily derive face bounding rectangles, normalized coordinates, and masks or keyframes needed to place pixelation, blur, or stickers.',
        'lenshide does not create or collect facial embeddings, biometric templates, faceprints, identity labels, or persistent facial landmark profiles. It does not recognize or identify people. Face data is used only to apply the visual privacy effect you request. It is not used for authentication, advertising, marketing, analytics, profiling, or any unrelated purpose.',
        'All face detection and processing take place on your device. Face data is not uploaded to lenshide servers, transferred off the device, shared with third parties, sold, or made available to the developer.',
        'Derived face coordinates, masks, and keyframes are kept only in volatile memory for the current editing and export session. They are discarded when that session ends or the app terminates, and are not stored in a persistent database or in user preferences.',
        'Temporary copies of selected media and processing files may remain in the app sandbox only while needed for editing, preview, export, or displaying the result. The app removes its temporary files when you leave the project, cancel processing, processing fails, leave the result screen, or during cleanup on a later launch. Deleting the app removes all remaining sandbox data. Copies you explicitly save to Photos or Files remain under your control.',
      ],
    },
    {
      heading: '3. Local content and your responsibilities',
      paragraphs: [
        'lenshide does not upload media for review. You may use cover, pixelation, pitch shift, and mute features on material you have the right to use.',
        'On-device processing does not make every publication lawful. You are responsible for rights, local law, privacy duties, and platform rules.',
        'lenshide does not provide a community, public gallery, cloud sharing, or publishing service. If cloud processing or sharing is added later, this policy will be updated first.',
      ],
    },
    {
      heading: '4. Photos, Files, and permissions',
      paragraphs: [
        'Photos and Files access is used only to import media you select and to save or share results you request. You can change permissions in iOS Settings.',
      ],
    },
    {
      heading: '5. In-app purchases',
      paragraphs: [
        'Lifetime Access purchases are processed by the Apple App Store. lenshide uses StoreKit for product and entitlement information to decide export limits. We do not receive your payment card details. Apple’s handling of related data is governed by Apple’s Privacy Policy.',
      ],
    },
    {
      heading: '6. This marketing website',
      paragraphs: [
        'This website introduces the lenshide iOS app. It does not offer online video or photo processing.',
        'Hosting and security services may automatically log IP address, browser type, time, and request path. Those logs help operate and protect the site and are unrelated to in-app media processing.',
        'The iOS app itself contains no advertising.',
      ],
    },
    {
      heading: '7. Sharing, children, and safety',
      paragraphs: [
        'We do not sell your videos or recognition data. Because we do not receive video content, we cannot view, restore, or delete media on your device for you.',
        'lenshide can process family videos that include children, but it is not designed to collect personal data from children. Guardians decide what is appropriate to import and share.',
      ],
    },
    {
      heading: '8. Updates and contact',
      paragraphs: [
        'If our data practices change materially, we will update this page and the effective date. Privacy questions can be sent through the contact options at reaidea.com.',
      ],
    },
  ],
  backHome: 'Back to home',
}
