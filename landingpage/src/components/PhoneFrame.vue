<script setup lang="ts">
defineProps<{
  src: string
  alt: string
}>()
</script>

<template>
  <div class="phone">
    <div class="bezel">
      <img :src="src" :alt="alt" />
      <div class="island" aria-hidden="true"></div>
      <div class="glare" aria-hidden="true"></div>
    </div>
  </div>
</template>

<style scoped>
.phone {
  width: min(100%, 300px);
  margin: 0 auto;
  filter: drop-shadow(0 32px 56px rgba(0, 0, 0, 0.5));
}

.bezel {
  position: relative;
  border-radius: 40px;
  padding: 10px;
  background: linear-gradient(160deg, #45352f, #1c1614 55%, #2e2420);
  border: 1px solid rgba(255, 244, 238, 0.14);
  box-shadow: inset 0 1px 0 rgba(255, 244, 238, 0.1);
  overflow: hidden;
}

.bezel img {
  width: 100%;
  border-radius: 31px;
  background: #000;
}

.island {
  position: absolute;
  top: 22px;
  left: 50%;
  transform: translateX(-50%);
  width: 82px;
  height: 24px;
  border-radius: 999px;
  background: #000;
  box-shadow: 0 0 0 1px rgba(255, 244, 238, 0.05);
}

.glare {
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background: linear-gradient(
    115deg,
    rgba(255, 244, 238, 0.1) 0%,
    transparent 22%,
    transparent 78%,
    rgba(255, 244, 238, 0.04) 100%
  );
  pointer-events: none;
}
</style>
