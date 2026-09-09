// Keelhaven icon geometry — the single source of truth for every mark we ship.
//
// The drawing is a night harbour: a lighthouse standing at the water's edge,
// throwing one warm beam across a cold sea. Everything else (menu-bar template,
// wordmark lockup, favicons, social images) is derived from the functions here,
// so the silhouette can never drift between surfaces.
//
// Canvas is always 1024×1024. The icon body is an 832 px superellipse — macOS
// leaves the outer 96 px as breathing room, the same proportion Apple's own
// icon template uses.

export const C = {
  abyss: '#05141F',
  hull: '#0B2540',
  deep: '#0D3055',
  sea: '#14507E',
  tide: '#22608F',
  foam: '#7FB6DC',
  mist: '#EAF2FB',
  beam: '#FFDDA8',
  lantern: '#FFBB52',
  ember: '#EE8C2C',
}

/** Apple-style squircle (quintic superellipse) sampled as a polyline. */
export function squircle(cx, cy, side, n = 5, steps = 256) {
  const a = side / 2
  const pts = []
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * Math.PI * 2
    const ct = Math.cos(t)
    const st = Math.sin(t)
    const x = cx + a * Math.sign(ct) * Math.abs(ct) ** (2 / n)
    const y = cy + a * Math.sign(st) * Math.abs(st) ** (2 / n)
    pts.push(`${x.toFixed(2)},${y.toFixed(2)}`)
  }
  return `M${pts.join('L')}Z`
}

export const BODY = squircle(512, 498, 832)

// ---------------------------------------------------------------------------
// Lighthouse geometry, authored in its own space: x centred on 512, y running
// 192 (finial) → 812 (foot of the plinth). Nothing else in the file hard-codes
// those numbers — placement is done by `place()` below, which pins the foot to
// the waterline and scales around it.
// ---------------------------------------------------------------------------

const TOP = 192
const FOOT = 812
const LAMP_Y = 323

export const PARTS = {
  finial: 'M 503,186 a 9,9 0 0 1 18,0 v 12 h -18 Z',
  dome: 'M 434,264 C 436,222 466,190 512,190 C 558,190 588,222 590,264 Z',
  lantern: 'M 446,264 h 132 v 120 h -132 Z',
  gallery: 'M 420,384 h 184 a 16,16 0 0 1 16,16 v 8 a 16,16 0 0 1 -16,16 h -184 a 16,16 0 0 1 -16,-16 v -8 a 16,16 0 0 1 16,-16 Z',
  tower: 'M 440,424 h 144 C 588,548 600,672 616,768 h -208 C 424,672 436,548 440,424 Z',
  plinth: 'M 392,762 h 240 a 20,20 0 0 1 20,20 v 10 a 20,20 0 0 1 -20,20 h -240 a 20,20 0 0 1 -20,-20 v -10 a 20,20 0 0 1 20,-20 Z',
  // Clipped to the tower, so the band inherits the taper.
  band: 'M 400,574 h 224 v 82 h -224 Z',
}

/** Union silhouette, for single-colour marks. */
export const SILHOUETTE = [PARTS.finial, PARTS.dome, PARTS.lantern, PARTS.gallery, PARTS.tower, PARTS.plinth].join(' ')

/**
 * Where the lighthouse sits inside the 1024 canvas. The foot is pinned to
 * `footY` and the drawing scales around it, so the tower always meets the
 * waterline no matter which size variant is being rendered.
 */
export function place({ scale = 0.82, footY = 732 } = {}) {
  return {
    transform: `translate(512 ${footY}) scale(${scale}) translate(-512 ${-FOOT})`,
    lamp: { x: 512, y: footY - (FOOT - LAMP_Y) * scale },
    top: footY - (FOOT - TOP) * scale,
    horizon: footY - 16,
  }
}

