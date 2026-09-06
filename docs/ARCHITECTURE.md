# Keelhaven Architecture

## Module boundaries

```
┌─────────────────────────────────────────────────┐
│ Keelhaven (SwiftUI app target)                  │
│  MenuBar/   Wizard/   Services/   Support/      │
│  AppState: single @MainActor @Observable root   │
└───────────────────────┬─────────────────────────┘
                        │ depends on
┌───────────────────────▼─────────────────────────┐
│ KeelhavenCore (SwiftPM package, UI-free)        │
│  Models/       BackupPlan, Destination, Schedule│
│  Restic/       ResticRunner, messages, errors   │
│  Persistence/  PlanStore, RunHistoryStore       │
│  Keychain/     KeychainStoring + impls          │
│  Scheduling/   SchedulePolicy (pure functions)  │
└───────────────────────┬─────────────────────────┘
                        │ spawns
                ┌───────▼───────┐
                │ restic binary │  (user-installed, ≥0.19)
                └───────────────┘
```

Everything that can be tested without a UI lives in `KeelhavenCore`. The app
target holds only SwiftUI views and thin service wrappers around system
frameworks (UserNotifications, ServiceManagement, AppKit panels).

## Data flow: a scheduled backup

1. `SchedulerService` fires every 60s → `AppState.runDuePlans()`.
2. `SchedulePolicy.isDue(plan)` — pure date math; a missed window (Mac asleep)
   makes the plan due immediately. Also checked at launch and on
   `NSWorkspace.didWakeNotification`.
3. `AppState` reads secrets from the Keychain (`KeychainAccount` names are
   keyed by plan UUID), builds `RepoCredentials`.
4. `ResticRunner.backupStream(...)` spawns `restic backup --json` with a
   minimal clean environment. Stdout JSON-lines are decoded into
   `BackupProgressEvent`s and streamed back.
5. `AppState` updates `runStates[plan.id]` (menu bar redraws), then writes a
   `BackupRunRecord` via `PlanStore`/`RunHistoryStore` and posts a
   notification.

Backups are serialized: one at a time, app-wide.

## Key decisions and their upgrade paths

| Decision (v1) | Why | Upgrade path |
|---|---|---|
| One restic repository per plan | Independent passwords, no lock contention, trivial snapshot mapping | — |
| Secrets via child env (`RESTIC_PASSWORD`) | Never argv (world-visible), never disk | `RESTIC_PASSWORD_COMMAND` helper reading Keychain directly |
| Bundled universal restic (`Contents/MacOS/restic`, vendored + checksum-verified by `Scripts/fetch-restic.sh`, ad-hoc/app-signed at build) | End users must not need Homebrew | User path override and Homebrew locations remain as fallbacks |
| In-app 60s timer + login item | No launchd plist lifecycle to manage | `SMAppService.agent(plistName:)` launchd agent reusing `SchedulePolicy` |
| App Sandbox OFF (hardened runtime ON) | restic child needs arbitrary folder read, network, ssh | Security-scoped bookmarks + XPC — known App Store blocker, revisit post-v1 |
| JSON files in Application Support | Human-readable, atomic writes, Codable round-trip tested | — |
| Retention as three presets (`off`/`year`/`month`), `forget --prune` riding the backup tail weekly | A choice a person can read instead of five keep-count fields; off (never delete) is the default; output isn't parsed — the exit code decides, like `check` | Custom keep counts can become a parameterized case alongside the presets |

## restic contract

All parsing is written against **captured fixtures** from restic 0.19.1
(`KeelhavenCore/Tests/KeelhavenCoreTests/Fixtures/`), not documentation.
Verified behavior:

- `backup --json` streams `{"message_type":"status",…}` lines then exactly one
  `summary` line. `current_files` and `seconds_remaining` are sometimes absent.
- Fatal errors write `{"message_type":"exit_error","code":N,"message":…}` to
  stderr. Observed codes: **10** = repository doesn't exist, **12** = wrong
  password (11 = locked, per restic docs). `ResticError.classify` maps these.
- Snapshot entries embed a `summary` object that lacks `total_duration` and
  `snapshot_id` — those fields are optional in `BackupSummary` so one type
  decodes both shapes.

When bumping the supported restic version, re-capture fixtures and re-run
`swift test`; the integration test (`ResticRunnerIntegrationTests`) also
exercises the real binary end-to-end when it's installed.

## Not yet built (deliberately)

File-level browsing inside snapshots (whole-snapshot restore shipped:
plan actions → Restore… lists snapshots and restores into a fresh subfolder),
custom retention keep counts (preset retention shipped: Edit Plan →
Retention), additional backends (rclone family), rest-server beyond its
default mode (`--private-repos`, `--append-only`, self-signed/custom-CA
TLS — public CA-signed HTTPS works), launchd scheduling, sandboxing.
