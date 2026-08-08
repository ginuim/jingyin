<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { SUPPORT_URL } from '../config'
import { getDictionary, homePath, privacyPath, type Locale } from '../i18n'

const route = useRoute()
const locale = computed(() => (route.meta.locale as Locale) ?? 'zh-Hans')
const copy = computed(() => getDictionary(locale.value).landing)
</script>

<template>
  <footer class="footer shell">
    <RouterLink class="brand" :to="homePath(locale)">
      <img src="/app-icon.png" alt="" width="28" height="28" />
      <span>{{ copy.brand }}</span>
    </RouterLink>
    <p>{{ copy.footerTagline }}</p>
    <nav class="links" :aria-label="copy.footerHome">
      <RouterLink :to="homePath(locale)">{{ copy.footerHome }}</RouterLink>
      <RouterLink :to="privacyPath(locale)">{{ copy.footerPrivacy }}</RouterLink>
      <a :href="SUPPORT_URL" rel="noopener noreferrer">reaidea.com</a>
    </nav>
  </footer>
</template>

<style scoped>
.footer {
  min-height: 96px;
  margin-top: 40px;
  padding: 28px 0 40px;
  border-top: 1px solid var(--divider);
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 14px 22px;
  color: var(--muted);
  font-size: 13px;
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--text);
  font-weight: 700;
}

.brand img {
  border-radius: 8px;
}

.footer p {
  margin: 0;
  flex: 1;
  min-width: 160px;
}

.links {
  display: flex;
  gap: 16px;
  margin-left: auto;
}

.links a {
  transition: color 0.15s ease;
}

.links a:hover {
  color: var(--accent-outline);
}
</style>
