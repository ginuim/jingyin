import type { Metadata } from "next";
import PrivacyStudio from "./privacy-studio";
import { LocaleProvider } from "./i18n/locale";
import { ThemeProvider } from "./i18n/theme";

export const metadata: Metadata = {
  title: "在线视频隐私打码｜保护孩子与家人的视频",
  description: "发布孩子、家人或街拍视频前，在浏览器本地隐藏人物与环境，并进行变音或静音，减少人像与声音被冒用、用于 AI 换脸或声音克隆的风险。",
};

export default function Home() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "WebApplication",
    name: "镜隐",
    applicationCategory: "MultimediaApplication",
    operatingSystem: "Web Browser",
    description: "纯浏览器运行的在线视频隐私工具，可遮盖人物与环境、变音或静音，视频无需上传服务器。",
    offers: { "@type": "Offer", price: "0", priceCurrency: "CNY" },
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <ThemeProvider>
        <LocaleProvider>
          <PrivacyStudio />
        </LocaleProvider>
      </ThemeProvider>
    </>
  );
}
