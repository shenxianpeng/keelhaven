---
title: 写给 restic 用户
description: Keelhaven 是 restic 的 macOS 原生菜单栏前端。它到底执行了哪些 restic 命令，怎么接入你已有的仓库，哪些事它有意留给命令行。
---

# 写给 restic 用户

Keelhaven 是前端，不是分支。它内置原版 restic（0.19.1），以子进程方式运行，
写出来的就是普通的 restic 仓库。它做的每件事你都可以自己敲命令完成，它补上
的是定时、钥匙串和菜单栏。

## 它执行了什么

| 什么时候 | 命令 |
|---|---|
| 新建计划 | `restic init` |
| 每次定时运行 | `restic backup --json --tag keelhaven <文件夹>` |
| 保留策略，备份成功后执行，最多每周一次 | `restic forget --prune --keep-…` |
| 验证，默认每周 | `restic check` |
| 恢复 | `restic restore <快照> --target <新文件夹>` |
| 你要求清理残留的锁时 | `restic unlock`，从不带 `--remove-all` |

整个应用同一时间只跑一个 restic 进程。

保留策略的几个选项，对应的是这些 keep 参数：

| 选项 | 参数 |
|---|---|
| 保留全部（默认） | 根本不执行 `forget` |
| 保留一年 | `--keep-last 3 --keep-daily 7 --keep-weekly 5 --keep-monthly 12` |
| 保留一个月 | `--keep-last 3 --keep-daily 7 --keep-weekly 4` |
| 保留固定份数的备份 | `--keep-last N` |

## 密钥放在哪

仓库密码和存储密钥都在 macOS 钥匙串里。它们通过环境变量交给 restic：
`RESTIC_PASSWORD`、`AWS_SECRET_ACCESS_KEY`、`RESTIC_REST_PASSWORD`，
从不经过命令行参数，也不落盘。

这份环境是从零拼出来的：只有 `PATH`、`HOME`、`TMPDIR`、`SSH_AUTH_SOCK`，
再加仓库地址和凭据。你会话里的其他变量一概不传。

## 接入已有的仓库

在选目的地那一步展开**高级选项**，勾上**接入该位置上已有的备份仓库**。
Keelhaven 会拿你的密码去验证，不会新建任何东西。

其他机器留下的快照原样保留，恢复窗口里会和 Keelhaven 自己的快照列在一起。

**如果还有别的机器往同一个仓库备份，保留策略请停在「保留全部」。**
Keelhaven 的 `forget` 并不只针对自己的快照：它会把策略用在仓库里所有主机、
所有路径上，和你手动不加过滤条件执行是一回事。共享的仓库，请用你自己的
策略去清理。

## 和命令行一起用

仓库地址就是你想的那样：

| 目的地 | 地址 |
|---|---|
| 文件夹或硬盘 | 路径本身 |
| S3 兼容存储 | `s3:https://<服务地址>/<存储桶>/<路径前缀>` |
| SFTP | `sftp:<用户名>@<主机>:<路径>` |
| REST 服务器 | `rest:http://<主机>:8000/` |

```bash
restic -r sftp:backup@nas.local:/backups/mac snapshots
restic -r sftp:backup@nas.local:/backups/mac restore latest --target ~/Restored
```

两边不会打架，restic 自己的锁管着。

## 它开放了哪些参数

没有「额外参数」输入框，这是有意的：`--quiet` 或 `--verbose` 会破坏进度条
所依赖的 JSON 输出，`--no-lock` 会让「同一时间只跑一个」的保护失效。大家
常要的参数做成了有名字的设置项：

| 设置项 | restic 参数 |
|---|---|
| 排除规则 | `--exclude` |
| 跳过缓存文件夹 | `--exclude-caches` |
| 内容没有变化时跳过备份 | `--skip-if-unchanged` |
| 不要备份挂载在这些文件夹里的其它磁盘 | `--one-file-system` |
| 不要先测量备份大小 | `--no-scan` |
| 预览本次备份 | `--dry-run` |
| 上传限速 | `--limit-upload` |
| 同时读取文件数 | `--read-concurrency` |
| 打包大小 | `--pack-size` |

缺了你离不开的那个？[告诉我们是哪个，用来做什么](https://github.com/shenxianpeng/keelhaven/issues/45)。

## 它不做什么

- **rclone 后端。** 不支持 Google Drive、OneDrive、Dropbox：rclone 的凭据
  存在钥匙串之外。[原因写在这里](https://github.com/shenxianpeng/keelhaven/issues/53)。
- **`restic mount`**，以及在快照里浏览文件。恢复是把整个快照放进一个新文件夹。
- **默认配置之外的 rest-server**：`--private-repos`、`--append-only`，
  或自签名证书。
