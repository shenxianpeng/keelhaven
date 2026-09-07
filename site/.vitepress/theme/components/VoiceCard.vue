<script setup lang="ts">
// One quote from a real post, linked back to where it was said. The link is
// the point: a testimonial you can click through to is evidence, one you
// can't is copy. Default slot: the quote, verbatim.
//
// `note` exists for the one case where "verbatim" needs a footnote — a quote
// said in the other language, rendered here in the reader's. The original is
// always one click away at `href`, and saying so is cheaper than pretending
// the translation is what they typed.
defineProps<{
  name: string
  handle: string
  source: string
  href: string
  note?: string
}>()
</script>

<template>
  <figure class="kh-voice">
    <blockquote class="kh-voice-quote"><slot /></blockquote>
    <figcaption class="kh-voice-who">
      <span class="kh-voice-name">{{ name }}</span>
      <span class="kh-voice-handle">{{ handle }}</span>
      <span v-if="note" class="kh-voice-note">{{ note }}</span>
      <a class="kh-voice-source" :href="href" target="_blank" rel="noopener">{{ source }} ↗</a>
    </figcaption>
  </figure>
</template>
