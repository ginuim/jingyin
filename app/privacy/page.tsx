import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "隐私政策 / Privacy Policy",
  description: "镜隐 LensHide 隐私政策：iOS App 与网页工具均在设备本地处理素材，不上传原视频与照片。",
  alternates: { canonical: "/privacy" },
};

export default function PrivacyPolicyPage() {
  return (
    <div className="policy-shell">
      <header className="policy-header">
        <Link className="brand" href="/">
          <span className="brand-mark" aria-hidden="true"><img src="/app-icon.png" alt="" width={38} height={38} /></span>
          <span>镜隐 LensHide</span>
        </Link>
        <Link className="policy-back" href="/">返回首页 / Home</Link>
      </header>

      <main className="policy-main">
        <span className="policy-kicker">PRIVACY POLICY</span>
        <h1>隐私政策</h1>
        <p className="policy-lead">
          本政策适用于镜隐 iOS App 与 lenshide.reaidea.com。两者都以设备本地处理为核心：原素材、识别数据和导出结果不上传到镜隐服务器。网页访问日志与 App Store 购买由不同服务提供方处理。
        </p>
        <p className="policy-updated">生效及更新日期：2026 年 7 月 30 日。本页中文全文 + 英文摘要，同一链接供 App Store 审核与英文用户阅读。</p>

        <aside className="policy-summary">
          <strong>最重要的一点：你的照片和视频不会上传给镜隐。</strong>
          <p>素材读取、识别、遮盖、声音处理和导出均在当前设备上完成。镜隐不提供云端存储，也不要求创建账号；我们也不会查看或审核你设备上的内容。</p>
        </aside>

        <div className="policy-content">
          <section>
            <h2>1. iOS App 如何处理数据</h2>
            <ul>
              <li>只有在你主动从照片图库或“文件”中选择照片或视频后，App 才会读取该素材。</li>
              <li>原素材、画面识别结果、蒙版数据和导出结果只在设备本地处理，不会上传到我们的服务器。</li>
              <li>处理过程中可能在 App 沙盒内创建输入副本、中间文件和导出临时文件。App 会清理其识别到的临时文件；你也可以通过删除 App 移除 App 沙盒内的数据。</li>
              <li>首发版不需要账号，不包含广告，也不集成用于跨 App 跟踪的分析 SDK。</li>
            </ul>
          </section>

          <section>
            <h2>2. 本地内容与使用责任</h2>
            <p>镜隐的本地版不会把素材提交到服务器，也不会查看或审核设备上的内容。你可以使用遮盖、像素化、变音和静音等功能处理自己有权使用的素材。</p>
            <p>本地处理不代表任何发布行为都合法。你应确保拥有素材及其中人物的必要授权，并遵守所在地法律、隐私义务和发布平台规则。不得使用镜隐制作、传播违法内容，或侵犯他人的肖像权、隐私权、名誉权和知识产权。</p>
            <p>镜隐不提供社区、公开作品库、云端分享或代用户发布内容。若未来增加云端处理、同步或内容分享功能，会在上线前更新本政策。</p>
          </section>

          <section>
            <h2>3. 照片、文件与权限</h2>
            <p>照片图库和文件权限只用于导入你选择的照片或视频，以及按你的操作保存或分享处理结果。你可以在 iOS“设置”中更改相关权限。</p>
          </section>

          <section>
            <h2>4. App 内购买</h2>
            <p>
              永久版购买由 Apple App Store 处理。镜隐通过 StoreKit 获取产品信息和当前购买权益，用于判断是否解除导出限制；我们不会收到或保存你的银行卡号等支付资料。Apple 对相关数据的处理受
              {" "}<a href="https://www.apple.com/legal/privacy/" rel="noopener noreferrer">Apple 隐私政策</a>约束。
            </p>
          </section>

          <section>
            <h2>5. 网页版与网站访问数据</h2>
            <p>网页版同样在你的设备本地处理视频。为运行识别功能，可能下载并缓存模型文件，但视频内容不会随之上传。</p>
            <p>
              网站托管和安全服务可能自动记录 IP 地址、浏览器类型、访问时间和请求路径等常规访问日志。网页可能使用 Google AdSense；Google 可能依据你的地区、同意选择和浏览器设置使用 Cookie 或设备信息。详情见
              {" "}<a href="https://policies.google.com/privacy" rel="noopener noreferrer">Google 隐私权政策</a>。
            </p>
            <p>这些网站行为与 iOS App 分开；iOS App 本身不含广告。</p>
          </section>

          <section>
            <h2>6. 数据共享、儿童与安全</h2>
            <p>我们不会出售你的视频或识别数据。由于我们不接收视频内容，也无法查看、恢复或代你删除设备上的视频。</p>
            <p>镜隐可用于处理包含儿童的家庭视频，但产品不面向儿童收集个人资料。监护人应决定哪些内容适合导入和公开分享。</p>
          </section>

          <section>
            <h2>7. 政策更新与联系</h2>
            <p>如果产品的数据处理方式发生实质变化，我们会更新本页面及生效日期。隐私问题可通过 <a href="https://reaidea.com" rel="noopener noreferrer">reaidea.com</a> 提供的联系渠道反馈。</p>
          </section>
        </div>

        <div className="policy-content policy-en" lang="en">
          <section>
            <h2>Privacy Policy (English Summary)</h2>
            <p>Effective and last updated: July 30, 2026.</p>
            <p>LensHide processes imported photos and videos, detections, masks, audio changes, and exports locally on your device. We do not upload your media to LensHide servers, provide cloud storage, require an account, or review content stored on your device.</p>
            <p>The iOS app accesses only photos and videos you select through Photos or Files. Temporary working files may be created inside the app sandbox. The app removes temporary files it recognizes, and deleting the app removes data in its sandbox. The launch version contains no advertising or cross-app tracking analytics SDK.</p>
            <p>The local app does not upload or review media stored on your device. You are responsible for having the necessary rights and for complying with applicable law, privacy obligations, and platform rules when editing or publishing material. LensHide does not provide cloud sharing, a public library, or publishing services.</p>
            <p>Lifetime purchases are processed by Apple. The app uses StoreKit product and entitlement information, but we do not receive your payment card details.</p>
            <p>The web tool also processes video locally. Normal hosting logs may include IP address, browser type, time, and request path. The website may use Google AdSense, which may process cookies or device information according to regional consent and browser settings. These website practices are separate from the ad-free iOS app.</p>
            <p>Questions can be sent through the contact options at <a href="https://reaidea.com" rel="noopener noreferrer">reaidea.com</a>.</p>
          </section>
        </div>
      </main>

      <footer className="policy-footer">
        <p>© 2026 镜隐 LensHide</p>
        <nav className="footer-links" aria-label="Footer">
          <Link href="/">首页 / Home</Link>
          <a href="https://reaidea.com" rel="noopener noreferrer">reaidea.com</a>
        </nav>
      </footer>
    </div>
  );
}
