// Shared release lookup for every download CTA on the landing page.
//
// /latest.json is written next to the mirrored DMG by website.yml on each
// release. Consumers render a link to the GitHub releases page immediately —
// so no placeholder copy ever flashes — and swap to the direct DMG download
// once the manifest turns out to exist. The fetch happens once per page load,
// however many CTAs are on it.
//
// The download link goes through dl.keelhaven.app (workers/dl), which counts
// it where an ad blocker cannot hide it and redirects to that same mirrored
// file. Only the file name is taken from latest.json: its dmgURL keeps naming
// the mirror, because the in-app update prompt and install.sh read it too. The
// link says it came from the site, and from which page — browsers send another
// subdomain only the origin, so the referrer alone can't tell / from /zh/. A
// file name the counter would not recognise gets the mirror's own URL, so a
// renamed DMG is a download that goes uncounted, never a broken button.
import { computed, ref } from 'vue'
import { useRoute } from 'vitepress'

const COUNTER = 'https://dl.keelhaven.app'
const COUNTED_FILE = /^Keelhaven-\d+\.\d+\.\d+\.dmg$/

const mirrorURL = ref('')
const version = ref('')
let requested = false

export function useLatestRelease() {
  const route = useRoute()
  if (!requested && typeof window !== 'undefined') {
    requested = true
    fetch('/latest.json')
      .then(async (res) => {
        if (!res.ok) return
        const latest = await res.json()
        if (typeof latest.dmgURL === 'string' && latest.dmgURL) {
          mirrorURL.value = latest.dmgURL
          version.value = typeof latest.version === 'string' ? latest.version : ''
        }
      })
      .catch(() => {
        // Offline or a malformed manifest — the releases-page link stays up.
      })
  }
  const dmgURL = computed(() => {
    const file = mirrorURL.value.split('/').pop() ?? ''
    return COUNTED_FILE.test(file)
      ? `${COUNTER}/${file}?src=site&page=${route.path}`
      : mirrorURL.value
  })
  return { dmgURL, version }
}

// Google Analytics only records file downloads by extension, and .dmg is not
// on its list, so without this a download is invisible in the reports. Every
// DMG link calls it — the hero, the closing CTA and the nav — so they all
// count the same way. The event uses GA's standard file_download name and
// parameters, which is what the property counts as a key event; link_text
// names which link it was ("hero", "footer", "nav") rather than its label,
// which the hero and the closing CTA share. link_url stays the mirror's
// address, as it was before the counter, so the reports don't split in two.
export function trackDownload(source: string) {
  if (!mirrorURL.value) return
  const gtag = (window as { gtag?: (...args: unknown[]) => void }).gtag
  gtag?.('event', 'file_download', {
    file_extension: 'dmg',
    file_name: mirrorURL.value.split('/').pop(),
    link_url: new URL(mirrorURL.value, location.href).href,
    link_text: source,
  })
}
