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
    </div>
  </div>
</template>

<style scoped>
.phone {
  width: min(100%, 300px);
  margin: 0 auto;
  filter: drop-shadow(0 28px 50px rgba(0, 0, 0, 0.45));
}

.bezel {
  border-radius: 36px;
  padding: 10px;
  background: linear-gradient(160deg, #3a2c27, #1c1614 55%, #2a211e);
  border: 1px solid rgba(255, 244, 238, 0.12);
}

.bezel img {
  width: 100%;
  border-radius: 28px;
  background: #000;
}
</style>
