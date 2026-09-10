# Keelhaven 差距分析与下一步计划

> 生成于 2026-09-10 · 分析方式：仓库与代码实测 + CI/发布数据 + 外部竞品与社区调研
> 核心原则（来自你）：**如无必要，勿增实体** — 小而精。

---

## 1. 执行摘要

**一句话判断：这个项目不缺功能，也不缺工程质量；它缺的是「信任」，以及一个会说实话的失败路径。**

先把家底摆出来（都是实测，不是印象）：

| 指标 | 数值 |
|---|---|
| 代码周期 | 2026-08-26 → 09-09，**15 天** |
| 提交 / 发布 | **119 commits / 9 个 release**（v0.1.0 → v0.8.0） |
| KeelhavenCore | 1,890 行，**169 个测试全绿**（本机实跑），CI 强制 **100% 行覆盖** |
| App target | 4,668 行 |
| Star / Fork | **19 / 2** |
| 单版本下载量 | **3–15**（v0.8.0 = 7）；全部 release 合计约 77 |
| 网站流量（14 天） | 724 浏览 / **53 独立访客** |
| 流量来源 | v2ex、meta.appinn.net、lewuxian.com、t.co — 基本全是中国技术社区 |
| 未关闭 issue | **5 个**，其中 2 个是真实需求（#74、#61），3 个是「记录但不排期」（#44、#45、#53） |

工程质量这一侧，这个项目已经超过绝大多数 19 star 的项目：fixture 驱动的 restic 解析、100% 行覆盖门禁、三种真后端的集成测试（MinIO / sshd / rest-server）、密钥只走子进程环境、GPL + BSD 双许可声明齐备、EN/中文站点同步（我核对过：两边各 16 个 FAQ、4 个 VoiceCard，完全对齐）。**这些都不需要再改进。**

问题在另一侧。我用真实 restic 0.19.1 做了一次实验，发现核心承诺上有一个洞：

```
$ restic backup ~/src --json        # 其中一个文件 chmod 000
EXIT CODE = 3
stderr: {"message_type":"error","error":{"message":"open …/b.txt: permission denied"},"during":"archival","item":"…/b.txt"}
        {"message_type":"exit_error","code":3,"message":"Warning: at least one source file could not be read"}
snapshots: 1                        # ← 注意：快照照样写进去了，但缺文件
```

而 Keelhaven 这边：

- `exit code 3` 没有专门分类，落到 `commandFailed(exitCode: 3, …)`，用户看到的是「Backup command failed (exit code 3)」+ 一句 restic 的英文（`ResticError.swift:60`）；
- **哪个文件读不到，被丢掉了** — runner 只从 stderr 取最后一条 `exit_error` 当消息（`ResticError.swift:29-35`），逐文件的 `message_type:"error"` 从来没人读；
- `ResticJSON.decodeProgressEvent` 只认 `status` / `summary`，其他 message_type 一律返回 nil（`ResticMessage.swift:252-259`）；
- **全仓库（app + site + 文档）没有任何一处提到 Full Disk Access 或权限**（我 grep 过 `*.swift / *.md / *.xcstrings / *.mts / *.vue / *.yml`）；
- 那个「不完整快照」在恢复窗口里和一 个好快照长得一模一样。

在 macOS 上这不是边缘情况：`~/Desktop`、`~/Documents`、`~/Downloads`、iCloud Drive、`~/Library/Mail|Messages` 都受 TCC 保护，而**第一次用备份 App 的人，选的就是这些文件夹**。这就是「前十分钟」的体验。

所以下面这份计划的主题不是「再加什么」，而是：**把已有的东西变真，再把门打开。**

### 三个最大的缺口

1. **失败不说真话**（P0）— 权限问题、部分失败、不完整快照，全是已存在的功能，但报错含糊、细节丢失。不需要新功能，只需要把已有实体修对。
2. **首启的信任门槛**（P1）— 自家 FAQ 第一条就是「macOS 说无法验证 Keelhaven」。对一个要拿 Keychain 密码、S3 密钥和全盘读取权限的 App，这是转化率杀手；而且它还是拿 FDA 的前提。
3. **恢复不完整**（P2）— 只能整快照恢复。竞品全都有文件级浏览；社区最强的诉求也是它。但它是**大实体**，要放在 P0/P1 之后，并且严格限制范围。

