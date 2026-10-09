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
| 保留策略，备份成功后执行，最多每周一次 | `restic forget --prune --tag keelhaven --keep-…` |
| 验证，默认每周 | `restic check` |
| 打开快照挑选文件 | `restic ls <快照> --json` |
| 恢复 | `restic restore <快照> --target <新文件夹>`，你选了哪些文件或文件夹，就各加一个 `--include <路径>` |
| 你要求清理残留的锁时 | `restic unlock`，从不带 `--remove-all` |

整个应用同一时间只跑一个 restic 进程。`forget` 上的 `--tag` 是 0.9.2 加的，
为什么要紧，见下面「接入已有的仓库」。

一个快照只完整列出一次，之后都在内存里浏览：`ls` 慢在打开仓库，按文件夹
逐个去列，每点一下都要再付一次这个代价。交给 `--include` 的路径会先转义，
所以名叫 `photo[1].jpg` 的文件恢复出来的就是它自己，而不是这个通配符碰巧
匹配到的别的文件。

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

保留策略也不会动它们，从 0.9.2 起是这样。这之后的 `forget` 带着
`--tag keelhaven` 执行，只会处理 Keelhaven 自己创建的快照；restic 命令行或
别的工具写进去的，会一直留着，要清理得你自己动手。

**0.9.1 及更早的版本，会把保留策略用在仓库里的所有快照上。** 如果仓库还有
别的东西在写，请先升级，再打开保留策略。

**一个仓库，只用一种保留策略。** 每个计划给快照打的标签都一样，所以两个
Keelhaven 计划（或者两台装了 Keelhaven 的 Mac）共用一个仓库时，谁的保留
策略先跑，就会同时作用在两边。要么给每个计划单独一个仓库，要么把它们的
保留策略设成同一个。

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
- **`restic mount`。** 恢复窗口可以打开快照、在里面搜索、只恢复其中的文件，
  但不能把快照挂载到访达里。
- **默认配置之外的 rest-server**：`--private-repos`、`--append-only`，
  或自签名证书。
