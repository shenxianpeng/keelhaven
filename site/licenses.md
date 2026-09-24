# Licenses

Keelhaven is free and open source software. This page states Keelhaven's own
license and credits the open source software it builds on.

## Keelhaven

Keelhaven's source code lives at
[github.com/shenxianpeng/keelhaven](https://github.com/shenxianpeng/keelhaven) under
the [GNU General Public License, version 3 or later](https://github.com/shenxianpeng/keelhaven/blob/main/LICENSE)
(GPL-3.0-or-later). Read it, audit it, build it, modify it, fork it — anything
the GPL allows. The "Keelhaven" name and icon are not part of that grant: a
fork should ship under its own name.

## restic

Keelhaven's backups are performed by [restic](https://restic.net), an open
source backup program. A copy of restic (version 0.19.1, universal binary) is
**included in the Keelhaven application bundle** and redistributed with it, so
you never have to install restic yourself.

restic is copyright © 2014 Alexander Neumann and is used under the BSD
2-Clause License, reproduced in full below. The same text ships inside the app
and can be read from the About window.

- Website: <https://restic.net>
- Source: <https://github.com/restic/restic>

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

restic is itself built from a number of open source Go libraries, each under
its own license. Those licenses are listed in the
[restic repository](https://github.com/restic/restic).

## Newsreader (website font)

This website sets its headings in [Newsreader](https://github.com/productiontype/Newsreader),
copyright © 2020 The Newsreader Project Authors, used under the
[SIL Open Font License 1.1](/fonts/LICENSE-Newsreader.txt). The font is served
from this site — it is not loaded from a font service.

## Not affiliated with the restic project

Keelhaven is an independent product. It is **not affiliated with, sponsored by,
or endorsed by** the restic project or its authors. "restic" is used here only
to describe the software Keelhaven builds on. All trademarks are the property
of their respective owners.

## Where to report problems

Report Keelhaven bugs to us, not to the restic project. A failed backup is far
more likely to come from how Keelhaven drives restic than from restic itself,
and its maintainers are volunteers. If a genuine restic bug does turn up, we
report it upstream ourselves.