### 最大的单一机会

**Full Disk Access 是 restic 命令行生态五年没解决的问题，而一个已签名 + 公证的 `.app` 正好是 macOS 唯一愿意授予 FDA 的对象。** restic 论坛从 2020 年吵到 2025 年 macOS 15.6，结论都是「得把脚本包成 App、再自签名」或者「只能给 bash 开 FDA，我不喜欢但没别的办法」（[restic forum](https://forum.restic.net/t/fixing-backups-in-macos-mojave-catalina-operation-not-permitted/2848)、[launchd 帖](https://forum.restic.net/t/can-restic-backup-macos-photos-library-from-launchd/7150)）。Backrest 现在也做不到。

Keelhaven 天生就是那个正确的形状 —— **但它既没把这件事写进产品，也没写进网站，代码里甚至还不能正确报告失败。** 这就是 1.0 的故事。

---

## 2. 项目评分：81 / 100

| 维度 | 得分 | 权重 | 加权 |
|---|---|---|---|
| 功能完整度 Functional | 26/35 | 35% | 26.0 |
| 代码质量 Code Quality | 23/25 | 25% | 23.0 |
| 文档质量 Documentation | 18/20 | 20% | 18.0 |
| 用户体验 UX | 14/20 | 20% | 14.0 |
| **合计** | | | **81.0 / 100** |

**功能 26/35** — 它自己声明的 v1 范围（引擎、向导、定时、整快照恢复、定期校验、保留预设）全都真实可用，且有测试。扣分在三处承诺与实现之间的缝：文件级恢复还差（README 自己说 "next"）、失败信息不足以让人采取行动、不完整快照无法辨认。另外功能面已经开始超出「小而精」：4 种目的地、4 种保留、7 个具名 restic 开关、dry-run 预览、计划复制、Touch ID……

**代码 23/25** — 分层干净（Core 无 UI、App 只放视图与系统框架薄封装），fixture 驱动解析、169 测试、100% 行覆盖门禁、密钥不落盘不落 argv。扣 2 分给 `exit 3` 这条真实世界最高频的路径没有 fixture、没有专门测试（`ResticRunnerProcessTests.swift:128` 现在把 3 断言成通用的 `commandFailed`，改的时候要一起改），以及 stderr 在成功路径上被整体丢弃。

**文档 18/20** — 对一个 beta 来说异常完备：16 条 FAQ、中英双语、ARCHITECTURE 里连「为什么不用 launchd」都写了、RELEASING/WEBSITE/CONTRIBUTING 齐全、许可声明干净。扣分只因为**缺最该有的那一条**：权限/Full Disk Access 的排查指引，以及「恢复演练」的文档。

**体验 14/20** — 菜单栏交互和文案水准很高（菜单栏 demo 是用 SwiftUI 源码重画的，不是截图，诚实）。但首启是一道 Gatekeeper 关卡（未公证），而最可能出现的第一次失败给出的是一句没有细节的英文错误。这两件事恰好都发生在用户决定「要不要信它」的那五分钟里。

---

## 3. 竞争格局

直接竞品很少，间接竞品极其拥挤。**「macOS 原生菜单栏 + restic GUI」这个位置是空的，但空得更像「需求未被验证」而不是「蓝海」。**

| 竞品 | 价格 | 文件级恢复 | 相对 Keelhaven 的优势 |
|---|---|---|---|
| **Arq 7** | $59.99/机 买断 | ✅ 可浏览历史 | 多目的地、APFS 快照、Wi-Fi/电量感知排期、2009 年就在 |
| **Carbon Copy Cloner 7** | ~€45 买断 | ✅ Snapshot Navigator + 搜索 | 快照浏览器、历史校验和比对、可启动克隆 |
| **Time Machine** | 免费内置 | ✅ Finder 直接浏览 | 系统级、零首启摩擦、整机恢复 |
| **Backblaze Personal** | ~$99/年 | ✅ 含网页恢复 | 无限量、寄 U 盘恢复 |
| **Backrest**（同为 restic） | 免费 | ✅ 浏览 + 恢复单文件 | rclone 远程、cron、hooks、企业级通知；但主界面是 localhost 网页，且需要 FDA |
| **Restic Browser** | 免费 MIT | ✅ 浏览 / dump / 选择性恢复 | 只做恢复，与 Keelhaven 互补；可作「替代品」被引用 |
| **Kopia / KopiaUI** | 免费 | ✅ | 后端多、压缩、策略、CLI 出口 |
| **Vorta（Borg）** | 免费 GPL | ✅ FUSE 挂载 | 自定义 prune、远程配置 |

三条结论：

1. **Keelhaven 真正的差异点是「restic + 密钥只进 Keychain + 原生菜单栏 + 免费无账号」**，这四件 Backrest 一件都不占（配置在 `config.json`、浏览器 UI、需要 FDA）。这是可以守住的楔子，但网站现在的叙述没有把它当主线。
2. **最大的可信度缺口是未公证**，不是缺功能。付费竞品和 Time Machine 都不弹那个框；免费替代品都能用 Homebrew 无痛装上。自家 FAQ 第一条就在教用户怎么绕过 macOS 的警告 —— 对一个备份工具，这句话的杀伤力比缺一个功能大得多。
3. **唯一能改变对比表的缺失功能是快照内文件浏览 / 选择性恢复**。几乎所有竞品都把它当卖点，而且它的两个难点（restic JSON 解析管线、恢复路径）Keelhaven 都已经有了。公证是「移除了一个反对理由」，文件浏览是「赢得一次比较」。

---

## 4. 真实需求信号

（调研覆盖 V2EX、小众软件、少数派、restic 官方论坛、r/macapps、HN、MPU Talk、TidBITS、Ars；即刻 / 什么值得买 / 知乎 评论区**没有可用信号**，如实说明。）

### 排名第一：恢复才是短板（信号强，4 个独立社区）

- HN 上 231 分的 restic 帖，一位用户的头号抱怨：「唯一缺的就是能像浏览普通文件一样浏览历史快照」（[HN](https://news.ycombinator.com/item?id=41829913)）
- r/macapps 对 Parachute 的评测，第一条改进建议就是「实现一键恢复，现在只能手动」（[r/macapps](https://www.reddit.com/r/macapps/comments/1pmc8jq/parachute_backup_specially_designed_for_icloud/)）
- restic 论坛 Resty 帖子把「浏览快照内文件、恢复单个条目而不是整个快照」列为头号功能（[restic forum](https://forum.restic.net/t/resty-desktop-gui-for-restic/10881)）
- Arq 恢复时 OOM + 重复取回产生约 100 美元费用的实例（[mjtsai](https://mjtsai.com/blog/2026/05/07/arq-restore-notes/)）
- 你自家 FAQ 也已经承认了这一点（「它恢复的是整个快照，还不能展开快照、只挑其中一个文件出来」）

**含义：这不是「再加一个功能」，这是把产品补完整。但它是大实体，排在 P0/P1 之后。**

### 排名第二：权限 / Full Disk Access —— 你已经解决了，却一个字都没写（信号强，且直指本产品）

- restic 论坛那条帖子从 2020 年活到 2025 年，最后停在 macOS 15.6 Sequoia 的 `operation not permitted`；结论是「命令行程序无法自己申请这种权限，必须被包成 App」（[restic forum](https://forum.restic.net/t/fixing-backups-in-macos-mojave-catalina-operation-not-permitted/2848)）
- 实际在用的办法全是很脏的 hack：Platypus 包一层、再用自签名证书签一次；或者「给 bash 开完全磁盘访问权限，我不喜欢，但想不到更好的」（[restic forum](https://forum.restic.net/t/can-restic-backup-macos-photos-library-from-launchd/7150)）
- Backrest 用户的原话是「现在用了 backrest，我连把 restic 包进 App 这条路都没法走了」
- **而 Keelhaven 的 app、网站、文档里对 FDA 零提及**（我 grep 过），你还多花了一条 FAQ 去解释「为什么不在 Mac App Store」，却没顺手说出「所以它是那个能被授予 FDA 的 .app」

**含义：这是免费的市场位置，也是产品现在最该补的一课 —— 先让它真的能报告权限失败，然后把它讲出来。**

### 排名第三：小工具的「持续性信任」（信号强）

- Mac 开发者原话：「用户其实不担心公司变动，他们担心的是：会不会改订阅制、本地格式能不能活、出事的时候还有没有人在」（[r/macapps](https://www.reddit.com/r/macapps/comments/1s7mrsx/parachute_backup_has_been_sold/)）
- V2EX 用户直接质问开发者：「如果存了很多快照，脱离你这个 app，能有别的办法手动删吗？我怕遇到 bug 时没法应急」（[V2EX](https://global.v2ex.co/t/1164537)）
- MPU Talk 的检查清单：几千 star、活跃开发、r/macapps 上有人提过；「完全没人提？那这 App 一定很冷门」（[MPU Talk](https://talk.macpowerusers.com/t/installing-foss-github-apps-on-macos-any-precautions/46321)）
- 少数派的方法论恰好**反转了 star 数**这条：星标「可以表示任何含义，最简单的方式就是不看」，要看的是维护时长、发布节奏、作者背景、文档质量（[少数派](https://sspai.com/prime/story/foss-how-to-select)）

**含义：英文社区的入场券是 star 数和 r/macapps 提及；中文社区的门票是作者履历、持续维护、文档质量 —— 后面这张票你已经有了，只是还没递出去。**

### 不是功能的最大障碍

**没有任何第三方证据证明 Keelhaven 存在、能用、会活下去。** 19 star、每版个位数下载、r/macapps 与 HN 零提及。叠加「未公证 + 一个人 + AI 时代对 vibe coding 的敌意」，谨慎用户的默认答案是先不装。

### 最可能带来口碑的一件事

写一篇**技术帖而不是发布公告**：讲 macOS 上 restic 的 `permission denied` / FDA 这个结构性坑，以及为什么需要一个（已公证的）`.app` 才能真正拿到授权。发在 restic 官方论坛和 r/macapps，作者身份明示。

证据：restic 论坛是 GUI 需求人群的聚集地，Resty Desktop 的帖子里作者的自荐被欢迎并换来九轮详细的 macOS/Linux 测试反馈（[restic forum](https://forum.restic.net/t/resty-desktop-gui-for-restic/10881)）；r/macapps 的所有高互动备份帖都是作者在评论区逐条回复。中文侧还有一张现成的牌：你在小众软件的帖子里唯一一条实质回复要的是 REST server 目的地（[appinn](https://meta.appinn.net/t/topic/91304)）—— **那个功能已经发布了，「你要的，上了」是个比重新发布好得多的故事。**

**前提：P0 必须先做完。** 否则你发出去的帖子讲的是「我们也有这个问题」。

---

## 5. 优先级判断（三条信号的交点）

| 差距 | 内部弱项 | 竞品压力 | 社区拉力 | 工作量 | 结论 |
|---|---|---|---|---|---|
| 权限与部分失败的真实性（P0） | 高（exit 3 无处理、细节丢失、无 FDA 文档） | 中 | 高（5 年老问题） | **S** | **立刻做** |
| 未公证 / 首启信任（P1） | 高（自家 FAQ 第一条就在道歉） | **高**（付费竞品全不弹框） | **高**（信任是首要决策） | **S**（$99/年 + 填 secret） | **立刻做** |
| 快照内文件浏览 / 选择性恢复（P2） | 高（README 自认 next） | **高**（全员都有） | **高**（4 社区共识） | **M** | **1.0 前做，但严格限范围** |
| 功能面继续膨胀（7 个具名字段、4 目的地…） | 中 | 低 | 低（#45 是收集帖） | — | **冻结** |
| 全局配置 / 全局排除（#74） | 低 | 低 | 低（1 人提出） | M | **暂缓**（引入第二个配置真源） |
| 导出 / 导入（#44） | 低 | 低 | 低 | L | **暂缓**（障碍 issue 里已写清） |
| rclone 后端（#53） | 低 | 中 | 低 | L | **不做**（理由已记录） |

---

## 6. 行动计划

### 先给 1.0 下一个定义

> **一个普通人能在 10 分钟内完成「装 → 授权 → 备份 → 取回一个文件」，且每一步失败都说得出原因。**

这个定义让「小而精」可执行：凡是与此无关的功能，1.0 之前都不做。

---

### 第 0 步 · 零代码（今天，30 分钟）

- **#74 的一半已经做完了**：版本更新检查早在 `UpdateChecker.swift` 里，`latest.json` 线上是 `0.8.0`（我 curl 过），菜单栏面板里会显示「New version … available」（`MenuBarView.swift:64`）。回帖告诉他，顺手把这条从 issue 里划掉。
- #61 回帖：文件浏览会做，快照删除暂不做（保留预设已经覆盖删除策略，且删除是破坏性操作）。
- 这一步不写一行代码，直接减少你的 issue 欠债。

### P0 · 让失败说真话（S：1–2 天，约 300 行 + 测试）

全部是修已有实体，**不引入任何新概念**：

1. **Core 分类**：`ResticError` 增加 `.someSourcesUnreadable(items:[String], message:String)`，`classify` 映射 exit code 3；并从 stderr 里**收集所有** `message_type:"error"` 行的 `item` / `error.message`（现在只取最后一条 exit_error，前面的全扔）。
2. **补 fixture**：用真实 restic 0.19.1 跑一次带不可读文件的 `backup --json`，把原始输出存进 Fixtures（我已在本机复现，上面的输出就是原始形态）。补测试，保证 100% 覆盖门禁不破。`ResticRunnerProcessTests.swift:128` 现有的「3 → commandFailed」断言要一起改。
3. **UI 翻译**：exit 3 的文案要说人话 —— 「N 个文件读不到，可能是 macOS 权限」+ 列出前几个路径 + 一个按钮直接打开「系统设置 › 隐私与安全性 › 完全磁盘访问权限」。
4. **事前预检（这一条价值最高）**：保存计划或首次运行时，对 `sourcePaths` 做一次可读性预检；命中 Desktop / Documents / Downloads / iCloud Drive 等 TCC 保护位置时，**在备份跑之前**就引导授权，而不是等它跑完给你一句英文报错。
5. **恢复窗口标注不完整快照**：run record 里已经有 `snapshotID` 和 `success`，用它把部分失败的快照标出来，别让用户在不知情的快照上做恢复。

**验收**：在 `~/Documents` 放一个 chmod 000 的文件跑一次，App 说的是「1 个文件读不到：<路径>，可能是完全磁盘访问权限」，而不是「exit code 3」。

### P1 · 拆掉首启的路障（S：$99/年 + 半天）

- 加入 Apple Developer Program，拿 Developer ID Application 证书。
- **管道已经写好了**：`release.yml` 里签名/公证是可选分支，不加 secret 就 ad-hoc 签名 —— 填上 secret 即自动生效。App Sandbox 关着不影响公证（hardened runtime 已开）。
- 做完顺手删掉这些「道歉文案」，EN 与中文两版一起改：
  - `site/index.md` 与 `site/zh/index.md` 的「macOS 说无法验证 Keelhaven」FAQ（16 条里删 1 条）
  - README 的「第一次启动需要一次性批准」
  - 站点 hero 里 install 的 note（「装完直接能开，不弹任何安全提示」现在只对 Homebrew 成立）
- 这也是 P0 第 4 条能真正生效的前提：**只有签过名、公证过的 `.app` 才是 macOS 愿意授予 FDA 的对象。**

### P2 · 让「取回一个文件」成立（M：3–5 天，严格限范围）

- 你**已经有数据**了：`Scripts/bench-remote-ls.sh` 就是为「快照浏览该怎么建」而写的，专门在注入 RTT 的 S3/SFTP 上量 `restic ls` 的延迟。先用它定实现形态（一次 `ls` 全量取回 vs 按需展开），别猜。
- **只做**：快照内文件列表 + 搜索 + 勾选恢复所选（`restore --include`）。
- **明确不做**（这是「小而精」的代价）：FUSE 挂载（macOS 上要装内核扩展，本目标人群明确反感）、跨快照搜索（Resty 的差异点，让给它）、快照删除、快照间 diff、拖拽。
- 顺带把 `docs/ARCHITECTURE.md` 的「Not yet built (deliberately)」和 README 的 status 一并更新 —— 你自己定的规矩是两处必须同步。

### P3 · 去讲这个故事（S–M，P0+P1 完成后）

- 技术帖（不是发布公告）：《macOS 上 restic 的 permission denied，以及为什么它需要一个公证过的 .app》，发 restic 官方论坛 + r/macapps，明示作者身份、在评论区回答。
- 中文：回小众软件原帖「你要的 REST server 已经上了」，附 issue 链接。
- 网站叙事换主线：现在 hero 讲的是「隐私优先的备份」，建议改成你真正的楔子 —— **「那个能拿到完全磁盘访问权限、并且会在读不到文件时告诉你哪个文件的 restic 客户端」**。同时把「标准 restic 格式 / 无账号 / GPL」从 FAQ 深处提到前面（社区里「脱离 App 能不能自己恢复」是明确被问到的）。
- **别提「替代 Time Machine」** —— 你的 FAQ 现在说得对，保持住；社区里的人都是故意同时跑三套的。

### 发布纪律

- 15 天 9 个 release，Actions 额度已经烧穿过一次（`ci.yml` 的注释就是证据）。**到 1.0 之前只发 1–2 个版本**，把力气放在上面四步。
- **Advanced 里的具名字段冻结**：不再新增 restic flag 字段。#45 保持「收集不实现」，新需求一律走「具名字段 + 校验 + 测试」的既有模式，且排到 1.0 之后。

### 明确不做清单（写进文档，别再讨论）

- rclone 后端（#53 理由已充分：凭据在 App 之外，破坏密钥模型）
- 全局配置 / 全局排除（#74）：会引入第二个配置真源和合并语义；「复制计划」（#62 刚做完）已经覆盖了大部分场景，1.0 后再谈
- 导出 / 导入（#44）：障碍（密钥、绝对路径、UUID、schema 版本）issue 里已经列全，post-1.0
- 自定义保留 keep counts、launchd 调度、沙箱、FUSE 挂载、Mac App Store、更多目的地类型

---

## 附：本报告中经实测验证的事实

- `restic 0.19.1`：存在不可读文件时 **exit code 3**，**快照仍会写入**；逐文件错误在 stderr 上以 `{"message_type":"error",…,"item":…}` 输出。
- Keelhaven `ResticError.classify` 没有 code 3 分支；stderr 只取最后一条 `exit_error` 作为消息。
- `ResticJSON.decodeProgressEvent` 丢弃 `status` / `summary` 以外的所有 message_type。
- 全仓库 `*.swift / *.md / *.xcstrings / *.mts / *.vue / *.yml` 中 **无** "Full Disk Access" 或权限相关文案。
- `swift test --package-path KeelhavenCore`：169 tests，3 skipped（本地缺真后端的集成套件），0 failures。
- `https://keelhaven.app/latest.json` 线上为 `0.8.0`（仓库里那份 0.1.0 是 gitignored 的构建残留，不是 bug）。
- `site/index.md` 与 `site/zh/index.md`：16 FAQ / 6 section / 4 VoiceCard，完全对齐。
- 未验证项：Arq / CCC / Backblaze 的公证状态未能从一手来源确认；CCC 价格是欧元区报价。竞品价格仅供量级参考。
