// keelhaven-dl: counts the website's DMG downloads on the server, where an
// ad blocker cannot hide them, then sends the visitor on to the same file.
//
// It answers on https://dl.keelhaven.app — a Worker custom domain, the one
// proxied hostname in the zone; keelhaven.app itself stays DNS-only on GitHub
// Pages. See docs/WEBSITE.md § "Download counter".
//
// Every GET of /Keelhaven-x.y.z.dmg writes one data point to the
// keelhaven_downloads Analytics Engine dataset, and site/privacy.md lists
// exactly what it holds. No IP address, no user agent string, no query
// string beyond the two parameters read below:
//
//   blob1  source    ?src= when it is a short slug ("site" from the site's
//                    buttons, or a tag on a link posted somewhere), else
//                    "site" for a keelhaven.app referrer, "referral" for any
//                    other, "direct" for none
//   blob2  version   from the file name
//   blob3  country   Cloudflare's two-letter guess, "" when it has none
//   blob4  client    "browser", "curl", "bot" or "other", from the user agent
//   blob5  referrer  host only, "" when there was none
//   blob6  page      ?page=, else the referrer's path. Browsers send another
//                    subdomain only the origin, so the site says which of its
//                    pages the link was on itself (site/.vitepress/theme/latest.ts)
//   index1 version
//
// Anything else on this host is a 404.

const FILE = /^\/(Keelhaven-(\d+\.\d+\.\d+)\.dmg)$/
const SITE = 'https://keelhaven.app'
const RELEASES = 'https://github.com/shenxianpeng/keelhaven/releases/download'

const SLUG = /^[a-z0-9][a-z0-9._-]{0,31}$/
const PAGE = /^\/[A-Za-z0-9/._-]{0,100}$/
const BOT = /bot|crawl|spider|slurp|preview|headless|facebookexternalhit/i

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    const match = FILE.exec(url.pathname)
    if (!match) return new Response('Not found\n', { status: 404 })
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed\n', { status: 405, headers: { allow: 'GET, HEAD' } })
    }
    const [, file, version] = match

    // A HEAD is a link checker or someone testing the redirect, not a download.
    if (request.method === 'GET') count(request, url, env, version)

    // GitHub Pages only ever holds the newest DMG: each deploy replaces
    // gh-pages wholesale. The newest goes back to that mirror — the same file
    // the button served before this Worker existed, and no extra tick on the
    // release's download_count. An older one goes to its GitHub release. The
    // mirror's path is built here rather than read from latest.json's dmgURL,
    // so pointing that field at this Worker later cannot make a loop.
    const target = (await latestVersion()) === version
      ? `${SITE}/downloads/${file}`
      : `${RELEASES}/v${version}/${file}`
    // no-store: a cached redirect would be a download nobody counted.
    return new Response(null, { status: 302, headers: { location: target, 'cache-control': 'no-store' } })
  },
}

function count(request, url, env, version) {
  const client = clientOf(request.headers.get('user-agent') || '')

  let referrer = ''
  let referrerPath = ''
  try {
    const ref = new URL(request.headers.get('referer'))
    referrer = ref.hostname
    referrerPath = ref.pathname.slice(0, 200)
  } catch {
    // No referrer, or not a URL — both count as none.
  }

  const source = sourceOf(url.searchParams.get('src') || '', referrer)
  const page = url.searchParams.get('page') || ''

  try {
    env.DOWNLOADS.writeDataPoint({
      indexes: [version],
      blobs: [source, version, request.cf?.country || '', client, referrer, PAGE.test(page) ? page : referrerPath],
    })
  } catch {
    // Counting must never cost anyone the download.
  }
}

// The user agent, reduced to the one thing a count needs: what kind of client.
function clientOf(ua) {
  if (ua.startsWith('curl/')) return 'curl'
  if (BOT.test(ua)) return 'bot'
  if (ua.startsWith('Mozilla/')) return 'browser'
  return 'other'
}

// A ?src= slug wins: the site's own buttons and tagged links set one. Without
// it, the referrer's host is all there is to go on.
function sourceOf(src, referrer) {
  if (SLUG.test(src)) return src
  if (referrer === 'keelhaven.app' || referrer.endsWith('.keelhaven.app')) return 'site'
  if (referrer) return 'referral'
  return 'direct'
}

// The version latest.json names, or null when it cannot be read — which
// sends every version to its release, a slower but always-working path.
async function latestVersion() {
  try {
    const res = await fetch(`${SITE}/latest.json`, { cf: { cacheTtl: 300, cacheEverything: true } })
    if (!res.ok) return null
    const latest = await res.json()
    return typeof latest.version === 'string' ? latest.version : null
  } catch {
    return null
  }
}
