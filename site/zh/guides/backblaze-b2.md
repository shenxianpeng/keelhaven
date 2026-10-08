---
title: 把 Mac 备份到 Backblaze B2
description: 用 Keelhaven 把 Mac 加密、定时备份到你自己的 Backblaze B2 存储桶：建桶、建应用密钥、要填的五个字段，以及 B2 必须设的那条生命周期规则。
---

# 把 Mac 备份到 Backblaze B2

Keelhaven 先在你的 Mac 上把选中的文件夹加密，再传到属于你的 B2 存储桶。
Backblaze 存的是它读不了的数据，中间也没有 Keelhaven 的服务器。

全程大约十分钟，大部分花在 Backblaze 那边。

## 1. 建一个存储桶

在 Backblaze 网页控制台打开 **Buckets**，点 **Create a Bucket**。

- **Files in Bucket are：** 选 Private。
- **Object Lock：** 保持关闭。开了之后旧备份就永远删不掉。
- **Default Encryption：** 开不开都行。数据离开 Mac 之前已经加密过了。

建好后，存储桶上会显示一个 **Endpoint**，形如
`s3.us-west-004.backblazeb2.com`。第 4 步要用。

## 2. 设置生命周期规则

在这个存储桶上打开 **Lifecycle Settings**，选 **Keep only the last version
of the file**。

备份工具删掉的东西，B2 并不真删，而是隐藏起来继续计费。设了这一项，旧备份
才会真正从账单里消失。详细原因见[常见问题](/zh/#faq)。

## 3. 建一个应用密钥

打开 **Application Keys**，点 **Add a New Application Key**。

- **Allow access to Bucket(s)：** 选刚建的那个存储桶。
- **Type of Access：** Read and Write。
- **Allow List All Bucket Names：** 勾上。只限单个存储桶的密钥走 S3 接口时，
  Backblaze 要求打开它。

之后会显示一个 **keyID** 和一个 **applicationKey**。applicationKey 只显示
这一次，两个都马上复制下来。

页面顶部的 master application key 用不了：B2 的 S3 接口只认这样新建的密钥。

## 4. 接入 Keelhaven

点菜单栏里的灯塔图标，选**添加备份计划…**，挑好文件夹。到下一步，展开
**高级选项**，选 **S3 兼容存储**。

| 字段 | 填什么 |
|---|---|
| 服务地址 | 第 1 步的 Endpoint |
| 存储桶 | 存储桶的名字 |
| 路径前缀 | 可不填。桶里的一个子目录，比如 `macbook` |
| Access Key ID | keyID |
| Secret Access Key | applicationKey |

然后设一个加密密码，或者让 Keelhaven 自动生成。密码存在钥匙串里，最好也
存一份进密码管理器。没有它，谁都读不了这份备份，包括你自己。

## 5. 选备份频率

每小时、每天或每周。第一次备份会上传全部内容，之后每次只传有变化的部分。

## 值得知道

**第一次上传可以限速。** 最后一步的**自定义这个计划**里有上传限速，之后在
**编辑计划 → 高级**里也能改，免得首次备份占满你的网络。

**不设置的话，备份会一直增长。** 删不删你的数据，Keelhaven 从不替你做主，
所以保留策略默认是关的。要开，去**编辑计划 → 保留策略**。

**不装 Keelhaven 也能恢复。** 存储桶里是标准的 [restic](https://restic.net)
仓库：

```bash
restic -r s3:https://s3.us-west-004.backblazeb2.com/your-bucket snapshots
```

## 换一家 S3 服务

五个字段在哪家都一样，只有服务地址不同。第 2 步的生命周期规则只是 B2 的事。

| 服务商 | 服务地址 |
|---|---|
| Amazon S3 | `s3.amazonaws.com` |
| Cloudflare R2 | `<account-id>.r2.cloudflarestorage.com` |
| Wasabi | `s3.<region>.wasabisys.com` |
| MinIO 或其他自建服务 | `https://your-host:9000` |
