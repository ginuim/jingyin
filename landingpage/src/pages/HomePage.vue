<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import Eyebrow from '../components/Eyebrow.vue'
import SiteFooter from '../components/SiteFooter.vue'
import SiteHeader from '../components/SiteHeader.vue'
import { APP_STORE_URL } from '../config'
import { getDictionary, privacyPath, type Locale } from '../i18n'
import { useLandingMotion } from '../motion/useLandingMotion'

const route = useRoute()
const locale = computed(() => (route.meta.locale as Locale) ?? 'zh-Hans')
const copy = computed(() => getDictionary(locale.value).landing)
const storeReady = computed(() => Boolean(APP_STORE_URL))

const homeShot = computed(() => `/screenshots/home-device-${locale.value}.webp`)
const editorShot = computed(() => `/screenshots/editor-device-${locale.value}.png`)
const photoShot = computed(() => `/screenshots/photo-device-${locale.value}.png`)

const paths = computed(() => [
  { ...copy.value.steps[0], src: editorShot.value },
  { ...copy.value.steps[1], src: photoShot.value },
])

const pageEl = ref<HTMLElement>()
useLandingMotion(pageEl, locale)
</script>

<template>
  <div ref="pageEl" class="page">
    <SiteHeader />

    <main>
    <section class="hero">
      <div class="hero-copy" :key="locale">
        <Eyebrow class="hero-eyebrow" :text="copy.heroEyebrow" />
        <h1>
          <span class="hero-title-line">{{ copy.heroTitle }}</span>
          <span class="hero-highlight">{{ copy.heroHighlight }}</span>
        </h1>
        <p>{{ copy.heroBody }}</p>
        <div class="hero-actions">
          <a
            v-if="storeReady"
            id="download"
            class="btn btn-primary"
            :href="APP_STORE_URL"
          >
            {{ copy.navDownload }}
          </a>
          <span v-else id="download" class="btn btn-primary is-disabled" aria-disabled="true">
            {{ copy.heroCta }}
          </span>
          <RouterLink class="btn btn-ghost" :to="privacyPath(locale)">
            {{ copy.heroSecondary }}
          </RouterLink>
        </div>
        <ul class="trust">
          <li v-for="item in copy.trust" :key="item">{{ item }}</li>
        </ul>
      </div>
      <div class="hero-media">
        <div class="hero-device-shift">
          <img
            class="hero-device"
            :src="homeShot"
            :alt="`${copy.brand} ${copy.heroTitle}`"
            width="2212"
            height="1478"
          />
        </div>
      </div>
    </section>

    <section class="section shell">
      <div class="section-head" data-reveal>
        <Eyebrow :text="copy.sectionLabels.features" />
        <h2>{{ copy.featuresTitle }}</h2>
        <p>{{ copy.featuresLead }}</p>
      </div>
      <div class="feature-grid">
        <article v-for="feature in copy.features" :key="feature.title" data-reveal>
          <h3>{{ feature.title }}</h3>
          <p>{{ feature.body }}</p>
        </article>
      </div>
    </section>

    <section class="section shell steps-section">
      <div class="section-head" data-reveal>
        <Eyebrow :text="copy.sectionLabels.paths" />
        <h2>{{ copy.stepsTitle }}</h2>
        <p>{{ copy.stepsLead }}</p>
      </div>
      <div class="steps">
        <article v-for="(path, i) in paths" :key="path.title" data-reveal>
          <div class="step-media">
            <img class="path-device" :src="path.src" :alt="path.title" width="621" height="1200" />
          </div>
          <div class="step-copy">
            <span class="step-index" aria-hidden="true">0{{ i + 1 }}</span>
            <h3>{{ path.title }}</h3>
            <p>{{ path.body }}</p>
          </div>
        </article>
      </div>
    </section>

    <section class="section shell pricing">
      <div class="section-head" data-reveal>
        <Eyebrow :text="copy.sectionLabels.access" />
        <h2>{{ copy.pricingTitle }}</h2>
        <p>{{ copy.pricingLead }}</p>
      </div>
      <div class="price-panel">
        <article class="free" data-reveal>
          <h3>{{ copy.freeTitle }}</h3>
          <p>{{ copy.freeBody }}</p>
          <ul>
            <li v-for="point in copy.freePoints" :key="point">{{ point }}</li>
          </ul>
        </article>
        <article class="pro" data-reveal>
          <div class="pro-head">
            <h3>{{ copy.proTitle }}</h3>
            <span class="pro-badge">{{ copy.proBadge }}</span>
          </div>
          <p>{{ copy.proBody }}</p>
          <ul>
            <li v-for="point in copy.proPoints" :key="point">{{ point }}</li>
          </ul>
        </article>
      </div>
    </section>
    </main>

    <SiteFooter />
  </div>
