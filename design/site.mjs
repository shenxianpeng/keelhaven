#!/usr/bin/env node
// Copies the non-icon files the website serves into site/public/:
//
//   cd design && npm install && npm run site
//
//   site/public/fonts/        Newsreader, the headline face (SIL OFL 1.1),
//                             self-hosted so the site loads no font CDN — the
//                             only third party it loads stays the one
//                             site/privacy.md discloses.
//   site/public/screenshots/  the app screenshots the "How it works" steps
//                             show, resized from docs/assets/screenshots/.
//
// Same rule as build.mjs: VitePress only serves static files from
// site/public/, and a hand-copied duplicate goes stale, so it is written here.

import sharp from 'sharp'
import { copyFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..')
const SHOTS = join(ROOT, 'docs/assets/screenshots')
const FONTS_OUT = join(ROOT, 'site/public/fonts')
const SHOTS_OUT = join(ROOT, 'site/public/screenshots')
for (const d of [FONTS_OUT, SHOTS_OUT]) mkdirSync(d, { recursive: true })

for (const f of ['Newsreader-latin-400.woff2', 'Newsreader-latin-400-italic.woff2', 'LICENSE-Newsreader.txt']) {
  copyFileSync(join(HERE, 'fonts', f), join(FONTS_OUT, f))
}
console.log('· site/public/fonts — Newsreader 400 + italic, with its licence')

// The window shots (wizard, restore) are the window and nothing else, square
// to the edge, so they go in whole and the page draws the rounded frame. The
// menu bar panel was captured on a desktop, with a strip of wallpaper around
// it; its box cuts just inside the panel. Pixel boxes are in the 2x capture —
// re-measure them if the panel is ever re-taken.
const SHOTS_FOR_SITE = {
  wizard: null,
  'wizard-zh': null,
  'menu-bar': { left: 34, top: 10, width: 676, height: 936 },
  'menu-bar-zh': { left: 34, top: 10, width: 676, height: 936 },
  restore: null,
  'restore-zh': null,
}

// Captures are 2x retina; the step cards show them at most ~340 CSS px wide,
// so 720 px keeps them sharp on a retina screen at a fraction of the bytes.
for (const [name, box] of Object.entries(SHOTS_FOR_SITE)) {
  const shot = sharp(join(SHOTS, `${name}.png`))
  await (box ? shot.extract(box) : shot)
    .resize({ width: 720, withoutEnlargement: true })
    .webp({ quality: 88 })
    .toFile(join(SHOTS_OUT, `${name}.webp`))
}
console.log(`· site/public/screenshots — ${Object.keys(SHOTS_FOR_SITE).length} step screenshots (webp)`)
