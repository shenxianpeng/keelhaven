// Extends the default theme with the landing-page components used by
// site/index.md. Standalone pages (/licenses, /privacy) are untouched —
// every landing style in landing.css is scoped under .kh-landing.
import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import LandingNav from './components/LandingNav.vue'
import LandingSection from './components/LandingSection.vue'
import LandingFooter from './components/LandingFooter.vue'
import MenuBarDemo from './components/MenuBarDemo.vue'
import FaqItem from './components/FaqItem.vue'
import FaqMore from './components/FaqMore.vue'
import FlowDiagram from './components/FlowDiagram.vue'
import VoiceCard from './components/VoiceCard.vue'
import DownloadButton from './components/DownloadButton.vue'
import CommandBlock from './components/CommandBlock.vue'
import './landing.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('LandingNav', LandingNav)
    app.component('LandingSection', LandingSection)
    app.component('LandingFooter', LandingFooter)
    app.component('MenuBarDemo', MenuBarDemo)
    app.component('FaqItem', FaqItem)
    app.component('FaqMore', FaqMore)
    app.component('FlowDiagram', FlowDiagram)
    app.component('VoiceCard', VoiceCard)
    app.component('DownloadButton', DownloadButton)
    app.component('CommandBlock', CommandBlock)
  },
} satisfies Theme
