---
layout: page
navbar: false
footer: false

# site/index.md 的简体中文版。结构与英文版逐段对应：改动英文文案时，
# 请同步这里（反之亦然）。中文不逐字直译，以读起来像中文为准。
# 所有组件文案都住在这份 frontmatter 里。
landing:
  # 支持邮箱只写在这一处。它是 keelhaven.app 上的 Cloudflare Email
  # Routing 别名，转发到真实邮箱，可随时改指向而不用动网站。
  contact: support@keelhaven.app
  # 仓库地址，导航图标和页脚的 GitHub 链接都读它。默认主题页面
  # （/zh/privacy、/zh/licenses）经由 config.mts 的 themeConfig.socialLinks
  # 另行携带。
  github: https://github.com/shenxianpeng/keelhaven
  cta: 下载
  # 导航用短标签（FAQ 而非「常见问题」），配合语言切换按钮才放得进
  # 375px 的手机导航胶囊；页内区块标题和页脚仍用中文全称。
  nav:
    - { text: 功能, anchor: features }
    - { text: 指南, anchor: guide }
    - { text: 定价, anchor: pricing }
    - { text: 评价, anchor: voices }
    - { text: FAQ, anchor: faq }
  footer:
    tagline: 隐私优先的 Mac 备份。
    versionNote: 公开测试版
    copyright: © shenxianpeng.
    groups:
      - title: 支持
        links:
          - { text: 邮件支持, mailto: true }
          - { text: 常见问题, anchor: faq }
          - { text: 在 X 上关注, href: "https://x.com/xianpengshen" }
      - title: 产品
        links:
          - { text: 功能, anchor: features }
          - { text: 快速上手, anchor: guide }
          - { text: 定价, anchor: pricing }
          - { text: GitHub 源码, github: true }
      - title: 法律
        links:
          - { text: 隐私, link: /zh/privacy }
          - { text: 许可, link: /zh/licenses }
  # 演示动画的界面文案，取自 App 自带的简体中文本地化
  # （Keelhaven/Localizable.xcstrings），保证演示与真实应用一字不差。
  demo:
    ariaLabel: Keelhaven 菜单栏应用执行备份的动画演示：名为「文稿」的计划备份到外置硬盘，运行时只显示一个小小的进度条，然后弹出「备份完成」通知。
    clock: 周一 9:41
    plan1Name: 文稿
    plan1Sched: 每天 9:00
    plan1StatusIdle: 2 小时前完成备份
    plan1StatusDone: 1 秒钟前完成备份
    plan2Name: 照片
    plan2Sched: 每小时
    plan2Status: 26 分钟前完成备份
    backUpNow: 立即备份
    addPlan: 添加备份计划…
    startAtLogin: 开机时自动启动
    quit: 退出 Keelhaven
    notifTitle: 备份完成
    notifBody: 文稿：新增 12 个文件，共 48 MB。
---

<script setup>
import { computed } from 'vue'
import { useData } from 'vitepress'

const { frontmatter } = useData()
const releases = computed(
  () => `${frontmatter.value.landing.github}/releases/latest`
)
</script>

<!-- 下载按钮是活的：/latest.json 解析成功前指向 GitHub Releases 页，
     解析后换成 DMG 直链。 -->

<div class="kh-landing">

<LandingNav />

<section id="top" class="kh-hero">
  <!-- CJK 允许在任意字符间断行，nowrap 保证「Mac 备份」不被拆成「备/份」；
       span 前的普通空格让换行点落在「的」之后。 -->
  <h1 class="kh-hero-title">隐私优先的 <span style="white-space: nowrap">Mac 备份</span></h1>
  <p class="kh-hero-tagline">安静的菜单栏应用。把最在乎的文件夹先在 Mac 上加密，再按时间表备份到你自己的硬盘、NAS 或云端。</p>
  <p class="kh-hero-facts">
    <span>macOS 14+</span>
    <span>免费开源</span>
    <span>无遥测</span>
    <span>开源工具即可恢复</span>
  </p>
  <div class="kh-hero-actions">
    <CommandBlock
      command="brew install --cask shenxianpeng/tap/keelhaven"
      note="一行命令，装完直接能开，不弹任何安全提示。"
      copy-label="复制"
      copied-label="已复制"
    />
    <p class="kh-hero-alt">
      <DownloadButton label="下载 .dmg" :fallback-href="releases" ghost />
      <a class="kh-btn kh-btn-ghost" href="#guide">先看指南</a>
    </p>
  </div>
</section>

<LandingSection id="tour" eyebrow="00 · 看一眼" title="一个菜单栏图标，就是整个应用。">

