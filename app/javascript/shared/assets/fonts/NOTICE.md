# Third-party fonts bundled with this application

38 `.woff2` files under `Inter/` and `InterDisplay/` are third-party binaries committed to this repository and
served to every browser that loads the dashboard or the widget (`inter.scss`, `widget_fonts.scss`). They are
not installed by any package manager, so nothing else in the build records where they came from.

| family | designer | licence |
|---|---|---|
| Inter | Rasmus Andersson | SIL Open Font License, Version 1.1 |
| Inter Display | Rasmus Andersson | SIL Open Font License, Version 1.1 |

## Open compliance action before distribution

**The verbatim licence text is not in this repository, and the OFL requires it to travel with the files.** The
licence's own terms oblige a redistributor to include the copyright notice and the licence text with every
copy, source or binary. Serving the `.woff2` files to browsers is redistribution.

This file records the facts and does not substitute for the licence. The remaining step, which needs a network
fetch this note could not make:

1. Download the canonical `OFL.txt` from the Inter release that these binaries came from
   (`https://github.com/rsms/inter`, the release whose `.woff2` files match the ones here).
2. Commit it beside this file as `OFL.txt`, unmodified.
3. Confirm the copyright line it carries names the correct years, and copy that line into the table above.

Until step 2 is done, the fonts are redistributed without their licence. It is tracked as an open item in
`docs/p-final/02-license-audit.md` §5 and in the release gate, and it is the kind of item a customer's
licence review asks about directly.

## Why not swap them for a package

`@fontsource/inter` would put the same fonts under a package manager, with the licence text included and
version-pinned. That is the better long-term answer and it is a build change, not a licence fix: it belongs in
its own change rather than in a release-hardening pass, because it moves every `@font-face` src in two
stylesheets and both of those are on the critical rendering path of the dashboard and the widget.
