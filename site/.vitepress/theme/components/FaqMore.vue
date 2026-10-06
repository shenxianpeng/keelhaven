<script setup lang="ts">
// The rest of the FAQ, folded behind one row so the landing page leads with
// the few questions a newcomer actually asks. Every answer stays on the page
// under #faq — the app and old release notes link to keelhaven.app/#faq, so
// the answers must not move to another URL.
defineProps<{ label: string }>()
</script>

<template>
  <details class="kh-faq-more">
    <summary>
      <span>{{ label }}</span>
      <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6" /></svg>
    </summary>
    <slot />
  </details>
</template>
