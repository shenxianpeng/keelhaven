---
layout: page
# The document title and meta description, i.e. the search result. The
# landing copy below is untouched by these.
title: "Keelhaven — Free, encrypted Mac backup to storage you own"
titleTemplate: false
description: "A free, open-source menu bar app that encrypts your Mac's folders and backs them up on a schedule to your own drive, NAS, S3-compatible bucket or SFTP server. Built on restic."
navbar: false
footer: false

# All landing copy that components render lives here (not inside the
# components); zh/index.md mirrors this file section for section — when
# editing copy here, make the same change there (and vice versa).
#
# The words themselves come from design/README.md § Words: say one thing per
# section, in one line where one line will do, and leave the detail to the
# FAQ. If a point was made further up the page, don't make it again.
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
    - { text: How it works, anchor: how }
    - { text: No lock-in, anchor: open }
    - { text: FAQ, anchor: faq }
  footer:
    tagline: Privacy-first backups for your Mac, to storage you own.
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
          - { text: How it works, anchor: how }
          - { text: Source on GitHub, github: true }
      - title: Legal
        links:
          - { text: Privacy, link: /privacy }
          - { text: Licenses, link: /licenses }
  # FlowDiagram.vue. docs/assets/flow.png (drawn by design/materials.mjs)
  # shows the same diagram in the README — change the two together.
  flow:
    mac:
      label: Your Mac
      title: The folders you pick
      items: [Documents, Photos, Projects]
      more: …any folder you choose
    app:
      sub: in your menu bar
      items:
        - Encrypts with a password kept in your Keychain
        - Stores only what changed since last time
        - Runs hourly, daily or weekly, at your time
        - Verifies the repository, weekly by default
    arrows: [your files, encrypted]
    storage:
      label: Storage you own
      title: Wherever you trust
      items:
        - { text: External or network drive }
        - { text: S3-compatible bucket, note: AWS · B2 · Wasabi · R2 · MinIO }
        - { text: SFTP to a server or NAS }
        - { text: restic REST server }
    notInPath:
      label: "Not in the path:"
      items: [a Keelhaven server, an account, telemetry]
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

<!-- Night band: the hero and the three promises. The nav floats over it. -->
<div class="kh-band kh-band-night kh-hero-band">
<section id="top" class="kh-hero">
  <div class="kh-hero-copy">
    <p class="kh-hero-chip"><span aria-hidden="true"></span>Public beta · macOS 14 or later</p>
    <h1 class="kh-hero-title">Back up your Mac to storage <em>you&nbsp;own.</em></h1>
    <p class="kh-hero-tagline">A free menu bar app that encrypts your folders on your Mac, then backs them up on a schedule to your own drive, bucket or server.</p>
    <div class="kh-hero-actions">
      <DownloadButton label="Download for Mac" :fallback-href="releases" />
      <CommandBlock
        command="brew install --cask shenxianpeng/tap/keelhaven"
        lead="Or with Homebrew — no security prompt:"
      />
    </div>
  </div>
  <!-- MenuBarDemo is an animated recreation of the popover, built from the
       SwiftUI sources rather than a screenshot, so it stays honest about what
       the app shows. -->
  <div class="kh-hero-demo"><MenuBarDemo /></div>
</section>
<ul class="kh-promises">
  <li>
    <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>
    <strong>Encrypted on your Mac</strong>
    <span>Only you hold the key.</span>
  </li>
  <li>
    <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="16" height="6" rx="1.5"/><rect x="4" y="13" width="16" height="6" rx="1.5"/><path d="M8 8h.01M8 16h.01"/></svg>
    <strong>Stored where you choose</strong>
    <span>No Keelhaven server in the path.</span>
  </li>
  <li>
    <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 15.5A8.5 8.5 0 1 1 8.5 4a6.8 6.8 0 0 0 11.5 11.5z"/></svg>
    <strong>Quiet until it matters</strong>
    <span>It speaks up only when something needs you.</span>
  </li>
</ul>
</div>

<LandingSection id="where" eyebrow="01 · Where your files go" title="From your Mac to your storage. Nowhere else.">

<FlowDiagram />

</LandingSection>

<LandingSection id="how" band="sand" eyebrow="02 · How it works" title="Three decisions, then silence.">

<ol class="kh-steps">
  <li>
    <div class="kh-step-shot"><img src="/screenshots/wizard.webp" alt="The New Backup Plan window, on the step that asks where the encrypted backup should go." width="720" height="758" loading="lazy"></div>
    <h3>1 · Make a plan</h3>
    <p>Folders, destination, schedule.</p>
  </li>
  <li>
    <div class="kh-step-shot"><img src="/screenshots/menu-bar.webp" alt="The menu bar panel listing three plans, each with a green dot, its schedule and when it last ran." width="720" height="997" loading="lazy"></div>
    <h3>2 · Let it run</h3>
    <p>A green dot means the last backup worked.</p>
  </li>
  <li>
    <div class="kh-step-shot"><img src="/screenshots/restore.webp" alt="The Restore Backup window listing snapshots by date, file count and size." width="720" height="591" loading="lazy"></div>
    <h3>3 · Restore any point in time</h3>
    <p>Into a new folder. Nothing is overwritten.</p>
  </li>
