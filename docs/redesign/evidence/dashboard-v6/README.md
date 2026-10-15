# Labels: the two dialogs, before and after

Real browser shots, Chromium at 1440×900, against the running dev server with the seeded
`john@acme.inc` account. The `before-` frames were taken with the four changed files stashed, so the
page behind them is identical and only the dialog differs.

| shot | what it is |
|---|---|
| `before-label-add.png` / `after-label-add.png` | Add label. Before: the legacy `woot-modal`, a `div` with a backdrop — no Teleport, no focus trap, and a colour control that is a bare swatch with no value on it. After: the shared `Dialog`, a native `<dialog>` in the top layer, with the design system's input, checkbox and colour control. The focus ring on Cancel in the `after` frame is the trap having put focus inside. |
| `before-label-add-color.png` / `after-label-add-color.png` | The same dialog with the colour panel open. **This is the frame that decided the dialog's scroll mode.** The panel is an in-flow `absolute` child of the form (`ColorPicker.vue`'s `.colorpicker--chrome`), exactly like `ComboBoxDropdown.vue:69`. It reaches 792px while the form ends at 689px, so it only survives because the dialog keeps its default `overflow: visible`. Passing `scroll-body` here would have given it a second, closer clipping box and cut the hex field off the bottom. |
| `before-label-edit.png` / `after-label-edit.png` | Edit label, opened from the first row. |

## What is not in a picture

Two of the changes do not show up in a frame.

**The "Show label on sidebar" checkbox had no label.** Its `<label for="conversation_creation">`
pointed at an id that appears nowhere in this codebase — so clicking the words did nothing, and a
screen reader announced an unnamed checkbox. The same orphaned `for` is in `TeamForm.vue`; that one
is left for its own change. `verify-label-dialog.mjs` asserts the fix by clicking the text and
checking the box's `checked` flipped.

**The dialogs are reused now instead of rebuilt.** The old modal mounted a fresh component on every
open, so the form was always clean. A `Dialog` held by a ref stays mounted, so both dialogs clear
themselves on `open()` — otherwise the next Add would hold the last label's text, and re-opening the
same label after abandoning an edit would keep the abandoned edit.

## Reproducing

```
node /path/to/verify-label-dialog.mjs    # 7 checks against the running server
```

It covers: the button opens a real `<dialog>`; the sidebar label toggles the box; the colour panel
is not clipped; Escape closes it; focus stays inside; Edit opens filled with the row that was
clicked.
