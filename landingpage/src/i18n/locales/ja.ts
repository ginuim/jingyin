import type { LandingCopy } from '../types'

export const landingJa: LandingCopy = {
  metaTitle: 'lenshide｜端末内で動画と写真を保護',
  metaDescription:
    '端末内で動作する動画・写真プライバシー保護：モザイク、ぼかし、手動マスク、写真一括、消音や声の高さ変更。元データはアップロードしません。',
  brand: 'lenshide',
  navDownload: 'App Store',
  navPrivacy: 'プライバシー',
  comingSoon: '近日公開',
  heroEyebrow: 'iOS · 端末内処理',
  heroTitle: '共有する前に、隠すべき部分を隠す',
  heroHighlight: '元データは端末から出ません',
  heroBody:
    'lenshide は端末内で動画と写真を処理します。モザイク、ぼかし、手動マスク、消音、声の高さ変更。アカウントも広告もサブスクリプションもありません。',
  heroCta: 'App Store 近日公開',
  heroSecondary: 'プライバシーポリシーを読む',
  trust: ['すべて端末内', 'アップロードなし', '広告・サブスクなし', '買い切りで解除'],
  featuresTitle: '短い動画と写真一括のために',
  featuresLead: '初版は確実な読み込み・保護・書き出しに集中します。',
  features: [
    {
      title: '動画マスク',
      body: '人物・顔・ペットの検出、または楕円／長方形マスクを配置。移動・サイズ変更とキーフレームに対応。',
    },
    {
      title: '写真一括',
      body: '複数選択して共通設定を適用し、1枚ずつ確認。永久版で一括書き出しを解除。',
    },
    {
      title: '音声プライバシー',
      body: '元の音声のまま、消音、または端末内でピッチ変更。周囲の声も守れます。',
    },
    {
      title: 'メタデータ削除',
      body: '書き出し時に位置情報や端末・撮影日時などの元情報を削除します。',
    },
  ],
  stepsTitle: '動画と写真',
  stepsLead: '素材を選んだあと、動画編集か写真の一括マスクへ進みます。',
  steps: [
    { title: '読み込み', body: '写真または「ファイル」から動画を選択。写真は複数選択可。' },
    { title: '動画', body: '主体検出、マスク範囲、手動マスク。プレビューと書き出しは一致。' },
    { title: '写真', body: '複数選択で一括処理。共通設定のあと、1枚ずつ確認して書き出し。' },
  ],
  pricingTitle: '編集は無料。制限解除は買い切り',
  pricingLead: '編集とプレビューはフル利用可能。書き出し制限は処理パイプライン内で強制されます。',
  freeTitle: '無料版',
  freeBody: '編集とプレビューはすべて使えます。書き出しに制限があります。',
  freePoints: [
    '動画：先頭30秒・最大720p',
    '写真：1回につき1枚',
    '透かしなし・広告なし',
  ],
  proTitle: '永久版',
  proBody: '一度の購入で永久に解除。',
  proBadge: 'おすすめ',
  proPoints: [
    '動画の長さと書き出し解像度の制限解除',
    '写真の一括書き出し',
    '価格は App Store の地域表示に従います',
  ],
  footerTagline: 'reaidea · 端末内プライバシー',
  footerPrivacy: 'プライバシーポリシー',
  footerHome: 'ホーム',
  langLabel: '言語',
  langNames: {
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
    en: 'English',
    ja: '日本語',
  },
}
