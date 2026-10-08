---
title: Keelhaven 和同类工具
description: Keelhaven 与时间机器、Arq、Backblaze 电脑备份、restic 命令行、Backrest、Vorta 的对比，以及备份 Mac 时它们各自什么时候更合适。
---

# Keelhaven 和同类工具

Keelhaven 只做一件事：把你选的文件夹加密后，存一份到你自己的存储上。
好几个不错的工具和它有重叠，其中有的可能更适合你。

| | 价格 | 开源 | 存到哪 | 形态 |
|---|---|---|---|---|
| **Keelhaven** | 免费 | 是 | 你的硬盘、存储桶或服务器 | Mac 菜单栏应用 |
| **时间机器** | macOS 自带 | 否 | 硬盘或网络磁盘 | macOS 的一部分 |
| **Arq** | 付费授权 | 否 | 你的硬盘、服务器或网盘账号 | Mac 和 Windows 应用 |
| **Backblaze 电脑备份** | 订阅 | 否 | Backblaze | Mac 和 Windows 应用 |
| **restic** | 免费 | 是 | 你的硬盘、存储桶或服务器 | 命令行 |
| **Backrest** | 免费 | 是 | restic 能连的任何地方 | 本机提供的网页界面 |
| **Vorta** | 免费 | 是 | 硬盘，或装了 Borg 的服务器 | Mac 和 Linux 应用 |

## 时间机器

两个一起用。时间机器擅长把整台 Mac 恢复原样，用的是桌上那块硬盘。
Keelhaven 管的是第二份副本：丢不起的那些文件夹，加密后放到别的地方。

## Arq

思路最接近的一个：你的文件、你的存储、你的密钥。Arq 做得更久，也支持
Windows，能备份到 Google Drive、OneDrive 和 Dropbox，还能打开备份只取出
一个文件，而 Keelhaven 恢复的是整个快照。

想要免费、开源，备份格式别的工具也能读，就选 Keelhaven。

## Backblaze 电脑备份

最省事的方案：一份订阅，整台电脑，存在他们那里。宁愿花钱把这件事整个
交出去，就选它。

想自己决定数据放哪，或者手里已经有 NAS、有存储桶，就选 Keelhaven。

## restic

restic 是 Keelhaven 的引擎。如果一个 launchd 任务加上脚本里的密码就够你用，
那你不需要 Keelhaven。

它补上的是命令行工具留给你自己操心的部分：定时真的会跑，密钥放钥匙串，
出了问题会通知你。仓库仍然是原样的 restic 仓库，见
[写给 restic 用户](/zh/restic)。

## Backrest

同样是 restic 的前端，在浏览器里用。除了 Mac，它还能跑在 Linux、Docker
和 NAS 上，开放的 restic 功能也比 Keelhaven 多。给服务器用，或者每个参数
都想自己调，就选它。

一台不想操心的 Mac，就选 Keelhaven：原生应用，不用开浏览器，默认值已经是
对的。

## Vorta

和 Keelhaven 一样是桌面应用，引擎是 BorgBackup 而不是 restic。Borg 要的是
一块硬盘，或者一台能运行它的服务器，而不是一个普通的存储桶。已经在用 Borg
的话，就选它。
