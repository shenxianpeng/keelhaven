<script setup lang="ts">
// "Where your files go": your folders → Keelhaven → storage you own, and the
// things that are not in that path. Copy comes from frontmatter
// (landing.flow) so index.md and zh/index.md localize it; the icons are fixed
// here. The README carries a rendered picture of the same diagram, drawn by
// design/materials.mjs — change the two together.
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

const { frontmatter } = useData()
const flow = computed(() => frontmatter.value.landing?.flow ?? {})

const ICONS: Record<string, string> = {
  folder: '<path d="M3.5 7a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
  lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  layers: '<path d="M12 4l8 4-8 4-8-4z"/><path d="M4 12l8 4 8-4"/><path d="M4 16l8 4 8-4"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  shield: '<path d="M12 3.5l7 2.5v5.5c0 4.3-2.9 7.6-7 9-4.1-1.4-7-4.7-7-9V6z"/><path d="M8.8 12.2l2.2 2.2 4.2-4.4"/>',
  drive: '<rect x="3.5" y="7" width="17" height="10" rx="2"/><path d="M7 12h.01M10 12h.01"/>',
  cloud: '<path d="M7 18a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.4 1.6A3.8 3.8 0 0 1 17 18z"/>',
  terminal: '<rect x="3.5" y="5" width="17" height="14" rx="2"/><path d="M7.5 10l2.5 2-2.5 2M12.5 14.5h4"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.5 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.5-3.5-8.5s1-6 3.5-8.5z"/>',
}
// In the order each card's items are written in frontmatter.
const APP_ICONS = ['lock', 'layers', 'clock', 'shield']
const STORAGE_ICONS = ['drive', 'cloud', 'terminal', 'globe']
</script>

<template>
  <div class="kh-flow">
    <div class="kh-flow-lanes">
      <div class="kh-flow-card">
        <p class="kh-flow-label">{{ flow.mac?.label }}</p>
        <p class="kh-flow-title">{{ flow.mac?.title }}</p>
        <ul>
          <li v-for="item in flow.mac?.items" :key="item">
            <svg viewBox="0 0 24 24" aria-hidden="true" v-html="ICONS.folder" />
            <span>{{ item }}</span>
          </li>
        </ul>
        <p class="kh-flow-more">{{ flow.mac?.more }}</p>
      </div>

      <div class="kh-flow-arrow">
        <span>{{ flow.arrows?.[0] }}</span>
        <svg viewBox="0 0 90 14" aria-hidden="true"><path d="M2 7h84" /><path d="M80 2l6 5-6 5" /></svg>
      </div>

      <div class="kh-flow-card kh-flow-app">
        <div class="kh-flow-app-head">
          <img :src="withBase('/icon-128.png')" alt="" width="48" height="48" />
          <div>
            <p class="kh-flow-app-name">Keelhaven</p>
            <p class="kh-flow-app-sub">{{ flow.app?.sub }}</p>
          </div>
        </div>
        <ul>
          <li v-for="(item, i) in flow.app?.items" :key="item">
            <svg viewBox="0 0 24 24" aria-hidden="true" v-html="ICONS[APP_ICONS[i]]" />
            <span>{{ item }}</span>
          </li>
        </ul>
      </div>

      <div class="kh-flow-arrow is-encrypted">
        <span>{{ flow.arrows?.[1] }}</span>
        <svg viewBox="0 0 90 14" aria-hidden="true"><path d="M2 7h84" /><path d="M80 2l6 5-6 5" /></svg>
      </div>

      <div class="kh-flow-card">
        <p class="kh-flow-label">{{ flow.storage?.label }}</p>
        <p class="kh-flow-title">{{ flow.storage?.title }}</p>
        <ul>
          <li v-for="(item, i) in flow.storage?.items" :key="item.text">
            <svg viewBox="0 0 24 24" aria-hidden="true" v-html="ICONS[STORAGE_ICONS[i]]" />
            <span>{{ item.text }}<small v-if="item.note">{{ item.note }}</small></span>
          </li>
        </ul>
      </div>
    </div>

    <p class="kh-flow-not">
      <strong>{{ flow.notInPath?.label }}</strong>
      <s v-for="item in flow.notInPath?.items" :key="item">{{ item }}</s>
    </p>
  </div>
</template>
