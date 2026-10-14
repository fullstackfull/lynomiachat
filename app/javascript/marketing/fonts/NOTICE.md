# IBM Plex Sans Arabic, bundled with the marketing site

Four `.woff2` files committed to this repository and served to browsers by `plex-arabic.scss`. They are not
installed by any package manager, so this file is the only record of where they came from.

## What is bundled, read from the binaries

Every value below was read out of the font files' own `name` table with `fontTools`, not from a changelog.
All four files agree.

| field | value |
|---|---|
| family (name ID 1) | `IBM Plex Sans Arabic` |
| version (name ID 5) | `Version 1.101` |
| copyright (name ID 0) | `Copyright 2019 IBM Corp. All rights reserved.` |
| licence URL (name ID 14) | `http://scripts.sil.org/OFL` |

| file | weight | bytes |
|---|---|---|
| `IBMPlexSansArabic-400.woff2` | 400 | 42,848 |
| `IBMPlexSansArabic-500.woff2` | 500 | 45,296 |
| `IBMPlexSansArabic-600.woff2` | 600 | 45,688 |
| `IBMPlexSansArabic-700.woff2` | 700 | 44,280 |

178 KB in total, and an English visitor downloads none of it: every `@font-face` carries the Arabic
`unicode-range`, so the browser only fetches a file when the page actually contains Arabic.

## Where they came from

Google Fonts' own `css2` endpoint for `IBM+Plex+Sans+Arabic`, Arabic subset, served from
`fonts.gstatic.com/s/ibmplexsansarabic/v15/`. They are self-hosted rather than linked for the same reason
Inter is: a marketing page that reaches a third-party host on first paint is a render-blocking dependency on
somebody else's uptime, and this site has a performance budget
(`docs/official-website/05-design-and-content-spec.md` section 5).

## Licence

SIL Open Font License, Version 1.1, copied in full to `OFL.txt` beside this file. The OFL permits bundling
and redistribution with or without modification, including inside a commercial product, provided the files
are not sold on their own and the licence travels with them. These are unmodified.