</template>

<style scoped>
.page {
  overflow-x: hidden;
}

/* ---- Hero：满宽容器 + 内容限宽；大图钉在底部，超出一屏的部分被裁掉 ---- */
.hero {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(340px, 520px);
  grid-template-rows: auto;
  align-items: center;
  gap: 32px;
  padding: 24px max(20px, calc((100% - var(--max)) / 2)) 56px;
  min-height: calc(100vh - 68px);
  min-height: calc(100svh - 68px);
}

.hero-copy {
  grid-column: 2;
  grid-row: 1;
  position: relative;
  z-index: 1;
  padding: 36px 0;
}

.hero-copy h1 {
  margin: 18px 0 20px;
  font-size: clamp(32px, 3.6vw, 48px);
  line-height: 1.18;
  letter-spacing: -0.02em;
  font-weight: 750;
  font-kerning: none;
  text-rendering: optimizeSpeed;
}

.hero-copy .eyebrow {
  text-transform: none;
}

.hero-title-line {
  display: inline;
}

.hero-highlight {
  display: block;
  margin-top: 8px;
  color: var(--accent-outline);
}

.hero-copy > p {
  margin: 0;
  max-width: 34em;
  color: var(--secondary);
  font-size: 16px;
  line-height: 1.75;
  text-wrap: pretty;
}

.hero-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 28px;
}

.hero-media {
  grid-column: 1;
  grid-row: 1;
  position: relative;
  align-self: stretch;
  z-index: 0;
  pointer-events: none;
}

.hero-device-shift {
  position: relative;
  height: 100%;
}

.hero-media::before {
  content: '';
  position: absolute;
  inset: 22% -6% -12% -10%;
  background: radial-gradient(closest-side, var(--accent-glow), transparent 72%);
  filter: blur(24px);
  z-index: 0;
  pointer-events: none;
}

/* 素材是 4424×2956、带透明边距的斜置渲染图；放大并下沉，底部超出一屏被裁 */
.hero-device {
  position: absolute;
  z-index: 1;
  left: -100%;
  bottom: -68%;
  display: block;
  width: 302%;
  max-width: none;
  height: auto;
  transform: rotate(10deg);
  filter: drop-shadow(0 28px 48px rgba(0, 0, 0, 0.5));
}

.trust {
  list-style: none;
  margin: 30px 0 0;
  padding: 18px 0 0;
  border-top: 1px solid rgba(255, 244, 238, 0.07);
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 9px 14px;
}

.trust li {
  color: var(--secondary);
  font-size: 13px;
  font-weight: 550;
  line-height: 1.4;
}

.trust li::before {
  content: '';
  display: inline-block;
  width: 5px;
  height: 5px;
  margin-right: 8px;
  border-radius: 50%;
  background: var(--accent-outline);
  vertical-align: 2px;
}

/* ---- 区块节奏 ---- */
.section {
  padding: 72px 0 88px;
}

.section + .section {
  border-top: 1px solid rgba(255, 244, 238, 0.05);
}

.section-head {
  max-width: 640px;
  margin-bottom: 40px;
}

.section-head h2 {
  margin: 14px 0 12px;
  font-size: clamp(28px, 4vw, 40px);
  letter-spacing: -0.04em;
  line-height: 1.12;
  text-wrap: balance;
}

