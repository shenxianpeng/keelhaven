---
layout: page
navbar: false
footer: false

# All landing copy that components render lives here (not inside the
# components); zh/index.md mirrors this file section for section — when
# editing copy here, make the same change there (and vice versa).
landing:
  # The one place the support address is written. It is a Cloudflare Email
  # Routing alias on keelhaven.app that forwards to a real inbox, so it can be
  # re-pointed without touching the site.
  contact: support@keelhaven.app
  # The repository URL, read by the nav icon and the footer's github link.
  # The default-theme pages (/privacy, /licenses) carry it separately via
  # themeConfig.socialLinks in config.mts.
  github: https://github.com/shenxianpeng/keelhaven
  cta: Download
  nav:
    - { text: Features, anchor: features }
    - { text: Guide, anchor: guide }
    - { text: Pricing, anchor: pricing }
    - { text: Voices, anchor: voices }
    - { text: FAQ, anchor: faq }
  footer:
    tagline: Privacy-first backups for your Mac.
    versionNote: public beta
    copyright: © shenxianpeng.
    groups:
      - title: Support
        links:
          - { text: Email support, mailto: true }
          - { text: FAQ, anchor: faq }
          - { text: Follow on X, href: "https://x.com/xianpengshen" }
      - title: Product
        links:
          - { text: Features, anchor: features }
          - { text: Getting started, anchor: guide }
          - { text: Pricing, anchor: pricing }
          - { text: Source on GitHub, github: true }
      - title: Legal
        links:
          - { text: Privacy, link: /privacy }
          - { text: Licenses, link: /licenses }
---

<script setup>
import { computed } from 'vue'
import { useData } from 'vitepress'

const { frontmatter } = useData()
const releases = computed(
  () => `${frontmatter.value.landing.github}/releases/latest`
)
</script>

<!-- The download CTA is live: DownloadButton links to the GitHub releases
     page until /latest.json resolves, then swaps in the direct DMG link. -->

<div class="kh-landing">

<LandingNav />

<section id="top" class="kh-hero">
  <h1 class="kh-hero-title">Privacy-first backups for your&nbsp;Mac</h1>
  <p class="kh-hero-tagline">A quiet menu bar app that backs up the folders you care about — encrypted on your Mac, on your schedule, to storage you own.</p>
  <p class="kh-hero-facts">
    <span>macOS 14+</span>
    <span>Free &amp; open source</span>
    <span>No telemetry</span>
    <span>Restore from the menu bar</span>
  </p>
  <div class="kh-hero-actions">
    <CommandBlock
      command="brew install --cask shenxianpeng/tap/keelhaven"
      note="One command — installs and launches with no security prompt."
    />
    <p class="kh-hero-alt">
      <DownloadButton label="Download the .dmg" :fallback-href="releases" ghost />
      <a class="kh-btn kh-btn-ghost" href="#guide">Read the guide</a>
    </p>
  </div>
</section>

<LandingSection id="tour" eyebrow="00 · See it" title="One menu bar item. That's the whole app.">

<!-- MenuBarDemo is an animated recreation of the popover, built from the
     SwiftUI sources rather than a screenshot, so it stays honest about what
     the app shows — the spinner before the engine reports anything, then the
     percentage that rides beside the progress bar. -->
<ShotFrame><MenuBarDemo /></ShotFrame>

</LandingSection>

<LandingSection id="features" eyebrow="01 · Features" title="Built to be forgotten">

<div class="kh-feature-grid">
<div class="kh-feature">

### Private by design

Your data is encrypted before it leaves your Mac. Passwords live in the macOS Keychain and are never written to disk or logs.

</div>
<div class="kh-feature">

### Out of your way

Lives in the menu bar — no Dock icon, no windows to manage. Set a schedule once and forget it.

</div>
<div class="kh-feature">

### Restore, with or without it

Pick a point in time in the menu bar and Keelhaven puts the files back in a new folder, overwriting nothing. The backups are a standard restic repository too, so the same snapshots restore with free open-source tools on any machine.

