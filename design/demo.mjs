#!/usr/bin/env node
// Renders the product demo: a silent half-minute that tells the landing
// page's story in motion — the headline, the three steps, the three promises,
// the install line.
//
//   cd design && npm install && npm run demo          # English
//   npm run demo -- --lang=zh                         # Chinese
//
// Writes build/demo.mp4 (for a post, where there is a player) and
// docs/assets/demo.gif (for the README, where there is not). The GIF is
// committed because the README shows it; the film is not, because nothing in
// the repository does — it is four megabytes a re-render would add to history
// for no reader. Chinese writes build/demo-zh.mp4 and build/demo-zh.gif.
//
// Needs Chromium (`npx playwright install chromium`), ffmpeg on the PATH, and
// site/node_modules, because step 2 is not a recording of anything:
// it is the website's own MenuBarDemo, lifted out of a fresh site build, so
// the video shows the same popover the hero does and cannot drift from it.
//
// Nothing here is filmed in real time. Every moving thing is a function of
// the clock, and the script sets the clock, takes a picture, and moves on —
// so two runs give the same frames, at any frame rate, on any machine.
//
// Steps 1 and 3 are the screenshots in docs/assets/screenshots/. When one is
// re-taken, re-run this: the video is only as current as they are. Chinese
// needs its own (wizard-zh.png, restore-zh.png) and the script stops rather
// than put an English window under a Chinese caption.
//
// The words are the landing page's own — headline, steps, promises and
// closing line from site/index.md and site/zh/index.md, which take them from
// design/README.md § Words. Change them there first, then here.

import { chromium } from 'playwright'
import sharp from 'sharp'
import { spawn, execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { C } from './icon.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..')
const ASSETS = join(ROOT, 'docs/assets')
const SHOTS = join(ASSETS, 'screenshots')
const SITE = join(ROOT, 'site')
// Gitignored, and where `make build` already puts things that are made.
const OUT = join(ROOT, 'build')
mkdirSync(OUT, { recursive: true })

const lang = process.argv.includes('--lang=zh') ? 'zh' : 'en'
const suffix = lang === 'zh' ? '-zh' : ''

const COPY = {
  en: {
    headline: 'Back up your Mac to storage <em>you&nbsp;own.</em>',
    proof: ['Free &amp; open source', 'No account', 'No telemetry'],
    steps: [
      ['1 · Make a plan', 'Folders, destination, schedule.'],
      ['2 · Let it run', 'A green dot means the last backup worked.'],
      ['3 · Restore any point in time', 'Into a new folder. Nothing is overwritten.'],
    ],
    promises: [
      ['Encrypted on your Mac', 'Only you hold the key.'],
      ['Stored where you choose', 'No Keelhaven server in the path.'],
      ['Quiet until it matters', 'It speaks up only when something needs you.'],
    ],
    closing: 'Set it up once. Then forget it.',
  },
  zh: {
    headline: '把 Mac 备份到<br>你自己的存储',
    proof: ['免费开源', '没有账号', '没有遥测'],
    steps: [
      ['1 · 建一个计划', '文件夹、目的地、时间表。'],
      ['2 · 让它自己跑', '绿点亮着，说明上次备份成功了。'],
      // Chinese has no spaces to break at, so a long caption says where it
      // may: the browser would otherwise cut 任意 in two to even the lines.
      ['<span class="nb">3 · 恢复任意</span><span class="nb">时间点</span>', '恢复到新文件夹，不覆盖任何文件。'],
    ],
    promises: [
      ['在 Mac 上加密', '钥匙只在你手里。'],
      ['存在你选的地方', '中间没有 Keelhaven 的服务器。'],
      ['有事才出声', '只在需要你的时候才提醒。'],
    ],
    closing: '设置一次，然后就可以忘了它。',
  },
}[lang]
const INSTALL = 'brew install --cask shenxianpeng/tap/keelhaven'

