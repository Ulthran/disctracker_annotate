<script setup lang="ts">
import HeroIntro from './components/HeroIntro.vue';
</script>

<template>
  <main class="page">
    <HeroIntro />
  </main>
</template>

<style scoped>
.page {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  padding: 2rem;
  box-sizing: border-box;
}
</style>
