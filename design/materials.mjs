#!/usr/bin/env node
// Renders the typographic brand assets — README banner, the README's
// "where your files go" diagram, link-preview cards and the wordmark lockup —
// by laying them out in Chromium and screenshotting.
//
//   cd design && npm install && npm run materials
//
// Chromium rather than SVG-to-raster because these need real text layout.
// Both faces are vendored in design/fonts (SIL OFL 1.1) so the output is
// identical on any machine: Newsreader for headlines — the face the website
// self-hosts for its headings — and Inter for everything else (the site sets
// body text in the system font instead, which is SF Pro on a Mac).
//
// The words on these cards are the brand copy from design/README.md § Words.
// Change them there first, then here, then on the site and in the README.

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

const b64 = (p) => readFileSync(p).toString('base64')
const inter = b64(join(HERE, 'fonts/Inter-latin.woff2'))
const serif = b64(join(HERE, 'fonts/Newsreader-latin-400.woff2'))
const serifItalic = b64(join(HERE, 'fonts/Newsreader-latin-400-italic.woff2'))
const iconData = b64(join(ASSETS, 'icon-512.png'))
const menuShot = b64(join(ASSETS, 'screenshots/menu-bar.png'))

// design/README.md § Words — the one-liner, the headline, the three promises.
const TAGLINE = 'Privacy-first backups for your Mac, to storage you own.'
const PROMISES = ['Encrypted on your Mac', 'Stored where you choose', 'Quiet until it matters']

// Stroke icons, one per promise and one per destination — the same drawings
// the site's FlowDiagram.vue and hero strip use.
const ICON = {
  lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  stack: '<rect x="4" y="5" width="16" height="6" rx="1.5"/><rect x="4" y="13" width="16" height="6" rx="1.5"/><path d="M8 8h.01M8 16h.01"/>',
  moon: '<path d="M20 15.5A8.5 8.5 0 1 1 8.5 4a6.8 6.8 0 0 0 11.5 11.5z"/>',
  folder: '<path d="M3.5 7a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
  layers: '<path d="M12 4l8 4-8 4-8-4z"/><path d="M4 12l8 4 8-4"/><path d="M4 16l8 4 8-4"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  shield: '<path d="M12 3.5l7 2.5v5.5c0 4.3-2.9 7.6-7 9-4.1-1.4-7-4.7-7-9V6z"/><path d="M8.8 12.2l2.2 2.2 4.2-4.4"/>',
  drive: '<rect x="3.5" y="7" width="17" height="10" rx="2"/><path d="M7 12h.01M10 12h.01"/>',
  cloud: '<path d="M7 18a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.4 1.6A3.8 3.8 0 0 1 17 18z"/>',
  terminal: '<rect x="3.5" y="5" width="17" height="14" rx="2"/><path d="M7.5 10l2.5 2-2.5 2M12.5 14.5h4"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.5 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.5-3.5-8.5s1-6 3.5-8.5z"/>',
}
const icon = (name, size, color = 'currentColor') =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${ICON[name]}</svg>`

const css = `
@font-face { font-family: 'Inter'; src: url(data:font/woff2;base64,${inter}) format('woff2'); font-weight: 100 900; font-display: block; }
@font-face { font-family: 'Newsreader'; src: url(data:font/woff2;base64,${serif}) format('woff2'); font-weight: 400; font-display: block; }
@font-face { font-family: 'Newsreader'; src: url(data:font/woff2;base64,${serifItalic}) format('woff2'); font-weight: 400; font-style: italic; font-display: block; }
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { background: transparent; }
body {
  font-family: 'Inter', -apple-system, system-ui, sans-serif;
  font-feature-settings: 'cv11', 'ss01';
  -webkit-font-smoothing: antialiased;
}
.serif { font-family: 'Newsreader', Georgia, serif; font-weight: 400; }
.night {
  position: relative;
  overflow: hidden;
  color: ${C.mist};
  background:
    radial-gradient(var(--glow-size, 620px 480px) at var(--glow-at, 85% 20%), rgba(255,187,82,.15), rgba(255,187,82,0) 62%),
    linear-gradient(180deg, ${C.deep} 0%, ${C.hull} 45%, ${C.abyss} 100%);
}
.soft { color: rgba(234,242,251,.76); }
`
const page = (body, extra = '') =>
  `<!doctype html><html><head><meta charset="utf-8"><style>${css}${extra}</style></head><body>${body}</body></html>`

// ---------------------------------------------------------------------------
// README banner: the name and one-liner on the left, the three promises on
// the right — the same three the site's hero strip and the README table use.
// ---------------------------------------------------------------------------
const banner = page(`
<div class="night stage">
  <img class="icon" src="data:image/png;base64,${iconData}">
  <div class="name-col">
    <div class="serif name">Keelhaven</div>
    <div class="soft tag">Privacy-first backups for your Mac,<br>to storage you own.</div>
  </div>
  <div class="promises">
    ${PROMISES.map((p, i) => `<div class="promise">${icon(['lock', 'stack', 'moon'][i], 20, C.foam)}<span>${p}</span></div>`).join('')}
  </div>