/** Shared gradient/filter defs. `blur` tightens the soft passes for small art. */
export function defs({ blur = 1 } = {}) {
  return `
  <linearGradient id="kh-sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${C.tide}"/>
    <stop offset="0.44" stop-color="${C.deep}"/>
    <stop offset="1" stop-color="${C.hull}"/>
  </linearGradient>
  <radialGradient id="kh-vignette" cx="0.5" cy="0.4" r="0.78">
    <stop offset="0.5" stop-color="#000000" stop-opacity="0"/>
    <stop offset="1" stop-color="#000814" stop-opacity="0.5"/>
  </radialGradient>
  <radialGradient id="kh-halo" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#FFF8EA" stop-opacity="0.92"/>
    <stop offset="0.2" stop-color="${C.beam}" stop-opacity="0.46"/>
    <stop offset="0.55" stop-color="${C.lantern}" stop-opacity="0.13"/>
    <stop offset="1" stop-color="${C.lantern}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="kh-amber" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFF6E1"/>
    <stop offset="0.34" stop-color="${C.lantern}"/>
    <stop offset="1" stop-color="${C.ember}"/>
  </linearGradient>
  <linearGradient id="kh-stone" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/>
    <stop offset="1" stop-color="#DCE8F4"/>
  </linearGradient>
  <!-- Cylindrical shading: lit from the upper left, core shadow on the right. -->
  <linearGradient id="kh-cylinder" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#7E9DBE" stop-opacity="0.5"/>
    <stop offset="0.16" stop-color="#FFFFFF" stop-opacity="0.28"/>
    <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    <stop offset="0.78" stop-color="#4E7098" stop-opacity="0.32"/>
    <stop offset="1" stop-color="#2C4B6E" stop-opacity="0.58"/>
  </linearGradient>
  <linearGradient id="kh-water" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#08203A"/>
    <stop offset="1" stop-color="#030C16"/>
  </linearGradient>
  <linearGradient id="kh-rim" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
    <stop offset="0.26" stop-color="#FFFFFF" stop-opacity="0.06"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="kh-beamR" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="${C.beam}" stop-opacity="0.6"/>
    <stop offset="0.38" stop-color="${C.beam}" stop-opacity="0.18"/>
    <stop offset="0.82" stop-color="${C.beam}" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="kh-beamL" x1="1" y1="0" x2="0" y2="0">
    <stop offset="0" stop-color="${C.beam}" stop-opacity="0.6"/>
    <stop offset="0.38" stop-color="${C.beam}" stop-opacity="0.18"/>
    <stop offset="0.82" stop-color="${C.beam}" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="kh-reflect" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${C.lantern}" stop-opacity="0.55"/>
    <stop offset="1" stop-color="${C.lantern}" stop-opacity="0"/>
  </linearGradient>
  <filter id="kh-drop" x="-25%" y="-25%" width="150%" height="150%">
    <feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#03101E" flood-opacity="0.45"/>
  </filter>
  <filter id="kh-cast" x="-45%" y="-45%" width="190%" height="190%">
    <feDropShadow dx="0" dy="10" stdDeviation="${(14 * blur).toFixed(1)}" flood-color="#020C16" flood-opacity="0.5"/>
  </filter>
  <filter id="kh-soft" x="-70%" y="-70%" width="240%" height="240%">
    <feGaussianBlur stdDeviation="${(28 * blur).toFixed(1)}"/>
  </filter>
  <filter id="kh-soft-sm" x="-70%" y="-70%" width="240%" height="240%">
    <feGaussianBlur stdDeviation="${(11 * blur).toFixed(1)}"/>
  </filter>
  <clipPath id="kh-clip"><path d="${BODY}"/></clipPath>
  <clipPath id="kh-tower"><path d="${PARTS.tower}"/></clipPath>
  <clipPath id="kh-shade">
    <path d="${PARTS.dome} ${PARTS.lantern} ${PARTS.gallery} ${PARTS.tower} ${PARTS.plinth}"/>
  </clipPath>`
}

/** The lighthouse itself, in full colour, in its own coordinate space. */
export function lighthouse({ detail = true } = {}) {
  return `
  <g filter="url(#kh-cast)">
    <path d="${PARTS.finial}" fill="#E4EDF7"/>
    <path d="${PARTS.dome}" fill="url(#kh-stone)"/>
    <path d="${PARTS.lantern}" fill="url(#kh-amber)"/>
    ${detail ? `<g stroke="${C.ember}" stroke-width="7" opacity="0.3">
      <path d="M 480,268 v 112"/><path d="M 544,268 v 112"/>
    </g>` : ''}
    <path d="${PARTS.gallery}" fill="url(#kh-stone)"/>
    <path d="${PARTS.tower}" fill="url(#kh-stone)"/>
    <g clip-path="url(#kh-tower)"><path d="${PARTS.band}" fill="${C.deep}" opacity="0.92"/></g>
    <path d="${PARTS.plinth}" fill="url(#kh-stone)"/>
    <g clip-path="url(#kh-shade)">
      <rect x="380" y="180" width="264" height="640" fill="url(#kh-cylinder)"/>
      ${detail ? `<rect x="380" y="384" width="264" height="52" fill="${C.lantern}" opacity="0.16"/>` : ''}
    </g>
  </g>`
}

/** Beams and halo, in canvas space — needs the placed lamp position. */
export function light(lamp, { detail = true, spread = 190, reach = 62 } = {}) {
  const { x, y } = lamp
  return `
  <g ${detail ? 'filter="url(#kh-soft-sm)"' : ''}>
    <path d="M ${x + reach},${y} L 1140,${y - spread} L 1140,${y + spread} Z" fill="url(#kh-beamR)"/>
    <path d="M ${x - reach},${y} L -116,${y - spread} L -116,${y + spread} Z" fill="url(#kh-beamL)"/>
  </g>
  <circle cx="${x}" cy="${y}" r="290" fill="url(#kh-halo)"/>`
}

