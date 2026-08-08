<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import SiteFooter from '../components/SiteFooter.vue'
import SiteHeader from '../components/SiteHeader.vue'
import { getDictionary, homePath, type Locale } from '../i18n'

const route = useRoute()
const locale = computed(() => (route.meta.locale as Locale) ?? 'zh-Hans')
const privacy = computed(() => getDictionary(locale.value).privacy)
</script>

<template>
  <div class="page">
    <SiteHeader />

    <main class="shell policy">
      <RouterLink class="back" :to="homePath(locale)">← {{ privacy.backHome }}</RouterLink>
      <div class="eyebrow">{{ privacy.kicker }}</div>
      <h1>{{ privacy.title }}</h1>
      <p class="lead">{{ privacy.lead }}</p>
      <p class="updated">{{ privacy.updated }}</p>

      <aside class="summary">
        <strong>{{ privacy.summaryTitle }}</strong>
        <p>{{ privacy.summaryBody }}</p>
      </aside>

      <div class="sections">
        <section v-for="section in privacy.sections" :key="section.heading">
          <h2>{{ section.heading }}</h2>
          <p v-for="(paragraph, index) in section.paragraphs ?? []" :key="`p-${index}`">
            {{ paragraph }}
          </p>
          <ul v-if="section.bullets?.length">
            <li v-for="(bullet, index) in section.bullets" :key="`b-${index}`">
              {{ bullet }}
            </li>
          </ul>
        </section>
      </div>
    </main>

    <SiteFooter />
  </div>
</template>

<style scoped>
.policy {
  padding: 28px 0 20px;
  max-width: 760px;
}

.back {
  display: inline-block;
  margin-bottom: 22px;
  color: var(--secondary);
  font-size: 14px;
}

.back:hover {
  color: var(--accent-outline);
}

.policy h1 {
  margin: 14px 0 12px;
  font-size: clamp(36px, 6vw, 56px);
  letter-spacing: -0.05em;
  line-height: 1.05;
}

.lead,
.updated,
.summary p,
.sections p,
.sections li {
  color: var(--secondary);
  line-height: 1.75;
}

.lead {
  margin: 0;
  font-size: 16px;
}

.updated {
  margin: 14px 0 0;
  font: 600 12px/1.5 var(--mono);
}

.summary {
  margin: 34px 0;
  padding: 20px 22px;
  border-radius: 18px;
  background: var(--accent-soft);
  border: 1px solid rgba(226, 138, 96, 0.35);
}

.summary strong {
  display: block;
  margin-bottom: 8px;
  color: var(--text);
  font-size: 16px;
}

.summary p {
  margin: 0;
  font-size: 14px;
}

.sections {
  display: grid;
  gap: 28px;
}

.sections section {
  padding-top: 24px;
  border-top: 1px solid var(--divider);
}

.sections h2 {
  margin: 0 0 12px;
  font-size: 22px;
  letter-spacing: -0.03em;
}

.sections p {
  margin: 0 0 10px;
  font-size: 14px;
}

.sections ul {
  margin: 8px 0 0;
  padding-left: 20px;
}

.sections li {
  margin-bottom: 8px;
  font-size: 14px;
}
</style>