</ol>

</LandingSection>

<LandingSection id="open" split band="night" eyebrow="03 · No lock-in" title="Your backups outlive the app.">

  <p class="kh-lead">Every plan is a standard <a href="https://restic.net" target="_blank" rel="noopener">restic</a> repository. Restore it on any Mac or Linux machine, with or without Keelhaven.</p>
  <div class="kh-term">
    <div class="kh-term-bar" aria-hidden="true"><span></span><span></span><span></span></div>
    <pre><code><span class="kh-term-prompt">$ </span>restic -r sftp:you@nas.local:/backups \
    restore latest --target ~/Restored</code></pre>
  </div>

</LandingSection>

<LandingSection id="free" split eyebrow="04 · Price" title="Free. That's the whole model.">

<p class="kh-lead">Open source under the GPLv3. No account, no subscription, no telemetry.</p>

<VoiceCard name="mao mao" handle="@maomao000211" source="X" href="https://x.com/maomao000211/status/2095382774874267938">

Nice scope — restic plus a menu bar UI is exactly the missing piece, and keeping the repo format standard means people aren't locked into your app. The no-account, no-telemetry stance will do a lot of the selling for you.

</VoiceCard>

</LandingSection>

<LandingSection id="faq" eyebrow="05 · Questions" title="Straight answers">

<FaqItem question="Does this replace Time Machine?">

No — run both. Time Machine is excellent at putting a whole Mac back the way it was, from a drive on your desk. Keelhaven is for the second copy: the folders you can't lose, encrypted, somewhere that isn't your desk.

</FaqItem>
<FaqItem question="macOS says it can't verify Keelhaven. Is something wrong?">

Nothing is wrong — beta builds aren't notarised with Apple yet, so macOS shows its standard warning for any app it can't verify online. Allow it once and it never asks again for that version:

- **macOS 15 (Sequoia):** double-click Keelhaven once and dismiss the warning, then open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway**.
- **macOS 14 (Sonoma):** right-click Keelhaven in Applications, choose **Open**, then click **Open** again.
- **Prefer the Terminal?** `xattr -d com.apple.quarantine /Applications/Keelhaven.app` clears the flag and skips the dialog entirely.

</FaqItem>
<FaqItem question="What happens if I forget the repository password?">

The backup is unrecoverable, by design — repositories are encrypted end to end, and nobody, not us and not your storage provider, holds a spare key. Keelhaven keeps the password in your macOS Keychain and can copy it back out after a Touch ID check; put it in your password manager too.

</FaqItem>

<FaqMore label="More questions">

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

**If it comes back after an update, this is why.** macOS ties this permission to the exact build it was granted for. Keelhaven's beta builds aren't Developer ID-signed yet, so every new version is a different app as far as that list is concerned, and the permission has to be given again: remove Keelhaven with the **−** button, add it back from Applications, then quit and reopen. Signing and notarisation remove this step; until then, a release can bring it back.

One thing worth knowing: the run may have stored a snapshot anyway, holding everything it *could* read — restic writes what it can and then reports the rest. Those snapshots are marked **incomplete** in the restore window, so you are never shown a file as backed up when it isn't.

This is also why Keelhaven is an app rather than a script. Granting this permission to a shell script means granting it to your terminal, which is a much bigger door than one app.

</FaqItem>
<FaqItem question="Do I need to install anything else?">

No. Everything Keelhaven needs ships inside the app bundle, including its backup engine — no separate install step, no Homebrew requirement, nothing to keep up to date.

</FaqItem>
<FaqItem question="Can I install it from the terminal?">

Two ways, both installing the same DMG the download button serves. With Homebrew, `brew install --cask shenxianpeng/tap/keelhaven` — and `brew upgrade` picks up new releases. Without it, `curl -fsSL https://keelhaven.app/install.sh | bash` downloads the latest release and copies it into Applications; the [script](https://github.com/shenxianpeng/keelhaven/blob/main/site/public/install.sh) is a short, readable page of shell if you'd rather check it first.

</FaqItem>
<FaqItem question="Why isn't it on the Mac App Store?">

App Store apps must run in the sandbox, and the backup engine needs to read the folders you point it at and open network and SSH connections. Running outside the sandbox is also what lets you grant it Full Disk Access — the permission macOS demands before any app may read Desktop, Documents or Downloads. Keelhaven ships with the hardened runtime enabled, just not through the store — and while in beta, without Apple notarisation, which is why the first launch asks for [one approval](#faq).

</FaqItem>

</FaqMore>

</LandingSection>

<div class="kh-band kh-band-night kh-cta">
<section class="kh-cta-inner">
  <img src="/favicon-180.png" alt="" width="88" height="88">
  <h2 class="kh-h2">Set it up once. Then forget it.</h2>
  <DownloadButton label="Download for Mac" :fallback-href="releases" />
  <p class="kh-cta-note">macOS 14 or later · Apple silicon and Intel</p>
</section>
</div>

<LandingFooter />

</div>
