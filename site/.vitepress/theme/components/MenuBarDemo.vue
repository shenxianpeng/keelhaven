<script setup>
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

// Every visible string in the demo, overridable from frontmatter
// (landing.demo) so zh/index.md can show the app's real Chinese UI — the
// values there should come from the app's Localizable.xcstrings, keeping the
// recreation honest in every language.
const defaults = {
  ariaLabel:
    'Animated demo of the Keelhaven menu bar app running a backup: a plan named Documents is backed up to an external drive, showing a small progress bar and its percentage while running, then a Backup complete notification.',
  clock: 'Mon 9:41 AM',
  plan1Name: 'Documents',
  plan1Sched: 'Every day at 9:00 AM',
  plan1StatusIdle: 'Backed up 2 hours ago',
  plan1StatusDone: 'Backed up 1 second ago',
  plan2Name: 'Photos',
  plan2Sched: 'Every hour',
  plan2Status: 'Backed up 26 minutes ago',
  backUpNow: 'Back Up Now',
  addPlan: 'Add Backup Plan…',
  startAtLogin: 'Start at Login',
  quit: 'Quit Keelhaven',
  notifTitle: 'Backup complete',
  notifBody: 'Documents: 12 new files, 48 MB added.',
}

const { frontmatter } = useData()
const t = computed(() => ({
  ...defaults,
  ...(frontmatter.value.landing?.demo ?? {}),
}))
</script>