</div>
<div class="kh-feature">

### Real schedules

Hourly, daily, or weekly — pick a weekday and a time, and Keelhaven keeps your backups current.

</div>
</div>

</LandingSection>

<LandingSection id="guide" eyebrow="02 · Guide" title="Three decisions, then silence">

<ol class="kh-steps">
<li>

### Pick your folders

Choose the folders you can't lose — documents, photos, projects.

</li>
<li>

### Choose a destination you own

An external drive, a NAS, or any S3-compatible bucket. There is no Keelhaven server in the path.

</li>
<li>

### Set the schedule

Hourly, daily, or weekly. Keelhaven runs in the background and only speaks up when something needs attention.

</li>
</ol>

<div class="kh-guide-note">

Runs on macOS 14 or later, Apple silicon and Intel, with everything it needs bundled. Prefer the terminal? Either command installs the same app the download button serves:

<div class="kh-install">
  <div class="kh-install-row"><span class="kh-install-label">With Homebrew</span><code>brew install --cask shenxianpeng/tap/keelhaven</code></div>
  <div class="kh-install-row"><span class="kh-install-label">Without Homebrew</span><code>curl -fsSL https://keelhaven.app/install.sh | bash</code></div>
</div>

Beta builds aren't notarised by Apple yet, so the very first launch takes one extra approval — the [FAQ below](#faq) walks through it in three clicks.

</div>

</LandingSection>

<LandingSection id="pricing" eyebrow="03 · Pricing" title="Free. That's the entire model.">

<PricingCard>
<template #price><span class="kh-badge">Free and open source</span></template>
<template #note>Free in beta, free after 1.0. No subscription, no account, no strings attached.</template>

- Unlimited backup plans and destinations
- Universal build — Apple silicon and Intel
- Backup engine built in — nothing else to install
- No account, no telemetry, no server of ours in the path

</PricingCard>

</LandingSection>

<LandingSection id="voices" eyebrow="04 · Voices" title="In other people's words">

<div class="kh-voices">
<VoiceCard name="mao mao" handle="@maomao000211" source="X" href="https://x.com/maomao000211/status/2095382774874267938">

Nice scope — restic plus a menu bar UI is exactly the missing piece, and keeping the repo format standard means people aren't locked into your app. The no-account, no-telemetry stance will do a lot of the selling for you.

</VoiceCard>
<VoiceCard name="小弟调调" handle="@jaywcjlove" source="X" href="https://x.com/jaywcjlove/status/2096527566400352339" note="translated from Chinese">

No Dock icon, no main window. Pick the folders, the storage and the schedule, and it runs quietly in the background, speaking up only when something fails. The password is kept in the macOS Keychain, and it writes a standard restic repository, so you can restore from the restic command line without this app.

</VoiceCard>
<VoiceCard name="An_yhl" handle="@An_yhl" source="X" href="https://x.com/An_yhl/status/2096486139725070835" note="translated from Chinese">

A backup tool in the menu bar really is less to think about. Worth a look if you already use restic.

</VoiceCard>
<VoiceCard name="小众软件" handle="@appinn" source="X" href="https://x.com/appinn/status/2096408933376065669" note="translated from Chinese">

Keelhaven: a restic backup tool for the macOS menu bar. Free and open source.

</VoiceCard>
</div>

</LandingSection>

<LandingSection id="faq" eyebrow="05 · Questions" title="Straight answers">

<FaqItem question="macOS says it can't verify Keelhaven. Is something wrong?">

Nothing is wrong — beta builds aren't notarised with Apple yet, so macOS shows its standard warning for any app it can't verify online. Allow it once and it never asks again for that version:

- **macOS 15 (Sequoia):** double-click Keelhaven once and dismiss the warning, then open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway**.
- **macOS 14 (Sonoma):** right-click Keelhaven in Applications, choose **Open**, then click **Open** again.
- **Prefer the Terminal?** `xattr -d com.apple.quarantine /Applications/Keelhaven.app` clears the flag and skips the dialog entirely.

