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
    title: { default: "镜隐｜在线视频隐私打码工具", template: "%s｜镜隐" },
    description: "免费的在线视频打码工具。AI 自动识别人物、车辆与宠物，视频全程仅在本地浏览器处理，完成后直接下载。",
    keywords: ["视频打码", "视频人物打码", "在线视频模糊", "隐私保护", "AI 视频处理", "video blur"],
    applicationName: "镜隐",
    authors: [{ name: "镜隐" }],
    creator: "镜隐",
    alternates: { canonical: "/" },
    openGraph: {
      type: "website",
      locale: "zh_CN",
      siteName: "镜隐",
      url: origin,
      title: "镜隐｜视频不出设备的 AI 打码工具",
      description: "上传、选择、打码、下载。整个过程只在你的浏览器里完成。",
      images: [{ url: `${origin}/og.png`, width: 1200, height: 630, alt: "镜隐视频隐私打码工具" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "镜隐｜视频不出设备的 AI 打码工具",
      description: "上传、选择、打码、下载。整个过程只在你的浏览器里完成。",
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
