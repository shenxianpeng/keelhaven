<script setup lang="ts">
// Hero CTA that upgrades itself: links to the GitHub releases page from the
// first paint, then swaps to a direct DMG download (with a version chip) once
// /latest.json resolves. The label never changes, so nothing flashes while
// the manifest loads.
import { trackDownload, useLatestRelease } from '../latest'

const props = defineProps<{
  label: string
  fallbackHref: string
  // Where the button sits ("hero", "footer"), sent to Google Analytics as
  // the download's link_text — see trackDownload.
  source: string
  // Secondary styling for when it sits under a primary CTA (the hero's
  // command box). Defaults to the filled primary look used elsewhere.
  ghost?: boolean
}>()

const { dmgURL, version } = useLatestRelease()
const btnClass = ['kh-btn', props.ghost ? 'kh-btn-ghost' : 'kh-btn-primary']
</script>

<template>
  <!-- `download` keeps VitePress's SPA router from intercepting the click:
       .dmg is not in its known-extensions list, so without it the router
       rewrites the href to …dmg.html and lands on the 404 page. -->
  <a v-if="dmgURL" :class="btnClass" :href="dmgURL" download @click="trackDownload(source)">
    {{ label }}<span v-if="version" class="kh-btn-version">v{{ version }}</span>
  </a>
  <a
    v-else
    :class="btnClass"
    :href="fallbackHref"
    target="_blank"
    rel="noopener"
  >{{ label }}</a>
</template>
