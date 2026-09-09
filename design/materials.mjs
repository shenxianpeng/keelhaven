#!/usr/bin/env node
// Renders the typographic brand assets — README banner, link-preview cards and
// the wordmark lockup — by laying them out in Chromium and screenshotting.
//
//   cd design && npm install && npm run materials
//
// Chromium rather than SVG-to-raster because these need real text layout.
// Inter is vendored in design/fonts (SIL OFL 1.1) so the output is identical on
// any machine; on a Mac the site itself falls back to the system font instead.

import { chromium } from 'playwright'
import sharp from 'sharp'
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { C } from './icon.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..')
const ASSETS = join(ROOT, 'docs/assets')
// VitePress serves static files only from site/public/, so the og:image needs
// a copy there. See the note in build.mjs about why this is generated, not
// hand-copied.
const SITE = join(ROOT, 'site/public')
for (const d of [ASSETS, SITE]) mkdirSync(d, { recursive: true })

const font = readFileSync(join(HERE, 'fonts/Inter-latin.woff2')).toString('base64')
const iconData = readFileSync(join(ASSETS, 'icon-512.png')).toString('base64')

const TAGLINE = 'Privacy-first Mac backup to storage you own'

const css = `
@font-face {
  font-family: 'Inter';
  src: url(data:font/woff2;base64,${font}) format('woff2');
  font-weight: 100 900;
  font-display: block;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: 'Inter', -apple-system, system-ui, sans-serif;
  font-feature-settings: 'cv11', 'ss01';
  -webkit-font-smoothing: antialiased;
  color: ${C.mist};
}
.stage {
  position: relative;
  overflow: hidden;
  display: flex;
  background:
    radial-gradient(120% 90% at 50% 8%, rgba(255,187,82,.20) 0%, rgba(255,187,82,0) 55%),
    linear-gradient(180deg, ${C.deep} 0%, #07203A 52%, ${C.abyss} 100%);
}
/* The lantern's beam, echoed from the icon — kept faint and wide, so it reads
   as atmosphere rather than as a stripe across the card. */
.stage::before {
  content: '';
  position: absolute;
  inset: 0;
  background:
    linear-gradient(102deg, transparent 26%, rgba(255,221,168,.055) 50%, transparent 74%),
    linear-gradient(78deg, transparent 26%, rgba(255,221,168,.055) 50%, transparent 74%);
}
/* Waterline. */
.stage::after {
  content: '';
  position: absolute;
  left: 0; right: 0; bottom: 0;
  height: 12%;
  background: linear-gradient(180deg, rgba(4,18,31,0) 0%, rgba(3,12,22,.85) 40%, #03101B 100%);
  border-top: 1px solid rgba(127,182,220,.16);
}
.inner { position: relative; z-index: 2; margin: auto; text-align: center; }
.icon { display: block; margin: 0 auto; filter: drop-shadow(0 14px 34px rgba(0,0,0,.5)); }
h1 { font-weight: 640; letter-spacing: -.035em; line-height: 1; }
p.tag { color: rgba(234,242,251,.66); font-weight: 420; letter-spacing: -.012em; }
.chips { display: flex; justify-content: center; flex-wrap: nowrap; }
.chip {
  border: 1px solid rgba(234,242,251,.16);
  background: rgba(234,242,251,.05);
  border-radius: 999px;
  color: rgba(234,242,251,.7);
  font-weight: 500;
  white-space: nowrap;
}
.chip b { color: ${C.lantern}; font-weight: 600; }
`

const CHIPS = [
  'Built on <b>restic</b>',
  'Encrypted <b>on your Mac</b>',
  '<b>No subscription</b>',
  '<b>Zero telemetry</b>',
]

/** One card layout. Sizes are given outright — a single scale factor made the
 *  headline outrun the canvas on the taller cards. */
