<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { APP_STORE_URL } from '../config'
import {
  LOCALES,
  getDictionary,
  homePath,
  privacyPath,
  type Locale,
} from '../i18n'

const route = useRoute()
const router = useRouter()

const locale = computed(() => (route.meta.locale as Locale) ?? 'zh-Hans')
const copy = computed(() => getDictionary(locale.value).landing)
const storeReady = computed(() => Boolean(APP_STORE_URL))

function switchLocale(next: Locale) {
  const isPrivacy = String(route.name ?? '').startsWith('privacy')
  router.push(isPrivacy ? privacyPath(next) : homePath(next))
}
</script>

<template>
  <div class="header-wrap">
    <header class="header shell">
      <RouterLink class="brand" :to="homePath(locale)">
        <img class="brand-mark" src="/app-icon.png" alt="" width="36" height="36" />
        <span>{{ copy.brand }}</span>
      </RouterLink>

      <div class="actions">
        <label class="lang">
          <span class="visually-hidden">{{ copy.langLabel }}</span>
          <select
            :value="locale"
            :aria-label="copy.langLabel"
            @change="switchLocale(($event.target as HTMLSelectElement).value as Locale)"
          >
            <option v-for="code in LOCALES" :key="code" :value="code">
              {{ copy.langNames[code] }}
            </option>
          </select>
        </label>

        <a
          class="btn btn-primary header-cta"
          :href="storeReady ? APP_STORE_URL : '#download'"
          :aria-disabled="!storeReady"
          :class="{ 'is-disabled': !storeReady }"
        >
          {{ storeReady ? copy.navDownload : copy.comingSoon }}
        </a>
      </div>
    </header>
  </div>
</template>

<style scoped>
.header-wrap {
  position: sticky;
  top: 0;
  z-index: 20;
  background: rgba(28, 22, 20, 0.78);
  backdrop-filter: blur(16px) saturate(1.4);
  -webkit-backdrop-filter: blur(16px) saturate(1.4);
  border-bottom: 1px solid rgba(255, 244, 238, 0.07);
}

.header {
  height: 68px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font-weight: 750;
  font-size: 20px;
  letter-spacing: -0.03em;
  transition: opacity 0.15s ease;
}

.brand:hover {
  opacity: 0.85;
}

.brand-mark {
  border-radius: 10px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.28);
}

.actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.lang select {
  appearance: none;
  min-height: 40px;
  padding: 0 34px 0 12px;
  border-radius: 999px;
  border: 1px solid var(--divider);
  cursor: pointer;
  transition: border-color 0.15s ease;
  background:
    linear-gradient(45deg, transparent 50%, var(--secondary) 50%) calc(100% - 14px) calc(50% - 2px) / 6px 6px no-repeat,
    linear-gradient(135deg, var(--secondary) 50%, transparent 50%) calc(100% - 10px) calc(50% - 2px) / 6px 6px no-repeat,
    var(--surface);
  color: var(--text);
}

.lang select:hover {
  border-color: var(--accent-outline);
}

.header-cta {
  min-height: 40px;
  padding: 0 14px;
  font-size: 13px;
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

@media (max-width: 560px) {
  .header-cta {
    display: none;
  }
}
</style>
