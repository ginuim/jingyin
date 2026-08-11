<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import SiteFooter from '../components/SiteFooter.vue'
import SiteHeader from '../components/SiteHeader.vue'
import { APP_STORE_URL } from '../config'
import { getDictionary, privacyPath, type Locale } from '../i18n'

const route = useRoute()
const locale = computed(() => (route.meta.locale as Locale) ?? 'zh-Hans')
const copy = computed(() => getDictionary(locale.value).landing)
const storeReady = computed(() => Boolean(APP_STORE_URL))

const homeShot = computed(() => `/screenshots/home-device-${locale.value}.png`)
const editorShot = computed(() => `/screenshots/editor-device-${locale.value}.png`)
const photoShot = computed(() => `/screenshots/photo-device-${locale.value}.png`)

const paths = computed(() => [
  { ...copy.value.steps[0], src: editorShot.value },
  { ...copy.value.steps[1], src: photoShot.value },
])
</script>

<template>
  <div class="page">
    <SiteHeader />

    <main>
    <section class="hero shell">
      <div class="hero-copy">
        <div class="eyebrow">{{ copy.heroEyebrow }}</div>
        <h1>
          {{ copy.heroTitle }}
          <span>{{ copy.heroHighlight }}</span>
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
        <img
          class="hero-device"
          :src="homeShot"
          :alt="`${copy.brand} ${copy.heroTitle}`"
          width="759"
          height="1600"
        />
      </div>
    </section>

    <section class="section shell">
      <div class="section-head">
        <div class="eyebrow">{{ copy.sectionLabels.features }}</div>
        <h2>{{ copy.featuresTitle }}</h2>
        <p>{{ copy.featuresLead }}</p>
      </div>
      <div class="feature-grid">
        <article v-for="feature in copy.features" :key="feature.title">
          <h3>{{ feature.title }}</h3>
          <p>{{ feature.body }}</p>
        </article>
      </div>
    </section>

    <section class="section shell steps-section">
      <div class="section-head">
        <div class="eyebrow">{{ copy.sectionLabels.paths }}</div>
        <h2>{{ copy.stepsTitle }}</h2>
        <p>{{ copy.stepsLead }}</p>
      </div>
      <div class="steps-panel">
        <div class="steps">
          <article v-for="path in paths" :key="path.title">
            <img class="path-device" :src="path.src" :alt="path.title" width="569" height="1200" />
            <div class="step-copy">
              <h3>{{ path.title }}</h3>
              <p>{{ path.body }}</p>
            </div>
          </article>
        </div>
      </div>
    </section>

    <section class="section shell pricing">
      <div class="section-head">
        <div class="eyebrow">{{ copy.sectionLabels.access }}</div>
        <h2>{{ copy.pricingTitle }}</h2>
        <p>{{ copy.pricingLead }}</p>
      </div>
      <div class="price-panel">
        <article class="free">
          <h3>{{ copy.freeTitle }}</h3>
          <p>{{ copy.freeBody }}</p>
          <ul>
            <li v-for="point in copy.freePoints" :key="point">{{ point }}</li>
          </ul>
        </article>
        <article class="pro">
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
.hero {
  display: grid;
  grid-template-columns: minmax(0, 1.1fr) minmax(280px, 0.85fr);
  gap: 40px;
  align-items: center;
  padding: 48px 0 88px;
}

.hero-copy h1 {
  margin: 20px 0 18px;
  font-size: clamp(40px, 5vw, 56px);
  line-height: 1.05;
  letter-spacing: -0.05em;
  font-weight: 730;
}

.hero-copy .eyebrow {
  text-transform: none;
}

.hero-copy h1 span {
  display: block;
  background: linear-gradient(100deg, var(--accent-outline), #f0a67e 60%, var(--accent-outline));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.hero-copy > p {
  margin: 0;
  max-width: 34em;
  color: var(--secondary);
  font-size: 17px;
  line-height: 1.7;
}

.hero-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 28px;
}

.hero-media {
  position: relative;
  display: flex;
  justify-content: center;
}

.hero-media::before {
  content: '';
  position: absolute;
  inset: 8% 12%;
  background: radial-gradient(closest-side, var(--accent-glow), transparent 72%);
  filter: blur(12px);
  z-index: -1;
}

.hero-device {
  display: block;
  width: min(100%, 352px);
  height: auto;
  filter: drop-shadow(0 36px 64px rgba(0, 0, 0, 0.55));
}

.trust {
  list-style: none;
  margin: 30px 0 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.trust li {
  padding: 8px 13px;
  border-radius: 999px;
  background: var(--accent-soft);
  border: 1px solid rgba(226, 138, 96, 0.28);
  color: var(--accent-outline);
  font-size: 12px;
  font-weight: 650;
}

.section {
  padding: 48px 0 64px;
}

.section + .section {
  border-top: 1px solid rgba(255, 244, 238, 0.05);
}

.section-head {
  max-width: 640px;
  margin-bottom: 32px;
}

.section-head h2 {
  margin: 14px 0 12px;
  font-size: clamp(28px, 4vw, 40px);
  letter-spacing: -0.04em;
  line-height: 1.12;
}

.section-head p {
  margin: 0;
  color: var(--secondary);
  line-height: 1.65;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}

.feature-grid article {
  padding: 24px 22px;
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

.steps-section .section-head {
  margin-bottom: 24px;
}

.steps-panel {
  padding: 28px 20px 24px;
  border-radius: var(--radius-lg);
  background: var(--card);
  border: 1px solid var(--card-border);
  box-shadow: inset 0 1px 0 rgba(255, 244, 238, 0.05);
}

.steps {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px 0;
  align-items: stretch;
}

.steps article {
  display: grid;
  grid-template-rows: auto 1fr;
  gap: 14px;
  justify-items: center;
  text-align: center;
  padding: 4px 22px 0;
}

.steps .path-device {
  display: block;
  width: min(100%, 220px);
  height: auto;
  filter: drop-shadow(0 16px 26px rgba(0, 0, 0, 0.42));
}

.step-copy {
  max-width: 22em;
}

.step-copy h3 {
  margin-bottom: 6px;
}

.price-panel {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
  border-radius: var(--radius-lg);
  background: var(--card);
  border: 1px solid var(--card-border);
  box-shadow: inset 0 1px 0 rgba(255, 244, 238, 0.05);
  overflow: hidden;
}

.price-panel article {
  padding: 26px 28px;
}

.price-panel article.pro {
  border-left: 1px solid rgba(255, 244, 238, 0.08);
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

@media (max-width: 900px) {
  .hero {
    grid-template-columns: 1fr;
    gap: 36px;
    padding: 28px 0 64px;
  }

  .hero-media::before {
    inset: 4% 10%;
  }

  .steps-panel {
    padding: 16px;
  }

  .steps {
    grid-template-columns: 1fr;
    gap: 0;
  }

  .steps article {
    grid-template-columns: minmax(0, 140px) minmax(0, 1fr);
    grid-template-rows: auto;
    align-items: center;
    justify-items: stretch;
    text-align: left;
    gap: 16px 18px;
    padding: 16px 4px;
  }

  .steps article + article {
    border-top: 1px solid rgba(255, 244, 238, 0.06);
  }

  .steps .path-device {
    width: 100%;
    max-width: 140px;
  }

  .step-copy {
    max-width: none;
  }

  .feature-grid {
    grid-template-columns: 1fr;
  }

  .price-panel {
    grid-template-columns: 1fr;
  }

  .price-panel article.pro {
    border-left: 0;
    border-top: 1px solid rgba(255, 244, 238, 0.08);
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
