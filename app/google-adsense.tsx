const DEFAULT_PUBLISHER_ID = "ca-pub-1445418365552396";
const PRODUCTION_HOST = "lenshide.reaidea.com";

type GoogleAdsenseProps = {
  host: string;
};

function adsenseIsEnabled(host: string) {
  const override = process.env.NEXT_PUBLIC_GOOGLE_ADSENSE_ENABLED?.trim();
  if (override === "true") return true;
  if (override === "false") return false;

  return host.split(":")[0].toLowerCase() === PRODUCTION_HOST;
}

export function GoogleAdsense({ host }: GoogleAdsenseProps) {
  if (!adsenseIsEnabled(host)) return null;

  const publisherId =
    process.env.NEXT_PUBLIC_GOOGLE_ADSENSE_CLIENT?.trim() ||
    DEFAULT_PUBLISHER_ID;

  return (
    <>
      <meta name="google-adsense-account" content={publisherId} />
      <script
        async
        crossOrigin="anonymous"
        src={`https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${publisherId}`}
      />
    </>
  );
}
