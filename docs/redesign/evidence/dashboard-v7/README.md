# dashboard-v7 — what `5b7a0ad6` and `80de56ae` changed on screen

Captured from the running dashboard on seed data at 1440×900, logged in as `john@acme.inc`,
account 1. Same browser and same login as every earlier set in this directory. No customer data.

**Most of what those two commits changed has no picture.** Eleven controls gained accessible
names; a dialog stopped pointing `aria-describedby` at an element that did not exist; a regex
checkbox became a real label. None of that moves a pixel — it was verified by reading the
accessibility tree and the DOM in Chromium, and those measurements are in the commit messages
rather than here. What follows is only the part that is visible.

| File | What it shows | Measured alongside |
| --- | --- | --- |
| `after-command-palette-brand-accent.png` | Cmd+K palette accented in the brand indigo | `--ninja-accent-color` computes to `rgb(91 91 240)`. It was the literal `rgba(39, 129, 246, 1)` — the Chatwoot blue this installation retired — and is now `rgb(var(--brand))`, which resolves per document so the widget and portal keep their own blue. |
| `after-reports-pager-ltr.png` | The Reports pager, English | Four arrows, each with a name: First / Previous / Next / Last page. The active page carries `aria-current="page"`. |
| `after-reports-pager-rtl-mirrored.png` | The same pager under `dir="rtl"` | All four read `matrix(-1, 0, 0, -1, 0, 0)`. Before this commit they were identity in both directions, so in Arabic "previous" pointed at the next page. Reading right to left the order is `«` `‹` 1 2 3 `›` `»`, which is correct. |
| `after-settings-help-chevron-rtl.png` | The settings help link in Arabic | The trailing chevron now mirrors. It is also `aria-hidden`, which needed it to become a bare `<span>`: `Icon` renders `h('span', { class })` and forwards no other attribute, measured — the rendered element's whole attribute list is `["class"]`. |
| `after-canned-shortcode-error.png` | Add canned response, short code emptied and blurred | The red outline and "Short Code is required." are back. `dedf7d66` called `v$.shortCode.$touch` and nothing read the result, so a touched-and-invalid field looked identical to a valid one. The "Message" label above the editor is a `role="group"` name now, not a `label for` pointing at a `<div>`. |
| `after-regex-label-toggles.png` | Add custom attribute, after clicking the WORDS beside the regex checkbox | The box toggled and the pattern and hint fields appeared. Its accessible name reads "Enable regex validation"; before, the text was a loose sibling node, so the box had no name and the words did not toggle it. |

## What is deliberately not pictured

Three dead Tailwind utilities were replaced (`bg-black/50`, `from-black/*`, `text-gray-900`),
because `theme.colors` sits outside `extend` and replaces the palette, so each compiled to no CSS
at all. The effect is a scrim appearing behind a referral video's play glyph, two hover gradients
appearing on shared attachments, and a Help Center portal label taking its intended colour. All
three need seed data this environment does not have (a referral message, a shared attachment, a
configured portal), so they are proven by measurement instead — each class was applied to a live
element and its computed value read:

```
bg-black/50   -> rgba(0, 0, 0, 0)     bg-n-black/50   -> rgba(0, 0, 0, 0.5)
text-gray-900 -> inherited, unchanged  text-n-slate-12 -> rgb(28, 32, 36)
from-black/40 -> no gradient stop      from-n-black/40 -> rgba(0, 0, 0, 0.4) stop
```