.section-head p {
  margin: 0;
  color: var(--secondary);
  line-height: 1.65;
  text-wrap: pretty;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.feature-grid article {
  padding: 26px 24px;
  border-radius: var(--radius-lg);
  background: var(--card);
  border: 1px solid var(--card-border);
  box-shadow: inset 0 1px 0 rgba(255, 244, 238, 0.05);
  transition:
    transform 0.18s ease,
    border-color 0.18s ease,
    box-shadow 0.18s ease;
}

.feature-grid article:hover {
  transform: translateY(-3px);
  border-color: rgba(226, 138, 96, 0.4);
  box-shadow:
    0 14px 30px rgba(0, 0, 0, 0.28),
    inset 0 1px 0 rgba(255, 244, 238, 0.06);
}

.feature-grid h3,
.price-panel h3,
.step-copy h3 {
  margin: 0 0 8px;
  font-size: 18px;
  letter-spacing: -0.02em;
}

.feature-grid p,
.price-panel p,
.step-copy p {
  margin: 0;
  color: var(--secondary);
  font-size: 14px;
  line-height: 1.65;
}

/* 处理路径：无外框，双机错位摆放 + accent 底光 */
.steps {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 24px 48px;
  align-items: start;
}

.step-media {
  position: relative;
  display: flex;
  justify-content: center;
}

.step-media::before {
  content: '';
  position: absolute;
  inset: 10% 16%;
  z-index: 0;
  background: radial-gradient(closest-side, var(--accent-glow), transparent 75%);
  filter: blur(20px);
  pointer-events: none;
}

.steps .path-device {
  position: relative;
  z-index: 1;
  display: block;
  width: min(100%, 320px);
  height: auto;
  filter: drop-shadow(0 20px 32px rgba(0, 0, 0, 0.45));
}

.step-copy {
  margin: 24px auto 0;
  padding: 0;
  max-width: 24em;
  text-align: center;
}

.step-index {
  display: block;
  margin-bottom: 10px;
  color: var(--accent-outline);
  font: 700 12px/1 var(--mono);
  letter-spacing: 0.14em;
}

.price-panel {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 16px;
}

.price-panel article {
  padding: 32px 30px 34px;
  border-radius: var(--radius-lg);
  background: var(--card);
  border: 1px solid var(--card-border);
  box-shadow: inset 0 1px 0 rgba(255, 244, 238, 0.05);
}

.price-panel h3 {
  font-size: 20px;
}

.price-panel article > p {
  font-size: 15px;
}

/* 永久版：accent 微光底 + 描边 + 投影，和免费版拉开层级 */
.price-panel article.pro {
  background:
    radial-gradient(140% 130% at 85% 0%, rgba(208, 100, 50, 0.2), transparent 60%),
    var(--card);
  border-color: rgba(226, 138, 96, 0.45);
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.32),
    inset 0 1px 0 rgba(255, 244, 238, 0.08);
}

.price-panel ul {
  list-style: none;
  margin: 16px 0 0;
  padding: 0;
  color: var(--secondary);
  font-size: 14px;
  line-height: 1.7;
}

.price-panel li {
  position: relative;
  padding-left: 18px;
  margin-bottom: 8px;
}

.price-panel li:last-child {
  margin-bottom: 0;
}

.price-panel li::before {
  content: '·';
  position: absolute;
  left: 0;
  top: 0;
  color: var(--muted);
  font-size: 22px;
  line-height: 0.9;
}

.price-panel .pro li::before {
  color: var(--accent-outline);
}

.pro-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 8px;
  min-height: 28px;
}

.price-panel .free h3 {
  min-height: 28px;
  display: flex;
  align-items: center;
}

.pro-head h3 {
  margin: 0;
  white-space: nowrap;
}

.pro-badge {
  flex-shrink: 0;
  padding: 4px 10px;
  border-radius: 999px;
  background: var(--accent-soft);
  border: 1px solid rgba(226, 138, 96, 0.4);
  color: var(--accent-outline);
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.02em;
}

/* ---- 动效：GSAP 入场前先藏起来，避免闪一帧；reduced-motion 走 matchMedia 直接显示 ---- */
.hero-copy :deep(.char) {
  display: inline-block;
}

@media (prefers-reduced-motion: no-preference) {
  .hero-eyebrow,
  .hero-title-line,
  .hero-highlight,
  .hero-copy > p,
  .hero-actions,
  .trust li,
  .hero-media,
  [data-reveal] {
    opacity: 0;
  }
}

@media (max-width: 900px) {
  .hero {
    grid-template-columns: 1fr;
    gap: 4px;
    min-height: 0;
    padding-top: 28px;
    padding-bottom: 48px;
    overflow: visible;
  }

  .hero-copy,
  .hero-media {
    grid-column: 1;
    grid-row: auto;
  }

  .hero-copy {
    padding: 8px 0 0;
  }

  .hero-copy h1 {
    font-size: clamp(30px, 8.4vw, 40px);
  }

  .hero-media {
    align-self: auto;
    margin-top: 8px;
  }

  .hero-device-shift {
    height: auto;
  }

  .hero-media::before {
    inset: 4% 8%;
  }

  .hero-device {
    position: static;
    width: 116%;
    margin: -2% -8% -8%;
  }

  .section {
    padding: 56px 0 64px;
  }

  .section-head {
    margin-bottom: 28px;
  }

  .steps {
    grid-template-columns: 1fr;
    gap: 56px;
  }

  .steps .path-device {
    width: min(76%, 240px);
  }

  .feature-grid {
    grid-template-columns: 1fr;
  }

  .price-panel {
    grid-template-columns: 1fr;
  }
}

@media (prefers-reduced-motion: reduce) {
  .feature-grid article {
    transition: none;
  }

  .feature-grid article:hover {
    transform: none;
  }
}
</style>