<template>
  <!-- An animated recreation of the real menu bar popover, drawn from the
       SwiftUI sources (MenuBarView / PlanStatusRow) so it can't drift into
       showing UI the app doesn't have. Pure CSS, one ~12s loop: idle → the
       cursor clicks Back Up Now → the progress bar and its percentage run →
       done, with the completion notification the app actually posts. All
       timing lives in landing.css under .kh-demo-*. -->
  <div class="kh-demo" role="img"
       :aria-label="t.ariaLabel">

    <div class="kh-demo-scene" aria-hidden="true">

    <!-- Mini macOS menu bar -->
    <div class="kh-demo-menubar">
      <span class="kh-demo-mb-slot">
        <!-- design/svg/menubar.svg — the app's template glyph, verbatim -->
        <svg class="kh-demo-mb-idle" width="17" height="17" viewBox="0 0 36 36"><g fill="currentColor"><path d="M 11.8,12.4 C 12.2,8.3 14.7,5.2 18,5.2 C 21.3,5.2 23.8,8.3 24.2,12.4 Z"/><rect x="13.7" y="12.4" width="8.6" height="6.4"/><rect x="10.2" y="18.8" width="15.6" height="3.1" rx="1.3"/><path d="M 13.9,21.9 h 8.2 C 22.6,25.2 23.4,28.2 24.2,30.4 h -12.4 C 12.6,28.2 13.4,25.2 13.9,21.9 Z"/><rect x="8.6" y="30.1" width="18.8" height="3.4" rx="1.5"/></g></svg>
        <!-- arrow.triangle.2.circlepath stand-in while a backup runs -->
        <svg class="kh-demo-mb-busy" width="17" height="17" viewBox="0 0 24 24"><g class="kh-demo-mb-busy-spin" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M 20 12 A 8 8 0 1 1 12 4"/><path d="M 8.6 1.6 L 12.6 4.1 L 9.6 7.6"/></g></svg>
      </span>
      <span class="kh-demo-mb-clock">{{ t.clock }}</span>
    </div>

    <!-- The popover, hanging off the menu bar item -->
    <div class="kh-demo-popover">
      <div class="kh-demo-arrow"></div>

      <div class="kh-demo-header">
        <span class="kh-demo-title">Keelhaven</span>
        <svg class="kh-demo-info" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="9"/><path d="M12 11v5" stroke-linecap="round"/><circle cx="12" cy="7.6" r="1.1" fill="currentColor" stroke="none"/></svg>
      </div>

      <div class="kh-demo-divider"></div>

      <!-- Plan 1: Documents — the one the demo backs up -->
      <div class="kh-demo-plan">
        <span class="kh-demo-dot kh-demo-dot-1"></span>
        <div class="kh-demo-plan-body">
          <div class="kh-demo-plan-top">
            <span class="kh-demo-plan-name">{{ t.plan1Name }}</span>
            <span class="kh-demo-runbtn kh-demo-runbtn-1">{{ t.backUpNow }}</span>
            <svg class="kh-demo-more" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="9"/><circle cx="7.5" cy="12" r="1.15" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.15" fill="currentColor" stroke="none"/><circle cx="16.5" cy="12" r="1.15" fill="currentColor" stroke="none"/></svg>
          </div>
          <div class="kh-demo-plan-dest">/Volumes/Harbor</div>
          <div class="kh-demo-plan-sched">
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.2 2" stroke-linecap="round"/></svg>
            {{ t.plan1Sched }}
          </div>
          <div class="kh-demo-statusline">
            <span class="kh-demo-status kh-demo-status-idle">{{ t.plan1StatusIdle }}</span>
            <span class="kh-demo-status kh-demo-status-done">{{ t.plan1StatusDone }}</span>
            <!-- The bar and the number it stands for share a line, as they
                 do in PlanStatusRow: a determinate bar that never says how
                 far along it is leaves the reader guessing. -->
            <span class="kh-demo-running">
              <span class="kh-demo-progress"><span class="kh-demo-progress-fill"></span></span>
              <span class="kh-demo-pct"></span>
            </span>
          </div>
        </div>
      </div>

      <!-- Plan 2: Photos — idle throughout, its button disabled mid-run -->
      <div class="kh-demo-plan">
        <span class="kh-demo-dot kh-demo-dot-2"></span>
        <div class="kh-demo-plan-body">
          <div class="kh-demo-plan-top">
            <span class="kh-demo-plan-name">{{ t.plan2Name }}</span>
            <span class="kh-demo-runbtn kh-demo-runbtn-2">{{ t.backUpNow }}</span>
            <svg class="kh-demo-more" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="9"/><circle cx="7.5" cy="12" r="1.15" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.15" fill="currentColor" stroke="none"/><circle cx="16.5" cy="12" r="1.15" fill="currentColor" stroke="none"/></svg>
          </div>
          <div class="kh-demo-plan-dest">s3://keelhaven-photos</div>
          <div class="kh-demo-plan-sched">
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.2 2" stroke-linecap="round"/></svg>
            {{ t.plan2Sched }}
          </div>
          <div class="kh-demo-statusline">
            <span class="kh-demo-status is-on">{{ t.plan2Status }}</span>
          </div>
        </div>
      </div>

      <div class="kh-demo-divider"></div>
      <div class="kh-demo-addrow">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>
        {{ t.addPlan }}
      </div>
      <div class="kh-demo-divider"></div>

      <div class="kh-demo-footrow">
        <span>{{ t.startAtLogin }}</span>
        <span class="kh-demo-switch"><span class="kh-demo-knob"></span></span>
      </div>
      <div class="kh-demo-footrow kh-demo-quit">
        <span>{{ t.quit }}</span>
        <span class="kh-demo-kbd">⌘Q</span>
      </div>

      <!-- macOS pointer -->
      <svg class="kh-demo-cursor" width="17" height="24" viewBox="0 0 17 24">
        <path d="M1 1 L1 18.5 L5.4 14.6 L8.2 21.4 L11.4 20 L8.6 13.4 L14.5 13.2 Z"
              fill="#fff" stroke="#000" stroke-width="1.2" stroke-linejoin="round"/>
      </svg>
    </div>

    </div>

    <!-- The completion notification the app actually posts. Sits at the
         demo's top-right like a real macOS banner, above the scene. -->
    <div class="kh-demo-notif" aria-hidden="true">
      <img :src="withBase('/icon-128.png')" alt="" width="30" height="30" />
      <div>
        <div class="kh-demo-notif-title">{{ t.notifTitle }}</div>
        <div class="kh-demo-notif-body">{{ t.notifBody }}</div>
      </div>
    </div>
  </div>
</template>