// The cut, in seconds. The popover's loop is 12 s and ends by resetting to
// idle; DEMO_FROM..DEMO_TO is the stretch from just before the pointer shows
// up to just before that reset, so the scene ends on a finished backup.
const DEMO_FROM = 0.9
const DEMO_TO = 10.8
const SCENES = [
  { id: 'title', len: 3.4 },
  { id: 'step1', len: 5.2 },
  { id: 'step2', len: DEMO_TO - DEMO_FROM + 0.6 },
  { id: 'step3', len: 5.2 },
  { id: 'promises', len: 5.4 },
  { id: 'end', len: 4.6 },
]
let clock = 0
for (const s of SCENES) {
  s.start = clock
  clock += s.len
}
const DURATION = clock
const FPS = 30
const W = 1920
const H = 1080

// --- inputs ----------------------------------------------------------------

const b64 = (p) => readFileSync(p).toString('base64')

// The window shots are the window and nothing else, so they go in whole and
// the frame drawn here rounds their corners — as design/site.mjs does for the
// website's step cards.
async function shot(name) {
  const file = join(SHOTS, `${name}${suffix}.png`)
  if (!existsSync(file)) {
    throw new Error(
      `No ${lang === 'zh' ? 'Chinese ' : ''}screenshot at ${file.replace(ROOT + '/', '')} — take it first; ` +
        'the demo will not show a window in one language under a caption in another.'
    )
  }
  const png = await sharp(file).png().toBuffer()
  return `data:image/png;base64,${png.toString('base64')}`
}

// The popover, as the website ships it. A build is two seconds and is the
// only way to be sure this is the markup the hero renders today.
function popover() {
  if (!existsSync(join(SITE, 'node_modules'))) {
    throw new Error('site/node_modules is missing — run `npm --prefix site install` first.')
  }
  execFileSync('npm', ['--prefix', SITE, 'run', 'build'], { stdio: 'ignore' })
  const html = readFileSync(join(SITE, '.vitepress/dist', lang === 'zh' ? 'zh/index.html' : 'index.html'), 'utf8')
  const start = html.indexOf('<div class="kh-demo"')
  if (start < 0) throw new Error('The built landing page has no .kh-demo — did MenuBarDemo.vue move?')
  // Walk the <div>s to find the one that closes it.
  const tag = /<(\/?)div\b[^>]*>/g
  tag.lastIndex = start
  let depth = 0
  for (let m; (m = tag.exec(html)); ) {
    depth += m[1] ? -1 : 1
    if (depth === 0) {
      return html
        .slice(start, tag.lastIndex)
        .replace(/src="[^"]*icon-128\.png"/, `src="data:image/png;base64,${b64(join(ASSETS, 'icon-128.png'))}"`)
    }
  }
  throw new Error('Could not find where .kh-demo ends in the built landing page.')
}

// landing.css carries every .kh-demo rule and the palette they read. Its two
// font URLs point at the site's own /fonts; here they become the same files
// from design/fonts, inlined.
const landingCSS = readFileSync(join(SITE, '.vitepress/theme/landing.css'), 'utf8')
  .replace(/url\('\/fonts\/(Newsreader-latin-400(?:-italic)?\.woff2)'\)/g, (_, f) =>
    `url(data:font/woff2;base64,${b64(join(HERE, 'fonts', f))})`
  )

const ICON = {
  lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  stack: '<rect x="4" y="5" width="16" height="6" rx="1.5"/><rect x="4" y="13" width="16" height="6" rx="1.5"/><path d="M8 8h.01M8 16h.01"/>',
  moon: '<path d="M20 15.5A8.5 8.5 0 1 1 8.5 4a6.8 6.8 0 0 0 11.5 11.5z"/>',
}
const icon = (name) =>
  `<svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="${C.foam}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${ICON[name]}</svg>`

// --- the page --------------------------------------------------------------

const step = (i, visual) => `
<section class="scene step" id="step${i + 1}">
  <div class="caption">
    <h2 class="serif">${COPY.steps[i][0]}</h2>
    <p>${COPY.steps[i][1]}</p>
  </div>
  <div class="visual">${visual}</div>
</section>`

