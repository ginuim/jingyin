import type { Metadata } from "next";
import PrivacyStudio from "./privacy-studio";

export const metadata: Metadata = {
  title: "在线视频隐私打码｜保护孩子与家人的视频",
  description: "发布孩子、家人或街拍视频前，在浏览器本地隐藏人物与环境，减少清晰人像被截取、冒用或用于 AI 换脸的风险。视频不上传服务器。",
};

export default function Home() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "WebApplication",
    name: "镜隐",
    applicationCategory: "MultimediaApplication",
    operatingSystem: "Web Browser",
    description: "纯浏览器运行的在线视频隐私打码工具，帮助保护孩子、家人、路人与拍摄环境，视频无需上传服务器。",
    offers: { "@type": "Offer", price: "0", priceCurrency: "CNY" },
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <PrivacyStudio />
    </>
  );
}
