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
        <article class="free">
          <h3>{{ copy.freeTitle }}</h3>
          <p>{{ copy.freeBody }}</p>
          <ul>
            <li v-for="point in copy.freePoints" :key="point">{{ point }}</li>
          </ul>
        </article>
        <article class="pro">
          <span class="pro-badge">{{ copy.proBadge }}</span>
          <div class="pro-main">
            <div class="pro-copy">
              <h3>{{ copy.proTitle }}</h3>
              <p>{{ copy.proBody }}</p>
              <ul>
                <li v-for="point in copy.proPoints" :key="point">{{ point }}</li>
              </ul>
            </div>
            <img class="paywall-shot" :src="paywallShot" :alt="copy.proTitle" />
          </div>
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
  padding: 48px 0 88px;
}

.hero-copy h1 {
  margin: 20px 0 18px;
  font-size: clamp(40px, 6vw, 64px);
  line-height: 1.05;
  letter-spacing: -0.05em;
  font-weight: 730;
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
}

.hero-media::before {
  content: '';
  position: absolute;
  inset: 6% -8%;
  background: radial-gradient(closest-side, var(--accent-glow), transparent 72%);
  filter: blur(12px);
  z-index: -1;
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

.feature-grid article,
.price-grid article {
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
  gap: 64px;
}

.steps article {
  display: grid;
  grid-template-columns: minmax(0, 0.95fr) minmax(0, 1.05fr);
  gap: 48px;
  align-items: center;
}

.steps article:nth-child(even) .phone {
  order: 2;
}

.steps .phone {
  width: min(100%, 250px);
}

.step-copy span {
  display: inline-block;
  margin-bottom: 10px;
  color: var(--accent-outline);
  font: 700 13px/1 var(--mono);
  letter-spacing: 0.12em;
}

.price-grid {
  display: grid;
  grid-template-columns: 1fr 1.15fr;
  gap: 16px;
  align-items: start;
}

.price-grid article.free {
  margin-top: 26px;
}

.price-grid article.free li::before {
  content: '·';
  color: var(--muted);
  font-size: 22px;
  line-height: 0.9;
}

.price-grid ul {
  list-style: none;
  margin: 16px 0 0;
  padding: 0;
  color: var(--secondary);
  font-size: 14px;
  line-height: 1.7;
}

.price-grid li {
  position: relative;
  padding-left: 24px;
  margin-bottom: 8px;
}

.price-grid li::before {
  content: '✓';
  position: absolute;
  left: 0;
  top: 0;
  color: var(--accent-outline);
  font-weight: 700;
}

.price-grid article.pro {
  position: relative;
  padding: 26px 24px;
  background:
    radial-gradient(420px 260px at 90% -10%, rgba(208, 100, 50, 0.28), transparent 65%),
    linear-gradient(160deg, rgba(208, 100, 50, 0.18), rgba(42, 33, 30, 0.95));
  border-color: rgba(226, 138, 96, 0.5);
  box-shadow:
    0 18px 44px rgba(208, 100, 50, 0.16),
    inset 0 1px 0 rgba(255, 244, 238, 0.08);
}

.pro-badge {
  position: absolute;
  top: -12px;
  right: 22px;
  padding: 5px 13px;
  border-radius: 999px;
  background: linear-gradient(180deg, #d96f3a, var(--accent));
  color: var(--accent-fg);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.02em;
  box-shadow: 0 6px 16px var(--accent-glow);
}

.pro-main {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 22px;
  align-items: center;
}

.paywall-shot {
  width: 168px;
  max-width: none;
  justify-self: end;
  border-radius: 18px;
  border: 1px solid rgba(255, 244, 238, 0.14);
  box-shadow: 0 16px 36px rgba(0, 0, 0, 0.4);
  transform: rotate(2.5deg);
}

@media (max-width: 900px) {
  .hero {
    grid-template-columns: 1fr;
    gap: 36px;
    padding: 28px 0 64px;
  }

  .hero-media {
    order: -1;
  }

  .hero-media::before {
    inset: 4% 10%;
  }

  .steps {
    gap: 48px;
  }

  .steps article {
    grid-template-columns: 1fr;
    gap: 22px;
  }

  .steps article:nth-child(even) .phone {
    order: 0;
  }

  .steps .phone {
    width: min(100%, 240px);
  }

  .feature-grid,
  .price-grid {
    grid-template-columns: 1fr;
  }

  .price-grid article.free {
    margin-top: 0;
  }

  .pro-main {
    grid-template-columns: 1fr;
  }

  .paywall-shot {
    width: 200px;
    justify-self: center;
    transform: none;
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
