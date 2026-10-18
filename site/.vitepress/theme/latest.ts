// Shared release lookup for every download CTA on the landing page.
//
// /latest.json is written next to the mirrored DMG by website.yml on each
// release. Consumers render a link to the GitHub releases page immediately —
// so no placeholder copy ever flashes — and swap to the direct DMG download
// once the manifest turns out to exist. The fetch happens once per page load,
// however many CTAs are on it.
import { ref } from 'vue'

const dmgURL = ref('')
const version = ref('')
let requested = false

export function useLatestRelease() {
  if (!requested && typeof window !== 'undefined') {
    requested = true
    fetch('/latest.json')
      .then(async (res) => {
        if (!res.ok) return
        const latest = await res.json()
        if (typeof latest.dmgURL === 'string' && latest.dmgURL) {
          dmgURL.value = latest.dmgURL
          version.value = typeof latest.version === 'string' ? latest.version : ''
        }
      })
      .catch(() => {
        // Offline or a malformed manifest — the releases-page link stays up.
      })
  }
  return { dmgURL, version }
}

// Google Analytics only records file downloads by extension, and .dmg is not
// on its list, so without this a download is invisible in the reports. Every
// DMG link calls it — the hero, the closing CTA and the nav — so they all
// count the same way. The event uses GA's standard file_download name and
// parameters, which is what the property counts as a key event; link_text
// names which link it was ("hero", "footer", "nav") rather than its label,
// which the hero and the closing CTA share.
export function trackDownload(source: string) {
  if (!dmgURL.value) return
  const gtag = (window as { gtag?: (...args: unknown[]) => void }).gtag
  gtag?.('event', 'file_download', {
    file_extension: 'dmg',
    file_name: dmgURL.value.split('/').pop(),
    link_url: new URL(dmgURL.value, location.href).href,
    link_text: source,
  })
}
