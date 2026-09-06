<script setup lang="ts">
defineProps<{
  text: string
}>()
</script>

<template>
  <div class="eyebrow">
    <svg class="eyebrow-mark" viewBox="0 0 18 2" width="18" height="2" aria-hidden="true">
      <line x1="0" y1="1" x2="18" y2="1" />
    </svg>
    <span>{{ text }}</span>
  </div>
</template>
