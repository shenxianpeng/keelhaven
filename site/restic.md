---
title: Keelhaven for restic users
description: Keelhaven is a native macOS menu bar front end for restic. Exactly which restic commands it runs, how to connect a repository you already have, and what it deliberately leaves to the command line.
---

# Keelhaven for restic users

Keelhaven is a front end, not a fork. It ships the stock restic binary
(0.19.1), runs it as a child process, and writes ordinary restic repositories.
Everything it does you could type yourself — it adds the schedule, the
Keychain and the menu bar.

## What it runs

| When | Command |
|---|---|
| A new plan | `restic init` |
| Each scheduled run | `restic backup --json --tag keelhaven <folders>` |
| Retention, at most weekly, after a good backup | `restic forget --prune --tag keelhaven --keep-…` |
| Verification, weekly by default | `restic check` |
| Opening a snapshot to choose files | `restic ls <snapshot> --json` |
| Restore | `restic restore <snapshot> --target <new folder>`, plus `--include <path>` for each file or folder you picked |
| A stale lock, when you ask | `restic unlock` — never `--remove-all` |

One restic process runs at a time, app-wide. The `--tag` on `forget` arrived
in 0.9.2 — *Use a repository you already have*, below, says why it matters.

A snapshot is listed once, whole, and browsed from memory: opening the
repository is the slow part of `ls`, so a call per folder would pay for it on
every click. The paths handed to `--include` are escaped, so a file called
`photo[1].jpg` is restored as itself and not as whatever the pattern matches.

The retention choices are presets over the keep flags:

| Choice | Flags |
|---|---|
| Keep everything (the default) | `forget` is never run |
| A year of history | `--keep-last 3 --keep-daily 7 --keep-weekly 5 --keep-monthly 12` |
| A month of history | `--keep-last 3 --keep-daily 7 --keep-weekly 4` |
| Keep a set number of backups | `--keep-last N` |

## Where the secrets are

The repository password and any storage key live in the macOS Keychain. They
reach restic through its environment — `RESTIC_PASSWORD`,
`AWS_SECRET_ACCESS_KEY`, `RESTIC_REST_PASSWORD` — and never through its
arguments or a file.

That environment is built from scratch: `PATH`, `HOME`, `TMPDIR` and
`SSH_AUTH_SOCK`, plus the repository and its credentials. Nothing else from
your session is passed on.

## Use a repository you already have

On the destination step open **Advanced options** and tick **Connect to an
existing repository at this destination**. Keelhaven checks your password
against it and creates nothing.

Snapshots made by other machines stay where they are, and the restore window
lists them alongside Keelhaven's own.

Retention leaves them alone as well, from 0.9.2 on. There `forget` runs with
`--tag keelhaven`, so it only ever considers snapshots Keelhaven made;
anything the restic command line or another tool wrote stays until you prune
it yourself.

**0.9.1 and earlier applied the policy to every snapshot in the repository.**
Update before you turn retention on for a repository that something else
writes to.

**One repository, one retention choice.** Every plan tags its snapshots the
same way, so when two Keelhaven plans — or two Macs running Keelhaven — share
a repository, whichever retention pass runs applies its policy to both. Give
each plan a repository of its own, or set them all to the same choice.

## Use the command line alongside it

The repository address is what you would expect:

| Destination | Address |
|---|---|
| Folder or drive | the path itself |
| S3-compatible | `s3:https://<endpoint>/<bucket>/<prefix>` |
| SFTP | `sftp:<user>@<host>:<path>` |
| REST server | `rest:http://<host>:8000/` |

```bash
restic -r sftp:backup@nas.local:/backups/mac snapshots
restic -r sftp:backup@nas.local:/backups/mac restore latest --target ~/Restored
```

restic's own locks keep the two from colliding.

## Which options it exposes

There is no box for extra arguments, on purpose: `--quiet` or `--verbose`
would break the JSON stream the progress bar reads, and `--no-lock` would
defeat the one-run-at-a-time guard. The options people ask for are named
settings instead:

| Setting | restic flag |
|---|---|
| Exclude patterns | `--exclude` |
| Skip cache folders | `--exclude-caches` |
| Skip backups when nothing has changed | `--skip-if-unchanged` |
| Don't back up other disks mounted inside these folders | `--one-file-system` |
| Don't measure the backup first | `--no-scan` |
| Preview Backup | `--dry-run` |
| Upload limit | `--limit-upload` |
| Files read at once | `--read-concurrency` |
| Pack size | `--pack-size` |

Missing one you rely on? [Say which, and why](https://github.com/shenxianpeng/keelhaven/issues/45).

## What it does not do

- **rclone backends.** Google Drive, OneDrive and Dropbox are not supported;
  an rclone remote keeps its credentials outside the Keychain. The
  [reasoning is here](https://github.com/shenxianpeng/keelhaven/issues/53).
- **`restic mount`.** The Restore window opens a snapshot, searches it and
  restores files out of it; it does not mount one in Finder.
- **rest-server beyond its defaults** — `--private-repos`, `--append-only` or
  a self-signed certificate.