</div>`, `
.stage { --glow-size: 520px 360px; --glow-at: 150px 190px; width: 1200px; height: 400px; border-radius: 20px;
  display: flex; align-items: center; gap: 56px; padding: 0 80px; }
.icon { width: 148px; height: 148px; filter: drop-shadow(0 16px 34px rgba(0,0,0,.5)); }
.name-col { flex: 1; display: flex; flex-direction: column; gap: 14px; }
.name { font-size: 78px; line-height: 1; letter-spacing: -.02em; }
.tag { font-size: 21px; line-height: 1.45; letter-spacing: -.01em; }
.promises { width: 290px; display: flex; flex-direction: column; font-size: 16px; font-weight: 500; }
.promise { display: flex; align-items: center; gap: 12px; padding: 14px 0; }
.promise + .promise { border-top: 1px solid rgba(234,242,251,.14); }
`)

// ---------------------------------------------------------------------------
// Link previews: the headline, with the menu bar panel beside it. og:image
// wants 1200×630; GitHub's social preview is 1280×640.
// ---------------------------------------------------------------------------
const preview = (w, h) => page(`
<div class="night stage">
  <div class="brand"><img src="data:image/png;base64,${iconData}"><span>Keelhaven</span></div>
  <h1 class="serif">Back up your Mac to storage <i>you&nbsp;own.</i></h1>
  <div class="foot">
    <div class="chips">
      <span>Encrypted on your Mac</span><span>Stored where you choose</span><span>Free &amp; open source</span>
    </div>
    <div class="url">keelhaven.app</div>
  </div>
  <div class="shot"><img src="data:image/png;base64,${menuShot}"></div>
</div>`, `
.stage { width: ${w}px; height: ${h}px; padding: 64px 72px; display: flex; flex-direction: column; gap: 28px; }
.brand { display: flex; align-items: center; gap: 14px; font-size: 24px; font-weight: 600; }
.brand img { width: 58px; height: 58px; }
h1 { width: 640px; font-size: 84px; line-height: .98; letter-spacing: -.025em; }
.foot { margin-top: auto; display: flex; flex-direction: column; gap: 18px; }
.chips { display: flex; gap: 10px; }
.chips span { padding: 8px 14px; border: 1px solid rgba(234,242,251,.2); border-radius: 999px; font-size: 16px; color: rgba(234,242,251,.86); }
.url { font-size: 17px; color: ${C.foam}; letter-spacing: .01em; }
/* The capture is 744×984 with wallpaper round the panel; at half size the
   panel sits 16px in and 4px down, so the frame crops to it. */
.shot { position: absolute; right: 72px; top: 96px; width: 340px; height: 470px; border-radius: 14px; overflow: hidden;
  transform: rotate(2deg); box-shadow: 0 40px 90px -24px rgba(0,0,0,.75), 0 0 0 1px rgba(234,242,251,.14); }
.shot img { display: block; width: 372px; height: 492px; margin: -4px 0 0 -16px; }
`)

// ---------------------------------------------------------------------------
// The README's copy of the site's FlowDiagram.vue — README can't run a Vue
// component, so it gets this picture of it. Paper ground with rounded corners
// so it reads on GitHub's light and dark themes alike.
// ---------------------------------------------------------------------------
const rows = (items, color) => items.map(([ic, text, note]) =>
  `<div class="row">${icon(ic, 20, color)}<div class="rowtext"><span>${text}</span>${note ? `<span class="note">${note}</span>` : ''}</div></div>`).join('')
const arrow = (label, dashed) => `
  <div class="arrow"><span>${label}</span>
    <svg width="90" height="14" viewBox="0 0 90 14" fill="none" stroke="${C.hull}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
      <path d="M2 7h84"${dashed ? ' stroke-dasharray="5 5"' : ''}/><path d="M80 2l6 5-6 5"/></svg></div>`
const flow = page(`
<div class="stage">
  <div class="lanes">
    <div class="card">
      <div class="label">Your Mac</div>
      <div class="serif title">The folders you pick</div>
      ${rows([['folder', 'Documents'], ['folder', 'Photos'], ['folder', 'Projects']])}
      <div class="more">…any folder you choose</div>
    </div>
    ${arrow('your files', false)}
    <div class="card app">
      <div class="app-head"><img src="data:image/png;base64,${iconData}"><div><div class="app-name">Keelhaven</div><div class="app-sub">in your menu bar</div></div></div>
      ${rows([
        ['lock', 'Encrypts with a password kept in your Keychain'],
        ['layers', 'Stores only what changed since last time'],
        ['clock', 'Runs hourly, daily or weekly, at your time'],
        ['shield', 'Verifies the repository, weekly by default'],
      ], C.foam)}
    </div>
    ${arrow('encrypted', true)}
    <div class="card">
      <div class="label">Storage you own</div>
      <div class="serif title">Wherever you trust</div>
      ${rows([
        ['drive', 'External or network drive'],
        ['cloud', 'S3-compatible bucket', 'AWS · B2 · Wasabi · R2 · MinIO'],
        ['terminal', 'SFTP to a server or NAS'],
        ['globe', 'restic REST server'],
      ])}
    </div>
  </div>
  <div class="not"><b>Not in the path:</b><s>a Keelhaven server</s><s>an account</s><s>telemetry</s></div>
