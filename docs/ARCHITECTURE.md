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
   `NSWorkspace.didWakeNotification`. A plan that has never run anchors on
   `createdAt`: due at once if it was created with "Start the first backup
   now", otherwise at the first scheduled time after creation. That flag is
   persisted on the plan rather than acted on once at creation, because this
   function is the only thing consulted on every tick and at every launch.
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
- **Exit code 3** is a partial failure rather than a fatal one: at least one
  source item could not be read, and restic **still writes a snapshot** of
  everything it could read (captured in `Fixtures/backup-permission-denied.jsonl`,
  with the stderr half in `…stderr.jsonl`). Which items failed appears only on
  stderr, one `{"message_type":"error",…,"item":…}` line per item *before* the
  closing `exit_error`; `ResticJSON.unreadableItems` collects them and
  `ResticError.someSourcesUnreadable` carries them to the UI. The `summary`
  event still arrives before the failure, which is why a failed run can record
  the id of the incomplete snapshot it left behind.
- Snapshot entries embed a `summary` object that lacks `total_duration` and
  `snapshot_id` — those fields are optional in `BackupSummary` so one type
  decodes both shapes.

## macOS permissions (TCC)

The likeliest first-run failure is not a restic problem at all. `~/Desktop`,
`~/Documents`, `~/Downloads`, iCloud Drive and the protected corners of
`~/Library` are guarded by TCC — and those are exactly the folders a person
picks for their first plan.

Two places handle it, and the split matters:

- **Before spawning restic**, `SourceAccess.unreadableExistingPaths` checks the
  plan's source folders, so a folder that exists but cannot be read fails the
  run in a second rather than after minutes of work. A folder that does not
  exist is deliberately *not* reported: an unplugged drive has a different
  cause and a different fix, and pointing someone at Full Disk Access because
  their backup disk is on a desk would be a lie.
- **After restic exits 3**, the error carries the paths it named and the plan
  row offers a deep link to the Full Disk Access pane.

This is also why the app's shape is load-bearing rather than cosmetic: a shell
script cannot ask macOS for this permission, and the usual workaround — giving
it to the terminal that runs the script — opens a far larger door. A signed
app bundle is what appears in that list on its own behalf. Notarisation
(docs/RELEASING.md) is a separate, first-launch trust question rather than a
prerequisite for the grant itself.

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

A free-form "extra restic arguments" field is not on the list either — it is
ruled out rather than pending. `--quiet` or `--verbose` would break the
`--json` event stream every progress bar and summary is parsed from,
`--no-lock` would defeat the one-run-at-a-time guard, and `--insecure-tls`
would silently drop certificate checking; none of it can be tested. The
throughput knobs people actually ask for are shipped instead, as typed and
range-checked fields (Edit Plan → Advanced: `--limit-upload`,
`--read-concurrency`, `--pack-size`). Anything beyond those three should be
a named field with its own validation, not an escape hatch.
