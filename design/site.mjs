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

// The captures include a strip of desktop wallpaper around each window;
// cropping just inside the window lets the page draw its own rounded frame
// (its border-radius covers the window's own corners). Pixel boxes are in the
// 2x capture, so re-measure them when a screenshot is re-taken.
const CROP = {
  wizard: { left: 18, top: 18, width: 1106, height: 1164 },
  'menu-bar': { left: 34, top: 10, width: 676, height: 936 },
  'menu-bar-zh': { left: 34, top: 10, width: 676, height: 936 },
  restore: { left: 17, top: 17, width: 1028, height: 844 },
}

// Captures are 2x retina; the step cards show them at most ~340 CSS px wide,
// so 720 px keeps them sharp on a retina screen at a fraction of the bytes.
for (const [name, box] of Object.entries(CROP)) {
  await sharp(join(SHOTS, `${name}.png`))
    .extract(box)
    .resize({ width: 720, withoutEnlargement: true })
    .webp({ quality: 88 })
    .toFile(join(SHOTS_OUT, `${name}.webp`))
}
console.log('· site/public/screenshots — 4 step screenshots (webp)')