const html = `<!doctype html><html lang="${lang === 'zh' ? 'zh-Hans' : 'en'}"><head><meta charset="utf-8"><style>
${landingCSS}
* { box-sizing: border-box; }
html, body { margin: 0; }
/* The night ground sits on its own element: landing.css paints the body
   paper wherever a .kh-landing is on the page, and the popover brings one. */
#stage {
  position: relative; width: ${W}px; height: ${H}px; overflow: hidden; color: ${C.mist};
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'PingFang SC', sans-serif;
  -webkit-font-smoothing: antialiased;
  background:
    radial-gradient(900px 700px at 82% 18%, rgba(255,187,82,.13), rgba(255,187,82,0) 62%),
    linear-gradient(180deg, ${C.deep} 0%, ${C.hull} 45%, ${C.abyss} 100%);
}
.serif { font-family: var(--kh-serif); font-weight: 400; letter-spacing: -.02em; }
.soft { color: rgba(234,242,251,.74); }
.nb { white-space: nowrap; }

/* --a is how far a scene has faded in, --p how far through it the clock is.
   Both are set from outside, once per frame. */
.scene {
  position: absolute; inset: 0; opacity: var(--a, 0);
  display: flex; align-items: center; justify-content: center;
}
.rise { transform: translateY(calc((1 - var(--a, 0)) * 18px)); }

#title, #end { flex-direction: column; text-align: center; gap: 34px; }
#title img, #end img { width: 168px; height: 168px; filter: drop-shadow(0 22px 44px rgba(0,0,0,.5)); }
#title h1 { margin: 0; font-size: 104px; line-height: 1.06; max-width: 1300px; }
.proof { display: flex; gap: 18px; font-size: 30px; }
.proof span + span::before { content: '·'; margin-right: 18px; opacity: .6; }

.step { gap: 110px; padding: 0 130px; justify-content: flex-start; }
.caption { width: 600px; flex: none; }
/* Balanced, so a caption that needs two lines gets two of similar length
   rather than one full line and a single word — or, in Chinese, a single
   character — left over on the next. */
.caption h2 { margin: 0 0 22px; font-size: 76px; line-height: 1.08; text-wrap: balance; }
.caption p { margin: 0; font-size: 36px; line-height: 1.4; color: rgba(234,242,251,.78); text-wrap: balance; }
.visual { flex: 1; display: flex; justify-content: center; }
.visual img {
  height: 800px; border-radius: 22px;
  box-shadow: 0 40px 90px rgba(2,8,16,.6), 0 0 0 1px rgba(234,242,251,.12);
  transform: scale(calc(1 + .035 * var(--p, 0)));
}
#step3 .visual img { height: 690px; }
/* The popover is drawn for a 560 px column; zoom re-lays it out larger, so
   its text stays text instead of becoming a stretched bitmap. .kh-landing is
   there for the selectors, not for the page chrome it also carries. */
.popover.kh-landing { zoom: 1.7; width: 560px; min-height: 0; background: none; color: inherit; }
.popover .kh-demo { min-height: 0; padding: 0 0 20px; }

#promises > div { display: flex; flex-direction: column; gap: 46px; }
.promise { display: flex; align-items: center; gap: 34px; opacity: var(--in, 0); transform: translateX(calc((1 - var(--in, 0)) * -24px)); }
.promise h3 { margin: 0 0 6px; font-size: 62px; line-height: 1.1; }
.promise p { margin: 0; font-size: 32px; color: rgba(234,242,251,.74); }

#end h2 { margin: 0; font-size: 88px; line-height: 1.08; }
.cmd {
  font-family: var(--kh-mono); font-size: 34px; padding: 22px 34px; border-radius: 16px;
  background: rgba(5,20,31,.55); border: 1px solid rgba(127,182,220,.35);
}
.cmd::before { content: '$ '; color: ${C.foam}; }
.url { font-size: 34px; color: ${C.foam}; }
</style></head><body><div id="stage">

<section class="scene" id="title">
  <img class="rise" src="data:image/png;base64,${b64(join(ASSETS, 'icon-512.png'))}" alt="">
  <h1 class="serif rise">${COPY.headline}</h1>
  <div class="proof soft rise">${COPY.proof.map((p) => `<span>${p}</span>`).join('')}</div>
</section>

${step(0, `<img src="${await shot('wizard')}" alt="">`)}
${step(1, `<div class="popover kh-landing">${popover()}</div>`)}
${step(2, `<img src="${await shot('restore')}" alt="">`)}

<section class="scene" id="promises"><div>
  ${COPY.promises
    .map(
      ([title, line], i) => `
  <div class="promise" data-i="${i}">${icon(['lock', 'stack', 'moon'][i])}
    <div><h3 class="serif">${title}</h3><p>${line}</p></div>
  </div>`
    )
    .join('')}
</div></section>

<section class="scene" id="end">
  <img class="rise" src="data:image/png;base64,${b64(join(ASSETS, 'icon-512.png'))}" alt="">
  <h2 class="serif rise">${COPY.closing}</h2>
  <div class="cmd rise">${INSTALL}</div>
  <div class="url rise">keelhaven.app</div>
</section>

</div><script>
const SCENES = ${JSON.stringify(SCENES)}
const FADE = 0.45
const clamp = (x) => Math.min(1, Math.max(0, x))
// Ease out, so things arrive and settle rather than slide at one speed.
const ease = (x) => 1 - Math.pow(1 - clamp(x), 3)

window.seek = (t) => {
  for (const s of SCENES) {
    const el = document.getElementById(s.id)
    const local = t - s.start
    const last = s === SCENES[SCENES.length - 1]
    const a = Math.min(ease(local / FADE), last ? 1 : ease((s.len - local) / FADE))
    el.style.setProperty('--a', local < 0 || local > s.len ? 0 : a)
    el.style.setProperty('--p', clamp(local / s.len))
    if (s.id === 'promises') {
      el.querySelectorAll('.promise').forEach((p) => {
        p.style.setProperty('--in', ease((local - 0.25 - 0.55 * p.dataset.i) / 0.6))
      })
    }
  }
  // The popover runs on CSS animations. Paused and set by hand, they show
  // the frame for this instant instead of whatever the wall clock says.
  const step2 = SCENES.find((s) => s.id === 'step2')
  const ms = (${DEMO_FROM} + Math.min(Math.max(0, t - step2.start), ${DEMO_TO - DEMO_FROM})) * 1000
  for (const anim of document.getAnimations()) {
    anim.pause()
    anim.currentTime = ms
  }
}
</script>
</body></html>`

