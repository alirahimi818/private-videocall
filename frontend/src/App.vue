<script setup>
import { watchEffect } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();

watchEffect(() => {
  const locale = route.meta.locale ?? 'en';
  document.documentElement.lang = locale;
  document.documentElement.dir = locale === 'fa' ? 'rtl' : 'ltr';
});
</script>

<template>
  <router-view />
</template>