</FaqItem>
<FaqItem question="Does this replace Time Machine?">

No — run both. Time Machine is excellent at putting a whole Mac back the way it was, from a drive on your desk. Keelhaven is for the second copy: the folders you can't lose, encrypted, somewhere that isn't your desk.

</FaqItem>
<FaqItem question="How do I get my files back?">

The plan's **⋯** menu has **Restore…** — it lists every snapshot that plan has taken (date, number of files, size, newest first), and you pick the point in time you want and where to put it. It restores into a new folder named for the plan and the moment, so nothing you have now is overwritten and a restore can never cost you the version you're standing on.

It restores a whole snapshot rather than letting you open one up and pull a single file out — take what you need from the restored folder afterwards. Browsing inside a snapshot is on the list, not in the app yet.

None of it depends on Keelhaven being there: the repository is standard restic, so `restic restore` from any Mac or Linux box does the same job.

</FaqItem>
<FaqItem question="It's free — what's the catch?">

There isn't one. Keelhaven's backup engine is [restic](https://restic.net) — free, open source, and excellent — and Keelhaven adds everything a command-line tool deliberately leaves to you: a schedule that actually runs, passwords held in the macOS Keychain and never written to disk or logs, and a menu bar that stays quiet until something needs you. There are no servers to pay for and no company behind it, and the whole thing is open source — it doesn't need a business model to stay alive. If it earns a place on your Mac, telling a friend is all the support it needs.

</FaqItem>
<FaqItem question="Am I locked into Keelhaven?">

No. Every plan writes an ordinary restic repository, so you can list, verify, and restore your backups with the open-source restic CLI on any Mac or Linux box — with or without Keelhaven installed. If Keelhaven disappears tomorrow, your backups don't.

</FaqItem>
<FaqItem question="Is Keelhaven open source?">

Yes. The full source is on [GitHub](https://github.com/shenxianpeng/keelhaven) under the GPLv3: read it, audit it, build it, fork it. The bundled restic engine is open source under the BSD 2-Clause License — see [Licenses](/licenses) for both notices.

</FaqItem>
<FaqItem question="Is my data readable by anyone else?">

No. Backups are encrypted on your Mac before anything is uploaded, and the repository password is stored only in your macOS Keychain. There is no Keelhaven server, no account system, and no telemetry — the app has nowhere else to send anything.

</FaqItem>
<FaqItem question="Which destinations are supported?">

An external or network drive mounted on your Mac, any S3-compatible bucket (AWS, Backblaze B2, Wasabi, Cloudflare R2, MinIO), SFTP to your own server or NAS, and a [restic REST server](https://github.com/restic/rest-server) you host yourself.

</FaqItem>
<FaqItem question="I back up to Backblaze B2. Why is deleting old backups not freeing any space?">

Because B2 does not delete — it hides. Keelhaven reaches B2 through its S3-compatible API, and deleting an object over that API marks the old version hidden rather than removing it. Hidden versions still take up storage and still appear on your bill, and no amount of `restic forget --prune` can reach them: the deletion has already been issued, and it did what the API allows.

The fix is one setting on the bucket, not in Keelhaven. In your B2 bucket's lifecycle settings, choose **Keep only the last version of the file**. This is what [restic's own documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html) recommends for B2, and it describes what follows: the previous version of the file is "hidden" for one day and then deleted automatically by B2.

Expect the space to come back over the next day or two rather than straight away. B2 applies lifecycle rules on its own schedule, so a bucket that looks unchanged tomorrow morning is normal — not a sign the rule failed.

</FaqItem>
<FaqItem question="Do backups grow forever?">

Only if you leave retention off — which is the default, because deleting your data is never something Keelhaven decides on its own. Every run adds a deduplicated snapshot, storing only what changed.

When a plan should stop growing, **Edit Plan → Retention** has three ways to stop it. *A year of history* and *a month of history* thin older snapshots down to daily, weekly and monthly keepers, so the further back you go the sparser it gets. *Keep a set number of backups* is blunter and easier to reason about: the last N runs survive and everything older goes, however recent it is — a burst of backups in one afternoon can push out the whole of last month, which is the trade you're making when you pick it.

Either way the space is reclaimed after a backup, at most once a week. The repository stays standard restic throughout, so `restic forget --prune` with a policy of your own still works from any machine.

</FaqItem>
<FaqItem question="A backup is eating my whole upload. Can I slow it down?">

Yes. **Edit Plan → Advanced** has an upload limit in KiB/s: set it and restic never pushes harder than that, so a big first backup can't take your connection hostage while you're on a call. The same section can lower how many files are read at once — worth doing on an external hard disk, where reading several at a time only makes it seek more — and raise the pack size for cloud storage that charges per request. All three are empty by default and each one left empty stays exactly as restic ships it.

</FaqItem>
<FaqItem question="How do I know the backups are actually good?">

A failed or incomplete run is never silent — errors from the engine surface immediately in the menu bar and as a notification. Keelhaven also verifies each plan's repository with restic's own integrity check on a schedule — weekly by default, adjustable per plan — and a quiet "Verified" line in the plan row shows the last time it passed; only a problem speaks up. And restoring a file now and then remains the gold standard for any backup tool, ours included.

</FaqItem>
<FaqItem question="A backup failed saying some files could not be read. What do I do?">

That is macOS protecting your files, not the backup engine misbehaving. **Desktop**, **Documents**, **Downloads**, iCloud Drive and parts of your Library are closed to every app until you allow it — and those are exactly the folders people put in their first backup plan. Keelhaven names the files it could not read instead of failing with a generic error, and the plan's row has a button that opens the right settings pane.

Fix it once: open **System Settings › Privacy & Security › Full Disk Access** and turn on Keelhaven — then **quit and reopen Keelhaven** before running the backup again, because macOS only hands the new permission to a freshly launched process. (System Settings offers the same "Quit & Reopen" button for this reason.)

One thing worth knowing: the run may have stored a snapshot anyway, holding everything it *could* read — restic writes what it can and then reports the rest. Those snapshots are marked **incomplete** in the restore window, so you are never shown a file as backed up when it isn't.

This is also why Keelhaven is an app rather than a script. Granting this permission to a shell script means granting it to your terminal, which is a much bigger door than one app.

</FaqItem>
<FaqItem question="Do I need to install anything else?">

No. Everything Keelhaven needs ships inside the app bundle, including its backup engine — no separate install step, no Homebrew requirement, nothing to keep up to date.

</FaqItem>
<FaqItem question="Can I install it from the terminal?">

Two ways, both installing the same DMG the download button serves. With Homebrew, `brew install --cask shenxianpeng/tap/keelhaven` — and `brew upgrade` picks up new releases. Without it, `curl -fsSL https://keelhaven.app/install.sh | bash` downloads the latest release and copies it into Applications; the [script](https://github.com/shenxianpeng/keelhaven/blob/main/site/public/install.sh) is a short, readable page of shell if you'd rather check it first.

</FaqItem>
<FaqItem question="What happens if I forget the repository password?">

The backup is unrecoverable, by design — repositories are encrypted end to end, and nobody, not us and not your storage provider, holds a spare key. Keelhaven keeps the password in your macOS Keychain and can copy it back out after a Touch ID check; put it in your password manager too.

</FaqItem>
<FaqItem question="Why isn't it on the Mac App Store?">

App Store apps must run in the sandbox, and the backup engine needs to read the folders you point it at and open network and SSH connections. Running outside the sandbox is also what lets you grant it Full Disk Access — the permission macOS demands before any app may read Desktop, Documents or Downloads. Keelhaven ships with the hardened runtime enabled, just not through the store — and while in beta, without Apple notarisation, which is why the first launch asks for [one approval](#faq).

</FaqItem>

</LandingSection>

<LandingFooter />

</div>
