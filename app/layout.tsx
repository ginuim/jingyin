import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";
import { GoogleAdsense } from "./google-adsense";
import { REAIDEA_THEME_BOOT_SCRIPT } from "./i18n/reaidea-theme";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") || requestHeaders.get("host") || "localhost:3000";
  const protocol = requestHeaders.get("x-forwarded-proto") || (host.startsWith("localhost") ? "http" : "https");
  const origin = `${protocol}://${host}`;
  return {
    metadataBase: new URL(origin),
    title: { default: "镜隐 LensHide｜本地视频与照片隐私打码", template: "%s｜镜隐 LensHide" },
    description: "纯本地处理的视频与照片隐私工具：打码、变音或静音，素材不上传。适合分享家人照片/视频、给路人打码。On-device video & photo privacy—nothing uploaded.",
    keywords: ["视频打码", "照片打码", "本地处理", "视频变音", "视频静音", "路人打码", "儿童视频隐私", "家人照片隐私", "隐私保护", "video blur", "photo blur", "on-device"],
    applicationName: "镜隐 LensHide",
    authors: [{ name: "镜隐" }],
    creator: "镜隐",
    alternates: { canonical: "/" },
    openGraph: {
      type: "website",
      locale: "zh_CN",
      siteName: "镜隐",
      url: origin,
      title: "镜隐｜纯本地视频与照片隐私打码",
      description: "分享家人照片和视频前，在设备本地给人物与路人打码，并可变音或静音。原素材不上传。",
      images: [{ url: `${origin}/og.png`, width: 1200, height: 630, alt: "镜隐本地隐私打码" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "镜隐｜纯本地视频与照片隐私打码",
      description: "分享家人照片和视频前，在设备本地给人物与路人打码。原素材不上传。",
      images: [`${origin}/og.png`],
    },
    robots: { index: true, follow: true },
    icons: {
      icon: [
        { url: "/favicon.ico", sizes: "any" },
        { url: "/favicon-32.png", sizes: "32x32", type: "image/png" },
        { url: "/favicon-16.png", sizes: "16x16", type: "image/png" },
      ],
      apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
      shortcut: "/favicon.ico",
    },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#1c1614" },
    { media: "(prefers-color-scheme: light)", color: "#fff7f2" },
  ],
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") || requestHeaders.get("host") || "";

  return (
    <html lang="zh-CN" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: REAIDEA_THEME_BOOT_SCRIPT }} />
        <GoogleAdsense host={host} />
      </head>
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
