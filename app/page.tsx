import type { Metadata } from "next";
import PrivacyStudio from "./privacy-studio";
import { LocaleProvider } from "./i18n/locale";
import { ThemeProvider } from "./i18n/theme";

export const metadata: Metadata = {
  title: "本地视频与照片隐私打码｜分享家人前先打码",
  description: "镜隐在设备本地处理照片与视频：给家人、路人打码，变音或静音。原素材与导出结果不上传服务器。",
};

export default function Home() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "镜隐 LensHide",
    applicationCategory: "MultimediaApplication",
    operatingSystem: "iOS, Web",
    description: "端侧视频与照片隐私工具：本地打码、变音或静音，原素材与导出结果不上传服务器。适合分享家人照片/视频前给路人打码。",
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
