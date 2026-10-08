---
title: 使用指南
description: 用 Keelhaven 备份 Mac 的分步指南：备份到 Backblaze B2 或其他 S3 存储桶、备份到 NAS，以及和 restic 命令行一起用。
---

# 使用指南

每一篇都从零讲到第一次备份跑完。

- [把 Mac 备份到 Backblaze B2](/zh/guides/backblaze-b2)：建存储桶、建密钥，
  再加 B2 必须设的那一项。同样的步骤也适用于 Amazon S3、Cloudflare R2、
  Wasabi 和 MinIO。
- [把 Mac 备份到 NAS](/zh/guides/nas)：群晖、威联通或任何一台服务器，
  挂载共享文件夹或走 SFTP 都行。

还有两页，回答动手之前的问题：

- [写给 restic 用户](/zh/restic)：它到底执行了哪些命令，怎么接入你已有的仓库。
- [Keelhaven 和同类工具](/zh/compare)：时间机器、Arq、Backblaze、Backrest、
  Vorta，各自什么时候更合适。