<!-- MenuBarDemo 是弹窗界面的动画复刻，按 SwiftUI 源码绘制而非截图，
     保证展示的和应用实际拥有的一致——包括那个安静的、不报数字的进度条。 -->
<ShotFrame><MenuBarDemo /></ShotFrame>

</LandingSection>

<LandingSection id="features" eyebrow="01 · 功能" title="装完就忘">

<div class="kh-feature-grid">
<div class="kh-feature">

### 隐私为本

数据离开 Mac 前就已加密。密码只存在 macOS 钥匙串里，不落盘、不进日志。

</div>
<div class="kh-feature">

### 不打扰

住在菜单栏里，没有 Dock 图标，也没有窗口要管。定好时间表，就不用再想起它。

</div>
<div class="kh-feature">

### 无锁定

备份是标准的开放格式，在任何机器上用免费的开源工具都能恢复，装没装 Keelhaven 都一样。

</div>
<div class="kh-feature">

### 时间表说到做到

每小时、每天或每周，选好星期和时间，之后的备份 Keelhaven 一次都不会落下。

</div>
</div>

</LandingSection>

<LandingSection id="guide" eyebrow="02 · 指南" title="决定三件事，剩下不用管">

<ol class="kh-steps">
<li>

### 挑几个文件夹

挑出丢不起的那些：文稿、照片、项目。

</li>
<li>

### 选个自己的地方存

外置硬盘、NAS，或任何兼容 S3 的存储桶。中间没有 Keelhaven 的服务器。

</li>
<li>

### 定个时间表

每小时、每天或每周。Keelhaven 在后台运行，出了问题才会叫你。

</li>
</ol>

<div class="kh-guide-note">

macOS 14 及以上，Apple 芯片和 Intel 都行，所有依赖都打包在应用里。喜欢终端的话，下面两条命令装的和下载按钮是同一个应用：

<div class="kh-install">
  <div class="kh-install-row"><span class="kh-install-label">用 Homebrew</span><code>brew install --cask shenxianpeng/tap/keelhaven</code></div>
  <div class="kh-install-row"><span class="kh-install-label">不用 Homebrew</span><code>curl -fsSL https://keelhaven.app/install.sh | bash</code></div>
</div>

