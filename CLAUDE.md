# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Keelhaven is a privacy-first macOS menu-bar backup app (SwiftUI, macOS 14+) that wraps the [restic](https://restic.net) CLI. See `docs/ARCHITECTURE.md` for module boundaries, data flow, key v1 decisions and their upgrade paths — read it before structural changes.

## Commands

```bash
# Prerequisites (once)
brew install restic xcodegen        # restic ≥ 0.19 required

# Core package: build + all tests (fast, no Xcode needed)
swift test --package-path KeelhavenCore

# Run a single test class or method
swift test --package-path KeelhavenCore --filter SchedulePolicyTests
swift test --package-path KeelhavenCore --filter ResticCommandTests/testBackupCommand

# App: regenerate the Xcode project (required after editing project.yml,
# and on fresh clones — the .xcodeproj is generated, never committed)
xcodegen generate
xcodebuild -project Keelhaven.xcodeproj -scheme Keelhaven build
```

There is no linter configured. CI (`.github/workflows/ci.yml`) runs the core tests with restic installed and **enforces 100% line coverage on KeelhavenCore** (llvm-cov gate). When adding core code, add the tests that cover it in the same PR or CI goes red. Check locally with:

```bash
swift test --package-path KeelhavenCore --enable-code-coverage
BIN=$(swift build --package-path KeelhavenCore --show-bin-path)
xcrun llvm-cov report "$BIN/KeelhavenCorePackageTests.xctest/Contents/MacOS/KeelhavenCorePackageTests" \
  -instr-profile="$BIN/codecov/default.profdata" -ignore-filename-regex="Tests|\.build"
```

## Architecture in one paragraph

Two layers with a hard boundary: **`KeelhavenCore/`** is a UI-free SwiftPM package holding everything unit-testable (models, restic process runner + JSON parsing, JSON-file persistence, Keychain protocol + impls, pure schedule math); **`Keelhaven/`** is the SwiftUI app target holding only views (`MenuBar/`, `Wizard/`) and thin service wrappers around system frameworks (`Services/`: scheduler timer, notifications, login item; `Support/`: restic discovery). All state flows through a single `@MainActor @Observable` root, `Keelhaven/AppState.swift`, which owns the services and serializes backups (one at a time, app-wide). Anything that can be tested without a UI belongs in KeelhavenCore, not the app target.

## Website (`site/`)

The public website + docs (VitePress, English at the root, Chinese mirror under `site/zh/` — keep the two in step when editing copy) live in `site/`. Preview locally with `npm --prefix site run dev`. On pushes to main that touch `site/**`, `.github/workflows/website.yml` builds the static output and force-pushes it to this repo's `gh-pages` branch, served by GitHub Pages at **https://keelhaven.app** — doc *sources* live in this repo under GPL-3.0-or-later (see `LICENSE`), and the rendered site keeps its own © shenxianpeng notice. Site changes are ignored by the expensive macOS CI. `docs/WEBSITE.md` documents the whole path from source to live domain.

The custom domain hangs on one file: **`site/public/CNAME`**. The deploy force-pushes an orphan `gh-pages` branch, so every file that is not in the build output is deleted on each run — a CNAME set through the GitHub Pages UI, or added to the branch by hand, survives exactly until the next deploy. Keep it in `site/public/`, where both the workflow and `Scripts/deploy-site.sh` pick it up. `base` in `site/.vitepress/config.mts` is `'/'` for the same reason; Cloudflare is DNS-only in front of it (no proxy). The site loads exactly one third party — Google Analytics, added in `config.mts`'s `head` — and `site/privacy.md` discloses it; keep the two in sync if analytics ever changes.

## Non-obvious rules

