<script setup lang="ts">
// Sticky pill nav for the landing page only. Items and CTA copy come from
// the page's frontmatter (fm.landing) so index.md and zh/index.md localize
// them without touching this component. An item is an in-page `anchor` or a
// `link` to another page; `fold: 1` or `fold: 2` lets it give way as the pill
// narrows (landing.css § responsive has the widths).
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useData, withBase } from 'vitepress'
import { trackDownload, useLatestRelease } from '../latest'

const { frontmatter, localeIndex } = useData()
const landing = computed(() => frontmatter.value.landing ?? {})

// The default navbar (which normally hosts VitePress's locale switcher) is
// hidden on the landing page, so the nav carries its own: a globe button
// opening a small menu, one row per language, the current one marked. Each
// label is that language's own name — the one string a reader lost in the
// wrong language can always recognize.
const langOpen = ref(false)
const languages = computed(() => [
  { text: 'English', href: withBase('/'), current: localeIndex.value !== 'zh' },
  { text: '简体中文', href: withBase('/zh/'), current: localeIndex.value === 'zh' },
])
const langLabel = computed(
  () => languages.value.find((l) => l.current)?.text ?? 'English'
)

const closeLang = (event: MouseEvent) => {
  if (!(event.target as Element | null)?.closest('.kh-nav-lang')) {
    langOpen.value = false
  }
}
const closeLangOnEscape = (event: KeyboardEvent) => {
  if (event.key === 'Escape') langOpen.value = false
}

const active = ref('')
const scrolled = ref(false)

// The CTA downloads a DMG, which is no use on an iPad, a phone in landscape
// or anything else that isn't a Mac, so there it points at the repository
// instead. VitePress's own `mac` class can't decide this: it matches iPhone
// and iPad too. An iPad asking for the desktop site says "Macintosh" like a
// Mac does; touch support is what tells the two apart. Set after mount so the
// server-rendered download link hydrates unchanged — the CTA is hidden until
// the reader scrolls, so the swap never shows.
const onMac = ref(true)

let observer: IntersectionObserver | undefined
const onScroll = () => {
  scrolled.value = window.scrollY > 420
}

onMounted(() => {
  onMac.value =
    /Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints < 2
  onScroll()
  window.addEventListener('scroll', onScroll, { passive: true })
  document.addEventListener('click', closeLang)
  document.addEventListener('keydown', closeLangOnEscape)
  observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) active.value = entry.target.id
      }
    },
    // A band around the upper-middle of the viewport decides the section.
    { rootMargin: '-40% 0px -55%' }
  )
  document
    .querySelectorAll('.kh-landing section[id]')
    .forEach((section) => observer!.observe(section))
})

onUnmounted(() => {
  observer?.disconnect()
  window.removeEventListener('scroll', onScroll)
  document.removeEventListener('click', closeLang)
  document.removeEventListener('keydown', closeLangOnEscape)
})

// Same self-upgrading download link as the hero's DownloadButton: the GitHub
// releases page until /latest.json resolves, the DMG itself afterwards.
const { dmgURL } = useLatestRelease()
const ctaHref = computed(
  () => dmgURL.value || `${landing.value.github}/releases/latest`
)
</script>

<template>
  <header class="kh-nav-wrap">
    <nav class="kh-nav" :class="{ 'is-scrolled': scrolled }">
      <a class="kh-nav-brand" :href="withBase('/')">
        <img :src="withBase('/icon-128.png')" alt="" width="26" height="26" />
        <span>Keelhaven</span>
      </a>
      <div class="kh-nav-links">
        <a
          v-for="item in landing.nav"
          :key="item.text"
          :href="item.anchor ? `#${item.anchor}` : withBase(item.link)"
          :class="[
            { active: item.anchor && active === item.anchor },
            item.fold && `kh-nav-fold-${item.fold}`,
          ]"
        >{{ item.text }}</a>
      </div>
      <div class="kh-nav-lang">
        <button
          type="button"
          :aria-label="localeIndex === 'zh' ? '选择语言' : 'Choose a language'"
          :aria-expanded="langOpen"
          aria-haspopup="menu"
          @click="langOpen = !langOpen"
        >
          <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6">
            <circle cx="12" cy="12" r="9" />
            <path d="M3 12h18M12 3c2.5 2.4 3.8 5.6 3.8 9S14.5 21 12 21.4 8.2 18.4 8.2 12 9.5 5.4 12 3Z" />
          </svg>
          <span class="kh-nav-lang-label">{{ langLabel }}</span>
          <svg viewBox="0 0 24 24" width="11" height="11" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
            <path d="m6 9 6 6 6-6" />
          </svg>
        </button>
        <div v-if="langOpen" class="kh-nav-lang-menu" role="menu">
          <a
            v-for="lang in languages"
            :key="lang.text"
            role="menuitem"
            :href="lang.href"
            :class="{ current: lang.current }"
            :aria-current="lang.current ? 'true' : undefined"
          >{{ lang.text }}</a>
        </div>
      </div>
      <!-- Always visible, unlike the scroll-gated CTA next to it. -->
      <a
        v-if="landing.github"
        class="kh-nav-github"
        :href="landing.github"
        target="_blank"
        rel="noopener"
        aria-label="Source on GitHub"
      >
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path
            fill="currentColor"
            d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0 0 24 12c0-6.63-5.37-12-12-12Z"
          />
        </svg>
      </a>
      <!-- `download` must be empty, not a boolean: its value is the suggested
           filename, so `download="true"` saves the DMG as a file named "true".
           Empty keeps the filename from the URL and still stops VitePress's
           SPA router from intercepting the click. -->
      <a
        v-if="onMac"
        class="kh-btn kh-btn-primary kh-nav-cta"
        :href="ctaHref"
        :download="dmgURL ? '' : undefined"
        @click="trackDownload('nav')"
      >
        {{ landing.cta }}
      </a>
      <a
        v-else
        class="kh-btn kh-btn-primary kh-nav-cta"
        :href="landing.github"
        target="_blank"
        rel="noopener"
      >
        {{ landing.ctaNotMac }}
      </a>
    </nav>
  </header>
</template>
