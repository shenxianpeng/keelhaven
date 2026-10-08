---
title: 把 Mac 备份到 NAS
description: 用 Keelhaven 把 Mac 加密、定时备份到群晖、威联通或任何一台 NAS：在访达里挂载共享文件夹，或者用 SSH 密钥走 SFTP。
---

# 把 Mac 备份到 NAS

Keelhaven 先在你的 Mac 上把选中的文件夹加密，再存到 NAS 上。别人在 NAS 上
打开那个目录，看到的只有加密数据。

连 NAS 有两种办法。没用过 SSH 密钥的话，从第一种开始。

## 简单的办法：挂载共享文件夹

1. 在访达里选**前往 → 连接服务器…**，输入 `smb://` 加 NAS 的名字，比如
   `smb://nas.local`，然后打开用来放备份的共享文件夹。
2. 在 Keelhaven 里点菜单栏的灯塔图标，选**添加备份计划…**，挑好文件夹。
3. 到下一步，点**选取…**，选共享文件夹里的一个目录。它在边栏的**位置**下面。
4. 设好加密密码和备份频率。

备份运行时，共享文件夹必须处于挂载状态。没挂载的话，那一次会失败，
Keelhaven 会告诉你。数据不会丢：下一次会把上次成功之后的变化都补上。

## 不想挂载：走 SFTP

走 SFTP 的话，只要 NAS 在网络上，Keelhaven 自己就能连上。它用 SSH 密钥登录，
从不询问 NAS 的密码，所以得先保证密钥登录是通的。

**1. 先在终端里试一下。**

```bash
ssh backup@nas.local
```

这条命令必须不问密码、也不问密钥口令就能登进去。第一次连接时它会问是否
信任这台 NAS，在这里回答 yes，因为这个问题 Keelhaven 没法替你回答。

如果它问了密码，说明 NAS 上还没有你的公钥：

```bash
ssh-keygen -t ed25519        # 还没有密钥时才需要
ssh-copy-id backup@nas.local
```

**2. 接入 Keelhaven。** 在选目的地那一步展开**高级选项**，选 **SFTP / NAS**。

| 字段 | 填什么 |
|---|---|
| 用户名 | NAS 上的账号，比如 `backup` |
| 主机 | `nas.local`，或者它的 IP 地址 |
| 端口 | `22`，除非你改过 |
| 服务器上的路径 | 放这台 Mac 备份的目录，比如 `/backups/mac` |

然后同样是加密密码和备份频率。

### 群晖上要注意

- SFTP 默认是关的：**控制面板 → 文件服务 → FTP → 启动 SFTP 服务**。
- 密钥登录需要有个人文件夹来放公钥：**控制面板 → 用户与群组 → 高级设置 →
  启动家目录服务**。剩下的步骤看群晖的
  [密钥登录教程](https://kb.synology.com/en-uk/DSM/tutorial/How_to_log_in_to_DSM_with_key_pairs_as_admin_or_root_permission_via_SSH_on_computers)。
- 走 SFTP 时，群晖通常把共享文件夹直接列在最上层，所以路径是
  `/backups/mac`，而不是 `/volume1/backups/mac`。运行
  `sftp backup@nas.local` 再输入 `ls`，就能看到你那台显示的是什么。

## 值得知道

**放在同一个家里的 NAS 只算一份，不算两份。** 它防的是 Mac 坏掉，防不了
火灾和入室盗窃。再建一个计划备份到[存储桶](/zh/guides/backblaze-b2)就能
补上，**复制计划…** 可以把现有计划拷到新的目的地。

**不装 Keelhaven 也能恢复。** 那个目录里是标准的
[restic](https://restic.net) 仓库：

```bash
restic -r sftp:backup@nas.local:/backups/mac snapshots
```