function card({ w, h, icon, title, tag, chip, chips = CHIPS }) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}
  .stage { width: ${w}px; height: ${h}px; }
  .inner { padding: 0 ${Math.round(w * 0.06)}px; }
  .icon { width: ${icon}px; height: ${icon}px; }
  h1 { font-size: ${title}px; margin-top: ${Math.round(title * 0.42)}px; }
  p.tag { font-size: ${tag}px; margin-top: ${Math.round(tag * 0.6)}px; }
  .chips { margin-top: ${Math.round(tag * 1.5)}px; gap: ${Math.round(chip * 0.6)}px; }
  .chip { font-size: ${chip}px; padding: ${Math.round(chip * 0.5)}px ${Math.round(chip * 1.05)}px; }
  </style></head><body>
  <div class="stage"><div class="inner">
    <img class="icon" src="data:image/png;base64,${iconData}">
    <h1>Keelhaven</h1>
    <p class="tag">${TAGLINE}</p>
    ${chips.length ? `<div class="chips">${chips.map(c => `<div class="chip">${c}</div>`).join('')}</div>` : ''}
  </div></div></body></html>`
}

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
})

async function shoot(html, { w, h, scale = 2, out }) {
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale })
  await page.setContent(html, { waitUntil: 'load' })
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({ path: out })
  await page.close()
  console.log(`· ${out.replace(ROOT + '/', '')} — ${w}×${h}@${scale}x`)
}

// README banner: wide and retina, so it stays crisp on the repo page.
await shoot(card({ w: 1200, h: 400, icon: 104, title: 54, tag: 21, chip: 14 }),
  { w: 1200, h: 400, out: join(ASSETS, 'banner.png') })

// Link previews. og:image wants 1200×630; GitHub's social preview is 1280×640.
await shoot(card({ w: 1200, h: 630, icon: 168, title: 82, tag: 30, chip: 19 }),
  { w: 1200, h: 630, scale: 1, out: join(ASSETS, 'og.png') })
// Copied rather than re-shot: an identical second screenshot would cost
// another Chromium page for a byte-identical result.
copyFileSync(join(ASSETS, 'og.png'), join(SITE, 'og.png'))
console.log('· site/public/og.png')
await shoot(card({ w: 1280, h: 640, icon: 172, title: 86, tag: 31, chip: 19 }),
  { w: 1280, h: 640, scale: 1, out: join(ASSETS, 'social-preview.png') })

await browser.close()

// The wordmark stays vector and stays on the system font stack: on a Mac that
// resolves to SF Pro, which is the right face next to a native app.
const wordmark = (fg, sub) => `<svg xmlns="http://www.w3.org/2000/svg" width="520" height="120" viewBox="0 0 520 120">
  <style>
    .n { font: 640 58px/1 -apple-system, 'SF Pro Display', 'Inter', system-ui, sans-serif; letter-spacing: -1.7px; }
    .s { font: 460 19px/1 -apple-system, 'SF Pro Text', 'Inter', system-ui, sans-serif; letter-spacing: -.1px; }
  </style>
  <text class="n" x="0" y="58" fill="${fg}">Keelhaven</text>
  <text class="s" x="2" y="92" fill="${sub}">${TAGLINE}</text>
</svg>`
writeFileSync(join(HERE, 'svg/wordmark-light.svg'), wordmark(C.hull, 'rgba(11,37,64,.62)'))
writeFileSync(join(HERE, 'svg/wordmark-dark.svg'), wordmark(C.mist, 'rgba(234,242,251,.62)'))
console.log('· design/svg/wordmark-{light,dark}.svg')

// Sanity check: every asset should be a real PNG of the size we asked for.
for (const [f, w, h] of [['banner.png', 2400, 800], ['og.png', 1200, 630], ['social-preview.png', 1280, 640]]) {
  const m = await sharp(join(ASSETS, f)).metadata()
  if (m.width !== w || m.height !== h) throw new Error(`${f}: expected ${w}×${h}, got ${m.width}×${m.height}`)
}
console.log('\nDone.')
