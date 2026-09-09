#!/usr/bin/env node
// Regenerates every Keelhaven brand asset from design/icon.mjs.
//
//   cd design && npm install && npm run build
//
// Outputs (all committed, because CI's macOS runner has no image toolchain):
//   design/svg/                          vector masters
//   Keelhaven/Assets.xcassets/           app icon + menu-bar template
//   docs/assets/                         README banner art, favicons, .icns
//   site/public/                         the subset VitePress serves
//
// site/public/ is a duplicate of a few docs/assets/ files on purpose: VitePress
// only serves static files from there. It is written here rather than copied by
// hand, because the hand-copied version of it went stale and unused.
//
// Nothing here is wired into xcodebuild — run it by hand when the mark changes.

import sharp from 'sharp'
import { mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { appIcon, mark, menuBarGlyph, monoMark, SILHOUETTE, RAYS, C } from './icon.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SVG_DIR = join(ROOT, 'design/svg')
const ICONSET = join(ROOT, 'Keelhaven/Assets.xcassets/AppIcon.appiconset')
const MENUSET = join(ROOT, 'Keelhaven/Assets.xcassets/MenuBarIcon.imageset')
const ASSETS = join(ROOT, 'docs/assets')
const SITE = join(ROOT, 'site/public')

for (const d of [SVG_DIR, ICONSET, MENUSET, ASSETS, SITE]) mkdirSync(d, { recursive: true })

const png = (svg, size, out, { fit = 'contain' } = {}) =>
  sharp(Buffer.from(svg), { density: 400 })
    .resize(size.w ?? size, size.h ?? size, { fit, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toFile(out)

// ---------------------------------------------------------------------------
// 1. Vector masters
// ---------------------------------------------------------------------------
const iconSvg = appIcon({ detail: true })
const iconSmallSvg = appIcon({ detail: false })

writeFileSync(join(SVG_DIR, 'icon.svg'), iconSvg)
writeFileSync(join(SVG_DIR, 'icon-small.svg'), iconSmallSvg)
writeFileSync(join(SVG_DIR, 'mark.svg'), mark())
writeFileSync(join(SVG_DIR, 'mark-flat.svg'), mark({ glow: false }))
writeFileSync(join(SVG_DIR, 'menubar.svg'), menuBarGlyph())
writeFileSync(join(SVG_DIR, 'mono.svg'), monoMark())
console.log('· design/svg — 6 vector masters')

// ---------------------------------------------------------------------------
// 2. AppIcon.appiconset
//
// 16/32/64 px use the simplified art: at those sizes the ripples and the
// blurred beam turn to noise, so those passes are dropped and the tower is
// scaled up slightly to hold its silhouette.
// ---------------------------------------------------------------------------
const APPICON = [
  ['16x16', '1x', 16], ['16x16', '2x', 32],
  ['32x32', '1x', 32], ['32x32', '2x', 64],
  ['128x128', '1x', 128], ['128x128', '2x', 256],
  ['256x256', '1x', 256], ['256x256', '2x', 512],
  ['512x512', '1x', 512], ['512x512', '2x', 1024],
]

const images = []
for (const [idiomSize, scale, px] of APPICON) {
  const file = `icon_${idiomSize}${scale === '2x' ? '@2x' : ''}.png`
  await png(px <= 64 ? iconSmallSvg : iconSvg, px, join(ICONSET, file))
  images.push({ size: idiomSize, idiom: 'mac', filename: file, scale })
}
writeFileSync(join(ICONSET, 'Contents.json'),
  JSON.stringify({ images, info: { version: 1, author: 'xcode' } }, null, 2) + '\n')
console.log(`· AppIcon.appiconset — ${images.length} sizes`)

// ---------------------------------------------------------------------------
// 3. Menu-bar template image (black + alpha; macOS recolours it per theme)
// ---------------------------------------------------------------------------
const glyphBlack = menuBarGlyph().replace(/currentColor/g, '#000000')
const menuImages = []
for (const [scale, px] of [['1x', 18], ['2x', 36], ['3x', 54]]) {
  const file = `menubar${scale === '1x' ? '' : `@${scale}`}.png`
  await png(glyphBlack, px, join(MENUSET, file))
  menuImages.push({ idiom: 'mac', filename: file, scale })
}
writeFileSync(join(MENUSET, 'Contents.json'), JSON.stringify({
  images: menuImages,
  info: { version: 1, author: 'xcode' },
  properties: { 'template-rendering-intent': 'template' },
}, null, 2) + '\n')

writeFileSync(join(ROOT, 'Keelhaven/Assets.xcassets/Contents.json'),
  JSON.stringify({ info: { version: 1, author: 'xcode' } }, null, 2) + '\n')
console.log('· MenuBarIcon.imageset — 3 scales (template)')

// ---------------------------------------------------------------------------
// 4. .icns — the standalone icon file, for anyone who wants it outside Xcode
// ---------------------------------------------------------------------------
const ICNS_TYPES = [
  ['icp4', 16], ['icp5', 32], ['icp6', 64],
  ['ic07', 128], ['ic08', 256], ['ic09', 512], ['ic10', 1024],
  ['ic11', 32], ['ic12', 64], ['ic13', 256], ['ic14', 512],
]
const chunks = []
for (const [type, px] of ICNS_TYPES) {
  const data = await sharp(Buffer.from(px <= 64 ? iconSmallSvg : iconSvg), { density: 400 })
    .resize(px, px).png({ compressionLevel: 9 }).toBuffer()
  const header = Buffer.alloc(8)
  header.write(type, 0, 'ascii')
  header.writeUInt32BE(data.length + 8, 4)
  chunks.push(header, data)
}
const payload = Buffer.concat(chunks)
const icnsHeader = Buffer.alloc(8)
icnsHeader.write('icns', 0, 'ascii')
icnsHeader.writeUInt32BE(payload.length + 8, 4)
writeFileSync(join(ASSETS, 'Keelhaven.icns'), Buffer.concat([icnsHeader, payload]))
console.log(`· Keelhaven.icns — ${ICNS_TYPES.length} variants`)

// ---------------------------------------------------------------------------
// 5. Web + README assets
// ---------------------------------------------------------------------------
for (const px of [1024, 512, 256, 128]) await png(iconSvg, px, join(ASSETS, `icon-${px}.png`))
await png(iconSmallSvg, 64, join(ASSETS, 'icon-64.png'))

// Favicons reuse the real icon art so a browser tab matches the Dock. Below
// 64 px the simplified variant is used, same rule as the app icon.
writeFileSync(join(ASSETS, 'favicon.svg'), iconSmallSvg)
for (const px of [16, 32, 180, 192, 512]) {
  await png(px <= 64 ? iconSmallSvg : iconSvg, px, join(ASSETS, `favicon-${px}.png`))
}

// The slice VitePress serves. Sizes match site/.vitepress/config.mts `head`:
// favicon.svg, a 32 px bitmap fallback, a 180 px apple-touch-icon, and the
// 128 px mark used as the nav logo. og.png is written by materials.mjs.
writeFileSync(join(SITE, 'favicon.svg'), iconSmallSvg)
await png(iconSmallSvg, 32, join(SITE, 'favicon-32.png'))
await png(iconSvg, 180, join(SITE, 'favicon-180.png'))
await png(iconSvg, 128, join(SITE, 'icon-128.png'))
console.log('· site/public — favicons + nav logo')

// Flat single-colour mark, for stickers/print/anywhere gradients can't go.
writeFileSync(join(SVG_DIR, 'mono-navy.svg'), monoMark(C.hull))
writeFileSync(join(SVG_DIR, 'mono-lantern.svg'), monoMark(C.lantern))
await png(monoMark(C.hull), 512, join(ASSETS, 'mark-mono.png'))
console.log('· docs/assets — icon exports + favicons')

rmSync(join(ASSETS, '.keep'), { force: true })
console.log('\nDone. Run `xcodegen generate` if the asset catalog is new.')