Beta 版还没做 Apple 公证，第一次打开要多点一次确认，[下面的 FAQ](#faq) 三步讲清。

</div>

</LandingSection>

<LandingSection id="pricing" eyebrow="03 · 定价" title="免费。这就是全部定价。">

<PricingCard>
<template #price><span class="kh-badge">免费且开源</span></template>
<template #note>Beta 免费，1.0 之后也免费。没有订阅，没有账号，也没有任何附加条件。</template>

- 备份计划和目的地数量不限
- 通用构建，Apple 芯片和 Intel 都支持
- 备份引擎已内置，不用再装任何东西
- 没有账号，没有遥测，中间没有我们的服务器

</PricingCard>

</LandingSection>

<LandingSection id="voices" eyebrow="04 · 评价" title="别人怎么说">

<div class="kh-voices">
<VoiceCard name="小弟调调" handle="@jaywcjlove" source="X" href="https://x.com/jaywcjlove/status/2096527566400352339">

无 Dock 图标，没有主窗口。选定文件夹、备份存储介质、定时策略，后台静默执行，出错才推送通知。密码仅保存在 macOS 钥匙串，生成标准 restic 仓库，脱离本软件也能用 restic 命令行恢复。

</VoiceCard>
<VoiceCard name="mao mao" handle="@maomao000211" source="X" href="https://x.com/maomao000211/status/2095382774874267938" note="译自英文">

思路很对，restic 配上菜单栏界面，正好补上了缺的那一块。仓库保持标准格式，用户就不会被你的软件绑住。不要账号、不做遥测，光这一条就够说服不少人了。

</VoiceCard>
</div>

</LandingSection>

<LandingSection id="faq" eyebrow="05 · 常见问题" title="不绕弯子的回答">

<FaqItem question="macOS 说无法验证 Keelhaven，是出问题了吗？">

没出问题。Beta 版还没做 Apple 公证，macOS 对所有没法在线验证的应用都会弹这个警告。允许一次，同一版本就不会再问：

- **macOS 15（Sequoia）：** 先双击一次 Keelhaven，关掉警告；再打开**系统设置 › 隐私与安全性**，拉到底部，点**仍要打开**。
- **macOS 14（Sonoma）：** 在「应用程序」里右键点按 Keelhaven，选**打开**，再点一次**打开**。
- **偏好终端？** `xattr -d com.apple.quarantine /Applications/Keelhaven.app` 一条命令清掉隔离标记，连对话框都不会弹。

</FaqItem>
<FaqItem question="能取代时间机器（Time Machine）吗？">

不能，两个一起用。时间机器擅长把整台 Mac 恢复原样，用的是桌上那块硬盘；Keelhaven 管的是第二份副本：丢不起的那些文件夹，加密后放到别的地方。

</FaqItem>
<FaqItem question="免费的，会不会有什么套路？">

没有套路。Keelhaven 的备份引擎是 [restic](https://restic.net)，免费、开源、久经考验；Keelhaven 补上命令行工具留给用户自己操心的部分：定时真的会跑，密码放钥匙串、不落盘不进日志，菜单栏没事不吭声。它没有服务器要养，背后也没有公司，整个项目开源，不需要商业模式也能活下去。要是它在你的 Mac 上站住了脚，向朋友推荐一句，就是对它最好的支持。

</FaqItem>
<FaqItem question="会被 Keelhaven 锁定吗？">

不会。每个计划写入的都是标准 restic 仓库，在任何 Mac 或 Linux 上用开源的 restic 命令行就能列出、校验、恢复，不需要装 Keelhaven。哪天 Keelhaven 没了，你的备份还在。

</FaqItem>
<FaqItem question="Keelhaven 开源吗？">

开源，GPLv3，代码在 [GitHub](https://github.com/shenxianpeng/keelhaven)：想读、想审计、想自己编译、想 fork 都行。内置的 restic 引擎是 BSD 2-Clause 许可，两份声明见[许可页](/zh/licenses)。

</FaqItem>
<FaqItem question="别人能读到我的数据吗？">

读不到。所有内容上传前就在你的 Mac 上加密完成，仓库密码只在你的钥匙串里。没有服务器、没有账号、没有遥测，这个应用就算想发数据，也没有地方可发。

</FaqItem>
<FaqItem question="支持哪些备份目的地？">

挂在 Mac 上的外置硬盘或网络硬盘；任何兼容 S3 的存储桶（AWS、Backblaze B2、Wasabi、Cloudflare R2、MinIO）；用 SFTP 连自己的服务器或 NAS；以及你自己架设的 [restic REST server](https://github.com/restic/rest-server)。

</FaqItem>
<FaqItem question="备份会一直涨下去吗？">

默认会，因为删你的数据这件事，Keelhaven 从不自作主张。每次运行加一个去重后的快照，只存变化的部分。想让某个计划别再涨，在「编辑计划」里选一档保留策略，保留一年或保留一个月，较旧的快照就会按每日、每周、每月逐级精简，空间在备份完成后回收，每周最多清一次。仓库始终是标准 restic 格式，想自己用 `restic forget --prune` 按别的策略清，随时可以。

</FaqItem>
<FaqItem question="我怎么知道备份真的能用？">

备份失败或没跑完不会悄无声息，引擎报的错会立刻出现在菜单栏和系统通知里。Keelhaven 还会定期用 restic 自带的完整性检查验证仓库，默认每周一次，可按计划调整；通过了就在计划行里安静记一条「已验证」，有问题才会吵你。当然，隔三差五真恢复一个文件出来，才是检验备份的金标准，用什么工具都一样。

</FaqItem>
<FaqItem question="还需要装别的东西吗？">

不用。Keelhaven 需要的都在应用包里，包括备份引擎：没有第二步安装，不依赖 Homebrew，也没有要你自己保持更新的组件。

</FaqItem>
<FaqItem question="能在终端安装吗？">

能，两种方式，装的都是下载按钮那个 DMG。有 Homebrew：`brew install --cask shenxianpeng/tap/keelhaven`，以后 `brew upgrade` 自动跟进新版本。没有：`curl -fsSL https://keelhaven.app/install.sh | bash` 下载最新版并拷进「应用程序」。[脚本](https://github.com/shenxianpeng/keelhaven/blob/main/site/public/install.sh)就一页 shell，不放心可以先看一遍。

</FaqItem>
<FaqItem question="忘了仓库密码会怎样？">

备份就找不回来了，这是有意为之：仓库端到端加密，备用钥匙谁手里都没有，我们没有，你的存储服务商也没有。Keelhaven 把密码存在钥匙串里，过一道 Touch ID 随时能拷出来；最好也存一份进你的密码管理器。

</FaqItem>
<FaqItem question="为什么不上 Mac App Store？">

App Store 要求应用跑在沙盒里，而备份引擎得读你指定的任意文件夹、连网络和 SSH。Keelhaven 开着强化运行时（hardened runtime），只是不走商店；Beta 期间也还没公证，所以第一次打开要[多点一次确认](#faq)。

</FaqItem>

</LandingSection>

<LandingFooter />

</div>
