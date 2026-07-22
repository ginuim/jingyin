import type { Metadata } from "next";
import PrivacyStudio from "./privacy-studio";

export const metadata: Metadata = {
  title: "在线给视频人物打码",
  description: "上传视频，AI 自动识别人物、车辆和宠物并打码。视频只在你的浏览器中处理，不上传服务器。",
};

export default function Home() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "WebApplication",
    name: "镜隐",
    applicationCategory: "MultimediaApplication",
    operatingSystem: "Web Browser",
    description: "纯浏览器运行的在线视频隐私打码工具。",
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
