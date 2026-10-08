---
title: Back up a Mac to a NAS
description: Encrypted, scheduled Mac backups to a Synology, QNAP or any other NAS with Keelhaven — as a share mounted in Finder, or over SFTP with an SSH key.
---

# Back up a Mac to a NAS

Keelhaven encrypts the folders you pick on your Mac and stores them on your
NAS. Anyone who opens that folder on the NAS sees encrypted data and nothing
else.

There are two ways to reach it. Start with the first unless you already use
SSH keys.

## The simple way: a mounted share

1. In Finder, choose **Go → Connect to Server…**, enter `smb://` and your
   NAS's name — `smb://nas.local` — and open the shared folder you want
   backups in.
2. In Keelhaven, click the lighthouse in the menu bar, then **Add Backup
   Plan…**, and pick your folders.
3. On the next step click **Choose…** and select a folder on the share. It is
   under **Locations** in the sidebar.
4. Choose an encryption password and a schedule.

The share has to be mounted when a backup runs. If it is not, that run fails
and Keelhaven tells you. Nothing is lost: the next run picks up everything
that changed since the last good one.

## Without mounting: SFTP

Over SFTP, Keelhaven reaches the NAS on its own whenever it is on the network.
It signs in with an SSH key and never asks for the NAS password, so key login
has to work first.

**1. Check it in Terminal.**

```bash
ssh backup@nas.local
```

This must sign you in without asking for a password or a passphrase. The
first time, it asks whether to trust the NAS — answer yes here, because
Keelhaven cannot answer that question for you.

If it does ask for a password, the NAS does not have your key yet:

```bash
ssh-keygen -t ed25519        # only if you have no key
ssh-copy-id backup@nas.local
```

**2. Connect Keelhaven.** On the destination step open **Advanced options**
and choose **SFTP / NAS**.

| Field | What goes in |
|---|---|
| User | the account on the NAS, such as `backup` |
| Host | `nas.local`, or its IP address |
| Port | `22`, unless you changed it |
| Path on server | the folder for this Mac's backups, such as `/backups/mac` |

Then the encryption password and the schedule, as above.

### On a Synology

- SFTP is off until you turn it on: **Control Panel → File Services → FTP →
  Enable SFTP service**.
- Key login needs a home folder to keep the key in: **Control Panel → User &
  Group → Advanced → Enable user home service**. Synology's
  [guide to key pairs](https://kb.synology.com/en-uk/DSM/tutorial/How_to_log_in_to_DSM_with_key_pairs_as_admin_or_root_permission_via_SSH_on_computers)
  covers the rest.
- Over SFTP a Synology usually lists its shared folders at the top level, so
  the path looks like `/backups/mac` rather than `/volume1/backups/mac`. Run
  `sftp backup@nas.local`, then `ls`, to see what yours shows.

## Worth knowing

**A NAS in the same house is one copy, not two.** It guards against a dead
Mac, not against a fire or a burglary. A second plan to
[a bucket](/guides/backblaze-b2) covers that — **Duplicate Plan…** copies
this one to a new destination.

**You can restore without Keelhaven.** The folder holds a standard
[restic](https://restic.net) repository:

```bash
restic -r sftp:backup@nas.local:/backups/mac snapshots
```
