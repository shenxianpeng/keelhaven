<script setup lang="ts">
// Hero CTA that upgrades itself: links to the GitHub releases page from the
// first paint, then swaps to a direct DMG download (with a version chip) once
// /latest.json resolves. The label never changes, so nothing flashes while
// the manifest loads.
import { useLatestRelease } from '../latest'

const props = defineProps<{
  label: string
  fallbackHref: string
  // Secondary styling for when it sits under a primary CTA (the hero's
  // command box). Defaults to the filled primary look used elsewhere.
  ghost?: boolean
}>()

const { dmgURL, version } = useLatestRelease()
const btnClass = ['kh-btn', props.ghost ? 'kh-btn-ghost' : 'kh-btn-primary']

// Google Analytics only records file downloads by extension, and .dmg is not
// on its list, so without this a download is invisible in the reports. The
// event uses GA's standard file_download name and parameters, which is what
// the property counts as a key event.
function trackDownload() {
  const gtag = (window as { gtag?: (...args: unknown[]) => void }).gtag
  gtag?.('event', 'file_download', {
    file_extension: 'dmg',
    file_name: dmgURL.value.split('/').pop(),
    link_url: new URL(dmgURL.value, location.href).href,
    link_text: props.label,
  })
}
</script>

<template>
  <!-- `download` keeps VitePress's SPA router from intercepting the click:
       .dmg is not in its known-extensions list, so without it the router
       rewrites the href to …dmg.html and lands on the 404 page. -->
  <a v-if="dmgURL" :class="btnClass" :href="dmgURL" download @click="trackDownload">
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