</div>`, `
.stage { width: 1264px; height: 504px; padding: 32px; border-radius: 24px; background: #F6F3EC; color: ${C.hull};
  display: flex; flex-direction: column; gap: 24px; }
.lanes { display: flex; align-items: stretch; height: 340px; }
.card { width: 300px; padding: 28px; display: flex; flex-direction: column; gap: 14px; background: #FDFBF6; border: 1px solid #E3DCCD; border-radius: 18px; font-size: 15.5px; }
.card.app { width: 380px; gap: 16px; background: ${C.hull}; color: ${C.mist}; border: 0; border-radius: 20px; box-shadow: 0 24px 60px -24px rgba(5,20,31,.55); font-size: 15px; }
.label { font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: #5E6E80; }
.title { font-size: 28px; line-height: 1.1; margin-bottom: 4px; }
.row { display: flex; align-items: flex-start; gap: 12px; line-height: 1.4; }
.row svg { flex: none; }
.rowtext { display: flex; flex-direction: column; gap: 2px; }
.note { font-size: 13px; color: #5E6E80; }
.more { padding-left: 32px; font-size: 14.5px; color: #5E6E80; }
.app-head { display: flex; align-items: center; gap: 14px; margin-bottom: 6px; }
.app-head img { width: 50px; height: 50px; }
.app-name { font-size: 20px; font-weight: 600; }
.app-sub { font-size: 13.5px; color: ${C.foam}; }
.arrow { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; font-size: 12.5px; color: #5E6E80; }
.not { height: 56px; display: flex; align-items: center; justify-content: center; gap: 28px; border: 1px dashed #C9C0AD; border-radius: 14px; font-size: 15px; color: #3F5368; }
.not b { color: ${C.hull}; font-weight: 600; }
.not s { text-decoration-color: rgba(11,37,64,.5); }
`)

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
})

async function shoot(html, { w, h, scale = 2, out, transparent = false }) {
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale })
  await page.setContent(html, { waitUntil: 'load' })
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({ path: out, omitBackground: transparent })
  await page.close()
  console.log(`· ${out.replace(ROOT + '/', '')} — ${w}×${h}@${scale}x`)
}

// README art: wide and retina, so it stays crisp on the repo page. Rounded
// corners, so both are shot on a transparent ground.
await shoot(banner, { w: 1200, h: 400, out: join(ASSETS, 'banner.png'), transparent: true })
await shoot(flow, { w: 1264, h: 504, out: join(ASSETS, 'flow.png'), transparent: true })

await shoot(preview(1200, 630), { w: 1200, h: 630, scale: 1, out: join(ASSETS, 'og.png') })
// Copied rather than re-shot: an identical second screenshot would cost
// another Chromium page for a byte-identical result.
copyFileSync(join(ASSETS, 'og.png'), join(SITE, 'og.png'))
console.log('· site/public/og.png')
await shoot(preview(1280, 640), { w: 1280, h: 640, scale: 1, out: join(ASSETS, 'social-preview.png') })

await browser.close()

// The wordmark stays vector and stays on the system font stack: on a Mac that
// resolves to SF Pro, which is the right face next to a native app.
const wordmark = (fg, sub) => `<svg xmlns="http://www.w3.org/2000/svg" width="560" height="120" viewBox="0 0 560 120">
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
for (const [f, w, h] of [
  ['banner.png', 2400, 800], ['flow.png', 2528, 1008],
  ['og.png', 1200, 630], ['social-preview.png', 1280, 640],
]) {
  const m = await sharp(join(ASSETS, f)).metadata()
  if (m.width !== w || m.height !== h) throw new Error(`${f}: expected ${w}×${h}, got ${m.width}×${m.height}`)
}
console.log('\nDone.')
