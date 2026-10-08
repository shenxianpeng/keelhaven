---
title: Keelhaven and the alternatives
description: How Keelhaven compares with Time Machine, Arq, Backblaze Computer Backup, the restic command line, Backrest and Vorta — and when each of them is the better choice for backing up a Mac.
---

# Keelhaven and the alternatives

Keelhaven does one thing: it keeps an encrypted copy of the folders you choose
on storage that is yours. Several good tools overlap with that, and some of
them will suit you better.

| | Price | Open source | Stores to | Runs as |
|---|---|---|---|---|
| **Keelhaven** | Free | Yes | Your drive, bucket or server | Mac menu bar app |
| **Time Machine** | Comes with macOS | No | A drive or network disk | Part of macOS |
| **Arq** | Paid licence | No | Your drive, server or cloud account | Mac and Windows app |
| **Backblaze Computer Backup** | Subscription | No | Backblaze | Mac and Windows app |
| **restic** | Free | Yes | Your drive, bucket or server | Command line |
| **Backrest** | Free | Yes | Anything restic can reach | Web page served from your machine |
| **Vorta** | Free | Yes | A drive, or a server running Borg | Mac and Linux app |

## Time Machine

Run both. Time Machine puts a whole Mac back the way it was, from a drive on
your desk. Keelhaven is the second copy: the folders you cannot lose,
encrypted, somewhere that is not your desk.

## Arq

The closest in idea: your files, your storage, your key. Arq has been doing it
longer, runs on Windows too, backs up to Google Drive, OneDrive and Dropbox,
and lets you open a backup to pull out one file — Keelhaven restores a whole
snapshot.

Choose Keelhaven if you want it free and open source, with backups in a format
other tools can read.

## Backblaze Computer Backup

The least effort there is: one subscription, the whole computer, their
storage. Choose it if you would rather pay someone to own the problem.

Choose Keelhaven if you want to decide where the data lives, or already have
a NAS or a bucket.

## restic

restic is Keelhaven's engine. If a launchd job and a password in a script
suit you, you do not need Keelhaven.

It adds what a command-line tool leaves to you: a schedule that runs, secrets
in the Keychain, and a notification when something breaks. The repository
stays plain restic — see [Keelhaven for restic users](/restic).

## Backrest

Also a front end for restic, used from a browser. It runs on Linux, in Docker
and on a NAS as well as on a Mac, and exposes more of restic than Keelhaven
does. Choose it for a server, or if you want every setting.

Choose Keelhaven for a Mac you would rather not think about: a native app,
nothing to open in a browser, defaults that are already right.

## Vorta

A desktop app like Keelhaven, built on BorgBackup instead of restic. Borg
wants a drive, or a server it can run on, rather than a plain bucket. Choose
it if you already use Borg.
