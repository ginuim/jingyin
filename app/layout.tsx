import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") || requestHeaders.get("host") || "localhost:3000";
  const protocol = requestHeaders.get("x-forwarded-proto") || (host.startsWith("localhost") ? "http" : "https");
  const origin = `${protocol}://${host}`;
  return {
    metadataBase: new URL(origin),
    title: { default: "镜隐 LensHide｜本地视频隐私打码", template: "%s｜镜隐 LensHide" },
    description: "免费的在线视频隐私工具：浏览器本地打码、变音或静音，视频不上传。Free local video blur, pitch shift, and mute—nothing leaves your device.",
    keywords: ["视频打码", "视频变音", "视频静音", "声音隐私", "儿童视频隐私", "AI 换脸防护", "声音克隆防护", "视频人物打码", "在线视频模糊", "隐私保护", "video blur"],
    applicationName: "镜隐 LensHide",
    authors: [{ name: "镜隐" }],
    creator: "镜隐",
    alternates: { canonical: "/" },
    openGraph: {
      type: "website",
      locale: "zh_CN",
      siteName: "镜隐",
      url: origin,
      title: "镜隐｜视频不出设备的 AI 打码工具",
      description: "发布孩子或家人视频前，本地隐藏人物与环境，并进行变音或静音。整个过程只在你的浏览器里完成。",
      images: [{ url: `${origin}/og.png`, width: 1200, height: 630, alt: "镜隐视频隐私打码工具" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "镜隐｜视频不出设备的 AI 打码工具",
      description: "发布孩子或家人视频前，本地隐藏人物、环境和声音身份。整个过程只在你的浏览器里完成。",
      images: [`${origin}/og.png`],
    },
    robots: { index: true, follow: true },
    icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#f7f7f2",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
