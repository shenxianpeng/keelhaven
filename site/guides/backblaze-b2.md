---
title: Back up a Mac to Backblaze B2
description: Encrypted, scheduled Mac backups to your own Backblaze B2 bucket with Keelhaven — the bucket, the application key, the five fields to fill in, and the one lifecycle rule B2 needs.
---

# Back up a Mac to Backblaze B2

Keelhaven encrypts the folders you pick on your Mac and sends them to a B2
bucket that belongs to you. Backblaze stores data it cannot read, and there is
no Keelhaven server in between.

It takes about ten minutes, most of them on Backblaze's side.

## 1. Create a bucket

In the Backblaze web console, open **Buckets** and click **Create a Bucket**.

- **Files in Bucket are:** Private.
- **Object Lock:** leave it disabled. It would stop old backups from ever
  being removed.
- **Default Encryption:** either setting works. The backup is already
  encrypted before it leaves your Mac.

The bucket now shows an **Endpoint**, something like
`s3.us-west-004.backblazeb2.com`. Step 4 needs it.

## 2. Set the lifecycle rule

On the bucket, open **Lifecycle Settings** and choose **Keep only the last
version of the file**.

B2 does not delete what a backup tool deletes. It hides it, and keeps billing
for it. This one setting is what lets old backups leave your bill — the
[FAQ](/#faq) has the long version.

## 3. Create an application key

Open **Application Keys** and click **Add a New Application Key**.

- **Allow access to Bucket(s):** the bucket you just made.
- **Type of Access:** Read and Write.
- **Allow List All Bucket Names:** on. Backblaze asks for it when a
  single-bucket key is used through the S3 API.

Backblaze shows a **keyID** and an **applicationKey**. The applicationKey is
shown once, so copy both now.

The master application key at the top of that page will not work: B2's S3 API
only accepts keys made this way.

## 4. Connect Keelhaven

Click the lighthouse in the menu bar, then **Add Backup Plan…**. Pick your
folders. On the next step open **Advanced options** and choose
**S3-Compatible**.

| Field | What goes in |
|---|---|
| Endpoint | the endpoint from step 1 |
| Bucket | the bucket's name |
| Path prefix | optional — a folder inside the bucket, such as `macbook` |
| Access key ID | the keyID |
| Secret access key | the applicationKey |

Then choose an encryption password, or let Keelhaven generate one. It is kept
in your Keychain; put it in your password manager too. Without it nobody can
read the backup, you included.

## 5. Pick a schedule

Hourly, daily or weekly. The first backup uploads everything. Every one after
it sends only what changed.

## Worth knowing

**The first upload can be slowed down.** *Customize this plan* on the last
step — or **Edit Plan → Advanced** later — has an upload limit, so a large
first backup does not take over your connection.

**Backups grow until you say otherwise.** Deleting your data is never
Keelhaven's decision, so retention is off by default. **Edit Plan →
Retention** turns it on.

**You can restore without Keelhaven.** The bucket holds a standard
[restic](https://restic.net) repository:

```bash
restic -r s3:https://s3.us-west-004.backblazeb2.com/your-bucket snapshots
```

## Another S3 provider

The five fields are the same everywhere. Only the endpoint changes, and the
lifecycle rule in step 2 is a B2 matter alone.

| Provider | Endpoint |
|---|---|
| Amazon S3 | `s3.amazonaws.com` |
| Cloudflare R2 | `<account-id>.r2.cloudflarestorage.com` |
| Wasabi | `s3.<region>.wasabisys.com` |
| MinIO or another self-hosted server | `https://your-host:9000` |
