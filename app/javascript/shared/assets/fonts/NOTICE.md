# Third-party fonts bundled with this application

38 `.woff2` files under `Inter/` and `InterDisplay/` are third-party binaries committed to this repository.
They are not installed by any package manager, so nothing else in the build records where they came from.

18 of the 38 are served to browsers: the three stylesheets here — `inter.scss`, `InterDisplay/inter-display.scss`
and `widget_fonts.scss` — carry 18 `@font-face` rules between them, covering `InterVariable`,
`InterVariable-Italic`, seven static `Inter` weights and nine static `InterDisplay` weights. The other 20, all
of them static italics or unused static weights, are committed but referenced by nothing. The licence applies
to all 38 either way, because committing them to a distributed repository is itself distribution; which ones
reach a browser only changes who else receives them.

## What is bundled, read from the binaries

Every value below was read out of the font files' own `name` table, not from a changelog or from memory. All
38 files agree on all of it.

| field | value |
|---|---|
| version (name ID 5) | `Version 4.000;git-a52131595` |
| copyright (name ID 0) | `Copyright 2016 The Inter Project Authors` |
| licence (name ID 13) | `This Font Software is licensed under the SIL Open Font License, Version 1.1.` |
| licence URL (name ID 14) | `http://scripts.sil.org/OFL` |
| designer (name ID 9) | `Rasmus Andersson` |
| vendor URL (name ID 11) | `https://rsms.me/` |

The copyright **holder** is "The Inter Project Authors"; Rasmus Andersson is the designer. An earlier version
of this file named the designer in the licence column, which is not the same thing and is the name an OFL
notice has to carry.

## The licence text

`OFL.txt` beside this file is the licence, copied byte for byte and unmodified from the upstream release these
binaries came from:

| | |
|---|---|
| source | `https://raw.githubusercontent.com/rsms/inter/a52131595/LICENSE.txt` |
| matches tag | `v4.0` returns the identical file (same SHA-256) |
| SHA-256 | `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a` |
| size | 4380 bytes, 92 lines, ASCII, LF |

The `a52131595` in the URL is the commit the fonts themselves name in their version string, so the licence
text and the binaries come from the same revision rather than from whatever upstream's default branch happens
to hold today. Its first line — `Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)`
— is the same copyright holder the binaries carry.

Nothing here is paraphrased or reconstructed. If `OFL.txt` ever needs re-verifying, re-fetch that URL and
compare the hash.

## What this file is and is not

This records where the fonts came from and puts the licence next to them, because the OFL obliges a
redistributor to carry the copyright notice and the licence text with every copy, and serving `.woff2` files
to browsers is redistribution. **It is not a legal opinion and not a compliance sign-off.** Whether this
repository's overall distribution satisfies every obligation that applies to it is a question for a licence
review, not for this note.

## Why not swap them for a package

`@fontsource/inter` would put the same fonts under a package manager, with the licence text included and
version-pinned. That is the better long-term answer and it is a build change, not a licence fix: it belongs in
its own change rather than in a release-hardening pass, because it moves every `@font-face` src in three
stylesheets and all of those are on the critical rendering path of the dashboard and the widget.
