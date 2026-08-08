<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import PhoneFrame from '../components/PhoneFrame.vue'
import SiteFooter from '../components/SiteFooter.vue'
import SiteHeader from '../components/SiteHeader.vue'
import { APP_STORE_URL } from '../config'
import { getDictionary, privacyPath, type Locale } from '../i18n'

const route = useRoute()
const locale = computed(() => (route.meta.locale as Locale) ?? 'zh-Hans')
const copy = computed(() => getDictionary(locale.value).landing)
const storeReady = computed(() => Boolean(APP_STORE_URL))

const homeShot = computed(() => `/screenshots/home-${locale.value}.png`)
const editorShot = computed(() => `/screenshots/editor-${locale.value}.png`)
const photoShot = computed(() => `/screenshots/photo-${locale.value}.png`)
const paywallShot = computed(() => `/screenshots/paywall-${locale.value}.png`)

const stepShots = computed(() => [
  { src: homeShot.value, key: 0 },
  { src: editorShot.value, key: 1 },
  { src: photoShot.value, key: 2 },
])
</script>

<template>
  <div class="page">
    <SiteHeader />

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
            id="download"
            class="btn btn-primary"
            :href="storeReady ? APP_STORE_URL : '#download'"
            :aria-disabled="!storeReady"
            :class="{ 'is-disabled': !storeReady }"
          >
            {{ storeReady ? copy.navDownload : copy.heroCta }}
          </a>
          <RouterLink class="btn btn-ghost" :to="privacyPath(locale)">
            {{ copy.heroSecondary }}
          </RouterLink>
        </div>
        <ul class="trust">
          <li v-for="item in copy.trust" :key="item">{{ item }}</li>
        </ul>
      </div>
      <div class="hero-media">
        <PhoneFrame :src="homeShot" :alt="copy.brand" />
      </div>
    </section>

    <section class="section shell">
      <div class="section-head">
        <div class="eyebrow">Features</div>
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

    <section class="section shell">
      <div class="section-head">
        <div class="eyebrow">Flow</div>
        <h2>{{ copy.stepsTitle }}</h2>
        <p>{{ copy.stepsLead }}</p>
      </div>
      <div class="steps">
        <article v-for="(step, index) in copy.steps" :key="step.title">
          <PhoneFrame :src="stepShots[index]!.src" :alt="step.title" />
          <div class="step-copy">
            <span>{{ String(index + 1).padStart(2, '0') }}</span>
            <h3>{{ step.title }}</h3>
            <p>{{ step.body }}</p>
          </div>
        </article>
      </div>
    </section>

    <section class="section shell pricing">
      <div class="section-head">
        <div class="eyebrow">Access</div>
        <h2>{{ copy.pricingTitle }}</h2>
        <p>{{ copy.pricingLead }}</p>
      </div>
      <div class="price-grid">
        <article>
          <h3>{{ copy.freeTitle }}</h3>
          <p>{{ copy.freeBody }}</p>
          <ul>
            <li v-for="point in copy.freePoints" :key="point">{{ point }}</li>
          </ul>
        </article>
        <article class="pro">
          <h3>{{ copy.proTitle }}</h3>
          <p>{{ copy.proBody }}</p>
          <ul>
            <li v-for="point in copy.proPoints" :key="point">{{ point }}</li>
          </ul>
          <img class="paywall-shot" :src="paywallShot" :alt="copy.proTitle" />
        </article>
      </div>
    </section>

    <SiteFooter />
  </div>
</template>

<style scoped>
.hero {
  display: grid;
  grid-template-columns: minmax(0, 1.05fr) minmax(260px, 0.85fr);
  gap: 48px;
  align-items: center;
  padding: 36px 0 72px;
}

.hero-copy h1 {
  margin: 18px 0 16px;
  font-size: clamp(40px, 6vw, 64px);
  line-height: 1.05;
  letter-spacing: -0.05em;
  font-weight: 730;
}

.hero-copy h1 span {
  display: block;
  color: var(--accent-outline);
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
  margin-top: 26px;
}

.trust {
  list-style: none;
  margin: 28px 0 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.trust li {
  padding: 8px 12px;
  border-radius: 999px;
  background: var(--accent-soft);
  border: 1px solid rgba(226, 138, 96, 0.35);
  color: var(--accent-outline);
  font-size: 12px;
  font-weight: 650;
}

.section {
  padding: 36px 0 56px;
}

.section-head {
  max-width: 640px;
  margin-bottom: 28px;
}

.section-head h2 {
  margin: 12px 0 10px;
  font-size: clamp(28px, 4vw, 40px);
  letter-spacing: -0.04em;
}

.section-head p {
  margin: 0;
  color: var(--secondary);
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}

.feature-grid article,
.price-grid article {
  padding: 22px 20px;
  border-radius: var(--radius-lg);
  background: rgba(42, 33, 30, 0.88);
  border: 1px solid var(--divider);
}

.feature-grid h3,
.price-grid h3,
.step-copy h3 {
  margin: 0 0 8px;
  font-size: 18px;
  letter-spacing: -0.02em;
}

.feature-grid p,
.price-grid p,
.step-copy p {
  margin: 0;
  color: var(--secondary);
  font-size: 14px;
  line-height: 1.65;
}

.steps {
  display: grid;
  gap: 22px;
}

.steps article {
  display: grid;
  grid-template-columns: 220px minmax(0, 1fr);
  gap: 28px;
  align-items: center;
  padding: 18px;
  border-radius: var(--radius-lg);
  background: rgba(42, 33, 30, 0.55);
  border: 1px solid var(--divider);
}

.step-copy span {
  display: inline-block;
  margin-bottom: 8px;
  color: var(--muted);
  font: 700 12px/1 var(--mono);
  letter-spacing: 0.08em;
}

.price-grid {
  display: grid;
  grid-template-columns: 1fr 1.15fr;
  gap: 14px;
}

.price-grid ul {
  margin: 14px 0 0;
  padding-left: 18px;
  color: var(--secondary);
  font-size: 14px;
  line-height: 1.7;
}

.price-grid article.pro {
  background: linear-gradient(160deg, rgba(208, 100, 50, 0.16), rgba(42, 33, 30, 0.95));
  border-color: rgba(226, 138, 96, 0.45);
}

.paywall-shot {
  margin-top: 18px;
  width: min(100%, 220px);
  border-radius: 18px;
  border: 1px solid var(--divider);
}

@media (max-width: 900px) {
  .hero {
    grid-template-columns: 1fr;
    padding-top: 18px;
  }

  .hero-media {
    order: -1;
  }

  .steps article {
    grid-template-columns: 1fr;
  }

  .feature-grid,
  .price-grid {
    grid-template-columns: 1fr;
  }
}
</style>
