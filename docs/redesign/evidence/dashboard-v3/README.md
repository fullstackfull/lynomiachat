# Dashboard evidence, third pass

Real screenshots of a real running dashboard, taken with `tools/visual/capture.mjs` against
`localhost:3000` on local seed data (`rails db:seed` + `Seeders::AccountSeeder`). Nothing here is
composited, retouched or generated. There is no customer conversation, address, phone number or token
in any of them: every name in these shots belongs to the PaperLayer / Acme Inc fixture set.

```
node tools/visual/capture.mjs --set dashboard --viewports desktop,mobile --out <dir>
node tools/visual/capture.mjs --set dashboard --locale ar --viewports desktop --out <dir>
node tools/visual/capture.mjs --set dashboard --dark --viewports desktop --out <dir>
```

The dashboard's default appearance is "auto" -- `App.vue` reads `prefers-color-scheme` and puts `.dark`
on the root, which is what the whole `n-*` token set resolves against -- so `--dark` sets that media
query in the browser rather than changing a setting or using a second account.

| Set | Viewport | Pages |
| --- | --- | --- |
| `en/desktop` | 1440×900 | 10 |
| `en/mobile` | 390×844 | 10 |
| `ar/desktop` | 1440×900, RTL | 10 |
| `en/desktop-dark` | 1440×900, dark palette | 10 |

The earlier passes are `dashboard-before/` (the baseline this project started from) and
`dashboard-v2/`. Compare the same filename across directories.

## What these shots were taken to prove

- `conversation-chat` — the day marker ("Yesterday" / "أمس"), one timestamp per message rather than a
  repeated date, the Reply / Private Note segmented control, and the selected row's indigo rail.
- `ar/desktop/conversation-chat` — the whole shell mirrors, the selection rail sits at the inline
  start, the segmented control's sliding chip translates the right way, and the timestamp reads
  "10:49 PM" rather than the bidi-reordered "PM 10:49".
- `conversation-list` — the Mine / Unassigned / All counts, whose inactive badge moved from
  `slate-10` (3.0:1) to `slate-11`.
- `en/desktop-dark/conversation-chat` — the same screen on the dark palette: the selection rail, the
  tab counts, the day marker and the segmented control all resolve against the dark token set.
- `settings-profile` — the settings column centred in the space it has instead of pinned to the
  inline start with ~400px of empty page beside it.

## Known gap, visible in the Arabic set

1,905 of 4,462 multi-word Arabic strings are still the English source text, so the Arabic dashboard
shows "My Inbox" and "Search…" in the sidebar beside correctly translated labels. That is Crowdin's
corpus, not this branch's: per CLAUDE.md, source changes update `en.json` only. Every key *this*
project added has an Arabic sibling.