// --- frames → ffmpeg -------------------------------------------------------

const run = (args, stdin) =>
  new Promise((resolve, reject) => {
    const p = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args], {
      stdio: [stdin ? 'pipe' : 'ignore', 'inherit', 'inherit'],
    })
    p.on('error', () => reject(new Error('ffmpeg is not on the PATH — brew install ffmpeg')))
    p.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited with ${code}`))))
    if (stdin) stdin(p.stdin)
  })

const mp4 = join(OUT, `demo${suffix}.mp4`)
const gif = lang === 'en' ? join(ASSETS, 'demo.gif') : join(OUT, 'demo-zh.gif')

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 })
await page.setContent(html, { waitUntil: 'load' })
await page.evaluate(() => document.fonts.ready)

const frames = Math.round(DURATION * FPS)
let feed
const encoding = run(
  // yuv420p and an even frame size: what every player and every upload form
  // accepts. +faststart puts the index first so it starts before it finishes
  // downloading.
  ['-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4],
  (stdin) => (feed = stdin)
)
for (let f = 0; f < frames; f++) {
  await page.evaluate((t) => window.seek(t), f / FPS)
  const png = await page.screenshot({ type: 'png' })
  if (!feed.write(png)) await new Promise((r) => feed.once('drain', r))
  if (f % FPS === 0) process.stdout.write(`\r· frame ${f}/${frames}`)
}
feed.end()
await encoding
await browser.close()
process.stdout.write('\r')

// The README copy. A GIF has 256 colours and no player, so it is smaller and
// slower than the film: 800 px, 12 frames a second, one palette worked out
// from the whole cut so the night gradient does not band.
await run(['-i', mp4, '-filter_complex',
  'fps=12,scale=800:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle',
  gif])

const mb = (p) => (statSync(p).size / 1e6).toFixed(1)
console.log(`· ${mp4.replace(ROOT + '/', '')} — ${W}×${H}, ${DURATION.toFixed(1)} s, ${mb(mp4)} MB`)
console.log(`· ${gif.replace(ROOT + '/', '')} — 800 px wide, ${mb(gif)} MB`)
console.log(`\nOpen it: ${pathToFileURL(mp4).href}`)
