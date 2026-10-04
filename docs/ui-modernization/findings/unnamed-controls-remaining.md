# Interactive controls still without an accessible name

The accessibility pass in this phase rewrote `v-tooltip*` into `aria-label` for self-closing icon-only
`Button` instances. That regex missed anything with slot content or a closing tag, and it only covered
components it could recognise as Buttons. A sweep of every opening tag in `app/javascript` that carries a
`v-tooltip` and no `aria-label` returns 82 candidates; 72 of them are `span`, `div`, `time`, `img`,
`Avatar`, `Icon` or `fluent-icon` — informational tooltips on things that are not controls, which the
inventory correctly ignores.

These ten are real controls. A tooltip gives `aria-describedby`, never a name, so each announces as an
unnamed button.

| File | Line | Control |
|---|---|---|
| `components/widgets/conversation/commerce/CommerceOrderItem.vue` | 94 | copy the order number |
| `components/widgets/conversation/conversation/LabelSuggestion.vue` | 169 | accept a suggested label |
| `components-next/emoji-icon-picker/EmojiIconPicker.vue` | 152, 204 | the two picker mode triggers |
| `components-next/emoji-icon-picker/ColorPalette.vue` | 11 | a colour swatch |
| `components-next/message/CaptainGenerationDetails.vue` | 229 | open the generation detail |
| `components-next/message/chips/File.vue` | 70 | download an attachment |
| `components/widgets/conversation/ContactConversationLink.vue` | 48 | open a previous conversation |
| `components/widgets/WootWriter/ReplyBottomPanel.vue` | 293 | attach a file (FileUpload renders its own label + input) |
| `routes/dashboard/settings/profile/AudioAlertTone.vue` | 85 | preview an alert tone |

**Status:** one of this class — the bulk bar's add-label / remove-label trigger — was found by the
`conversation-bulk-actions` capture and named, which takes the 47-surface set to zero unnamed controls.
The ten above sit on surfaces the capture set does not reach yet (the emoji picker, the colour palette,
a message chip, the Captain generation detail, the profile alert tone), so naming them cannot be verified
by the gate today.

**Lands in:** the accessibility sweep, together with the surfaces needed to prove it — which is the point
worth keeping: every one of these was invisible until a capture existed for the surface it lives on.

---

## Re-scanned at the close of the phase

Four of the ten are now named, each by the batch that reached its surface: the order-number copy button
(`CommerceOrderItem.vue`), the alert-tone preview (`AudioAlertTone.vue`), the attachment control in
`ReplyBottomPanel.vue`, and the previous-conversation link (`ContactConversationLink.vue`).

**Six remain**, all on surfaces the capture set still does not reach:

| File | Line | Control |
|---|---|---|
| `components/widgets/conversation/conversation/LabelSuggestion.vue` | 169 | accept a suggested label |
| `components-next/emoji-icon-picker/EmojiIconPicker.vue` | 152, 204 | the two picker mode triggers |
| `components-next/emoji-icon-picker/ColorPalette.vue` | 11 | a colour swatch |
| `components-next/message/CaptainGenerationDetails.vue` | 229 | open the generation detail |
| `components-next/message/chips/File.vue` | 70 | download an attachment |

The 68 captured surfaces report **0 unnamed controls** in 544 captures. These six are outside that set,
so naming them is a change the gate cannot yet check — which is the reason they are still listed rather
than quietly fixed.