- **restic parsing is fixture-driven.** All JSON parsing is written against real captured restic 0.19.1 output in `KeelhavenCore/Tests/KeelhavenCoreTests/Fixtures/` — not restic docs. When changing parsers or bumping the supported restic version, re-capture fixtures from the real binary and keep them unmodified. `ResticRunnerIntegrationTests` additionally runs the real restic binary end-to-end and self-skips when restic isn't installed; `ResticS3IntegrationTests` and `ResticSFTPIntegrationTests` do the same against a real S3 server (MinIO) and a real sshd, self-skipping when that backend isn't reachable. CI always runs all three — its setup steps fail loudly rather than let a suite skip silently. See CONTRIBUTING.md for running the network backends locally.
- **Secrets never touch argv or disk.** Repository passwords / S3 keys live in the macOS Keychain (one entry per plan UUID) and reach restic only via the child process environment, which is a minimal clean environment — not the app's. Don't add code that logs, persists, or passes secrets as arguments.
- **`Keelhaven.xcodeproj` and `Keelhaven/Info.plist` are generated** (gitignored). Edit `project.yml` instead, then run `xcodegen generate`. `project.yml` also has a post-build script that stamps the git commit into Info.plist for the About window — it must keep running after ProcessInfoPlistFile and before signing.
- **Public releases are a separate pipeline from CI.** `.github/workflows/release.yml` (triggered by a `vX.Y.Z` tag) builds a universal `Keelhaven-<version>.dmg` and attaches it to a GitHub Release — distinct from `build-app.yml`'s ad-hoc per-arch zips, which only feed `Scripts/install-latest.sh` for personal installs. It needs **no Apple Developer secrets**: without them the DMG is ad-hoc signed and unnotarized (users allow it once on first launch — the release body, site FAQ, and `docs/RELEASING.md` all carry the walkthrough); if the optional signing/notarization secrets are ever added, the same workflow signs and notarizes automatically. Publishing a release triggers `website.yml`, which mirrors the DMG to keelhaven.app/downloads plus `latest.json` — that manifest drives both the site's download button and the in-app update prompt. When Actions minutes are exhausted, `make release VERSION=x.y.z` (`Scripts/release-local.sh`) cuts the identical release from a Mac with no Actions involvement — tests, universal DMG, tag, GitHub Release, site mirror; `Scripts/deploy-site.sh` re-mirrors the newest release DMG on every manual site deploy so a docs push can't kill the download link. `Scripts/make-dmg.sh` (`make dmg`) packages any built `.app` into a DMG locally. Both release paths also bump the Homebrew cask in [shenxianpeng/homebrew-tap](https://github.com/shenxianpeng/homebrew-tap) via `Scripts/update-homebrew-tap.sh` (idempotent; the Actions path needs the `HOMEBREW_TAP_TOKEN` secret and skips silently without it — see `docs/RELEASING.md`).
- **Menu-bar-only app** (`LSUIElement: true`): no Dock icon. App Sandbox is deliberately OFF (hardened runtime ON) because the restic child needs arbitrary folder/network/ssh access — see ARCHITECTURE.md before "fixing" this.
- **restic is bundled, and that carries a licence obligation.** `Scripts/fetch-restic.sh` vendors the pinned restic binary *and* its BSD-2-Clause text; `project.yml` copies the binary to `Contents/MacOS/` and the licence to `Contents/Resources/restic-LICENSE.txt`, which `AboutView` surfaces. Because we redistribute restic, that notice must ship — don't drop it, and re-check it when bumping the pinned version. The site (which distributes nothing, so carries no obligation) mirrors it on `site/licenses.md`, linked discreetly from the footer.
- **Deliberately not built yet** (don't add speculatively): file-level browsing inside snapshots (whole-snapshot restore is shipped: plan actions → Restore…), custom retention keep counts (preset retention is shipped: Edit Plan → Retention), extra backends (REST server is shipped in its default mode only), a free-form "extra restic arguments" field (ruled out, not pending — it would break the `--json` stream the progress UI parses; the three throughput knobs people ask for are shipped as typed fields under Edit Plan → Advanced), launchd scheduling, sandboxing. The canonical list lives in `docs/ARCHITECTURE.md` § "Not yet built (deliberately)" — keep the two in sync.
