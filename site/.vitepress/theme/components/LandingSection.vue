<script setup lang="ts">
// Numbered magazine section: eyebrow ("01 · Where your files go"), serif
// heading, body. Owns the anchor id the nav scrolls to and highlights.
// `band` paints the section's full-bleed background: `sand` for a quieter
// paper, `night` for the dark navy the hero and the close use. `split` sets
// the heading and a lead line on the left and the section's one card — its
// last child — on the right.
defineProps<{
  id: string
  eyebrow: string
  title: string
  band?: 'sand' | 'night'
  split?: boolean
}>()
</script>

<template>
  <div class="kh-band" :class="band ? `kh-band-${band}` : undefined">
    <section :id="id" class="kh-section" :class="{ 'kh-section-split': split }">
      <p class="kh-eyebrow">{{ eyebrow }}</p>
      <h2 class="kh-h2">{{ title }}</h2>
      <slot />
    </section>
  </div>
</template>
