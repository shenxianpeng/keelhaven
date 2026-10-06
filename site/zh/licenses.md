# 许可

Keelhaven 是自由开源软件。本页说明 Keelhaven 自身的许可，并致谢它所依赖的开源软件。

## Keelhaven

Keelhaven 的源代码位于
[github.com/shenxianpeng/keelhaven](https://github.com/shenxianpeng/keelhaven)，
以 [GNU 通用公共许可证第 3 版或更高版本](https://github.com/shenxianpeng/keelhaven/blob/main/LICENSE)
（GPL-3.0-or-later）发布。阅读、审计、构建、修改、fork，GPL 允许的一切都可以。
「Keelhaven」的名称和图标不在此授权范围内：fork 应当使用自己的名字发布。

## restic

Keelhaven 的备份由 [restic](https://restic.net) 执行，它是一个开源备份程序。
一份 restic 副本（0.19.1 版，通用二进制）**包含在 Keelhaven 应用包内**并随之
再分发，所以你永远不需要自己安装 restic。

restic 版权所有 © 2014 Alexander Neumann，按 BSD 2-Clause 许可证使用，全文
转载如下（法律文本按惯例保留英文原文）。同样的文本也随应用一起分发，可在
「关于」窗口中查看。

- 网站：<https://restic.net>
- 源码：<https://github.com/restic/restic>

```
BSD 2-Clause License

Copyright (c) 2014, Alexander Neumann <alexander@bumpern.de>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

restic 本身由许多开源 Go 库构建而成，各自遵循其许可。这些许可列在
[restic 仓库](https://github.com/restic/restic)中。

## Newsreader（网站字体）

本网站的标题使用 [Newsreader](https://github.com/productiontype/Newsreader) 字体，
版权 © 2020 The Newsreader Project Authors，依
[SIL Open Font License 1.1](/fonts/LICENSE-Newsreader.txt) 使用。字体文件由本站自己提供，
不经任何字体服务加载。

## 与 restic 项目无关联

Keelhaven 是独立产品，**与 restic 项目及其作者没有关联，也未获其赞助或
背书**。这里使用「restic」一词仅为描述 Keelhaven 所基于的软件。所有商标
均归各自所有者所有。

## 问题应该报到哪里

Keelhaven 的问题请报给我们，不要报给 restic 项目。备份失败更可能出在
Keelhaven 调用 restic 的方式上，而不是 restic 本身，而且 restic 的维护者
都是志愿者。如果真的发现了 restic 自身的 bug，我们会自己向上游报告。