/** Sea, horizon and the lantern's reflection, in canvas space. */
export function water(horizon, lamp, { detail = true } = {}) {
  const y = horizon
  const edge = `M -8,${y} C 180,${y - 12} 348,${y + 9} 512,${y + 6} C 690,${y + 3} 852,${y - 14} 1032,${y + 1}`
  return `
  <path d="${edge} L 1032,1032 L -8,1032 Z" fill="url(#kh-water)"/>
  <path d="${edge}" stroke="${C.foam}" stroke-width="4" opacity="0.22" fill="none"/>
  <path d="M ${lamp.x - 36},${y} L ${lamp.x - 74},1032 L ${lamp.x + 74},1032 L ${lamp.x + 36},${y} Z"
        fill="url(#kh-reflect)" ${detail ? 'filter="url(#kh-soft-sm)"' : ''} opacity="0.8"/>
  ${detail ? `
  <g stroke="${C.beam}" stroke-linecap="round" opacity="0.55">
    <path d="M ${lamp.x - 52},${y + 46} h 104" stroke-width="11"/>
    <path d="M ${lamp.x - 36},${y + 96} h 72" stroke-width="10"/>
    <path d="M ${lamp.x - 66},${y + 148} h 132" stroke-width="9"/>
  </g>
  <g stroke="${C.foam}" stroke-width="11" stroke-linecap="round" opacity="0.15">
    <path d="M 178,${y + 62} h 104"/><path d="M 742,${y + 112} h 126"/><path d="M 246,${y + 166} h 80"/>
  </g>` : ''}`
}

/** Complete app icon. `detail:false` drops fine passes for 16–64 px art. */
export function appIcon({ detail = true } = {}) {
  const p = detail ? place() : place({ scale: 0.9, footY: 742 })
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>${defs({ blur: detail ? 1 : 0.55 })}</defs>
<g filter="url(#kh-drop)"><path d="${BODY}" fill="url(#kh-sky)"/></g>
<g clip-path="url(#kh-clip)">
  ${light(p.lamp, { detail })}
  ${water(p.horizon, p.lamp, { detail })}
  <g transform="${p.transform}">${lighthouse({ detail })}</g>
  <path d="${BODY}" fill="url(#kh-vignette)"/>
</g>
<path d="${BODY}" fill="none" stroke="url(#kh-rim)" stroke-width="4"/>
</svg>`
}

/** The lighthouse alone, no squircle — for lockups and light backgrounds. */
export function mark({ glow = true } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="620" viewBox="352 168 320 664">
<defs>${defs()}</defs>
${glow ? `<circle cx="512" cy="${LAMP_Y}" r="230" fill="url(#kh-halo)" opacity="0.9"/>` : ''}
${lighthouse({ detail: true })}
</svg>`
}

/**
 * Light rays for single-colour marks: three short strokes per side, radiating
 * from the lantern with a clear gap so they read as emitted light. Solid wedges
 * were tried first and read as ears — keep these thin and detached.
 */
export const RAYS = (() => {
  const cx = 512
  const cy = LAMP_Y
  const seg = []
  for (const base of [0, 180]) {
    for (const off of [-19, 0, 19]) {
      const a = ((base + off) * Math.PI) / 180
      const [x1, y1] = [cx + 136 * Math.cos(a), cy + 136 * Math.sin(a)]
      const [x2, y2] = [cx + 212 * Math.cos(a), cy + 212 * Math.sin(a)]
      seg.push(`M ${x1.toFixed(1)},${y1.toFixed(1)} L ${x2.toFixed(1)},${y2.toFixed(1)}`)
    }
  }
  return seg.join(' ')
})()

/**
 * Single-colour silhouette sized for the macOS menu bar. Drawn fresh rather
 * than scaled down: at 18 pt the dome, gallery and taper have to be exaggerated
 * or they vanish into mush.
 */
export function menuBarGlyph({ rays = false } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36">
  <g fill="currentColor">
    <path d="M 11.8,12.4 C 12.2,8.3 14.7,5.2 18,5.2 C 21.3,5.2 23.8,8.3 24.2,12.4 Z"/>
    <rect x="13.7" y="12.4" width="8.6" height="6.4"/>
    <rect x="10.2" y="18.8" width="15.6" height="3.1" rx="1.3"/>
    <path d="M 13.9,21.9 h 8.2 C 22.6,25.2 23.4,28.2 24.2,30.4 h -12.4 C 12.6,28.2 13.4,25.2 13.9,21.9 Z"/>
    <rect x="8.6" y="30.1" width="18.8" height="3.4" rx="1.5"/>
    ${rays ? '<path d="M 11.9,13.2 L 6.6,11.8 L 6.6,19.4 L 11.9,18 Z M 24.1,13.2 L 29.4,11.8 L 29.4,19.4 L 24.1,18 Z"/>' : ''}
  </g>
</svg>`
}

/** Flat one-colour mark for print, stickers, and anywhere gradients can't go. */
export function monoMark(color = 'currentColor', { rays = true } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="${rays ? '288 176 448 664' : '356 176 312 664'}">
  <path d="${SILHOUETTE}" fill="${color}"/>
  ${rays ? `<path d="${RAYS}" stroke="${color}" stroke-width="22" stroke-linecap="round" fill="none"/>` : ''}
</svg>`
}
