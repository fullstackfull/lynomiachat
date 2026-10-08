# P7-C — Live browser UI audit

A real browser (Chromium via Playwright) against a production-mode instance of this branch, signed in as an
administrator, over 21 route groups × 3 viewports (1440×900, 834×1112, 390×844) in English, and 6 route groups
× 2 viewports in Arabic. Every route was checked for console errors, failed requests, 4xx/5xx responses,
horizontal overflow, and — on the routes this phase changed — for what it actually says.

## How it was run

- Production-mode Rails on `127.0.0.1:3001` against the local `chatwoot_production` database, serving the real
  Vite build. A second instance, so the one on `:3000` was left alone.
- Local demo data seeded for the audit: 6 conversations (2 open, 2 resolved, 1 pending, 1 snoozed) and 3 failed
  outgoing messages — one 131049, one 131042, one unclassified (470).
- Scripts under `tmp/audit/` (gitignored), screenshots under `tmp/audit/shots/`.

## Defect matrix

| # | What | Where | Severity | Status |
| --- | --- | --- | --- | --- |
| 1 | `GET /api/v1/accounts/:id/portals` returned 401 on every Inbox load, and the rejection surfaced as an unhandled `Error: You are not authorized to do this action` | `ConversationView.vue` dispatched `portals/index` on mount; the Help Center policy overlay now refuses it | **Blocker** — a console error on the product's busiest screen, caused by this phase | **Fixed.** The dispatch is gone; nothing in the conversation workspace read portal state |
| 2 | Inbox settings offered a "Help Center" portal selector that could only ever list nothing, and fetched the same refused endpoint | `settings/inbox/Settings.vue` | **Should fix** — a dead control, and the second half of the same regression | **Fixed.** Field, getter, fetch and `selectedPortalSlug` removed; `portal_id` dropped from the save payload rather than sent as `null`, so an inbox that already carries a link keeps it |
| 3 | `PATCH /inboxes/:id` accepted any `portal_id` at all — another tenant's, or the platform documentation's. `Inbox belongs_to :portal, optional: true` is not scoped to the account | `api/v1/accounts/inboxes_controller.rb` (upstream) | **Should fix** — a cross-account reference, pre-existing but newly reachable only via the API | **Fixed.** `Custom::Api::V1::Accounts::InboxesController` refuses the parameter at the request boundary with 422 |
| 4 | `RangeError: Invalid language tag: en-US@posix`, three times per load, on Reports Overview at every viewport | `navigator.language` passed straight into `Intl.DateTimeFormat` / `Intl.NumberFormat` in 5 places | **Should fix** — the tag comes from the browser, not from us, and an unparseable one crashed the component formatting the value | **Fixed.** New `shared/helpers/localeHelper.js#toIntlLocale`; `useLocale` now delegates to it, and the five raw call sites go through it |
| 5 | The failure explanation was right-aligned beside an outgoing bubble, so three lines of body copy were set ragged-left | `MessageError.vue` (introduced earlier in this phase) | **Should fix** — markedly harder to read, and the explanation is the part an agent has to read | **Fixed.** The block still sits against its bubble; its sentences are start-aligned |
| 6 | In Arabic, the provider's English refusal was bidi-reordered, so `470: Message failed…` rendered as `Message failed… :470` — the error code detached from its message | `MessageError.vue` | **Should fix** — the code is the first thing an operator looks up | **Fixed.** The refusal is isolated in `<bdi dir="auto">`, the repo's own idiom for this |
| 7 | `CHAT_LIST.FAILED_TO_SEND` in `ar/chatlist.json` was a copy of the English source string, so the Arabic UI read "Failed to send" above three lines of Arabic | `ar/chatlist.json` | **Should fix** — conspicuous beside the new Arabic copy | **Fixed.** "تعذّر الإرسال" |
| 8 | `GET /enterprise/api/v1/accounts/:id/limits` returns 404 on every page that uses Captain | `check_cloud_env` returns 404 off Chatwoot Cloud; `accounts/limits` swallows it by design | Informational — correct behaviour on a self-hosted install, no user impact | **Not changed.** One console line |
| 9 | `GET /api/v1/accounts/:id/custom_roles` returns 401 on Settings → Agents | `ensure_custom_roles_feature_enabled` raises when the `custom_roles` feature is off; the client requests it unconditionally | Informational — upstream, handled, no user impact | **Not changed** |
| 10 | Two elements carry `id="app"` | The Rails layout's wrapper and the mounted Vue root | Informational — invalid HTML; `#app[dir]` selectors still resolve because they are attribute-qualified | **Not changed.** Upstream layout |

Three "findings" the sweep reported were not defects: `contacts` → `contacts?page=1`, `reports/agent` →
`reports/agent?from=…`, and `settings/inboxes` → `settings/inboxes/list` are the routes' own default parameters.
`settings/applications` → `dashboard` was a wrong path in the sweep list; integrations live at
`settings/integrations`.

## What the audit confirmed works

**Inbox visibility (P7-A), end to end against the running app:**

| Check | Result |
| --- | --- |
| Status chip renders, names the active status, carries `aria-label="Status filter: Open. Change it."` | PASS |
| The chip opens the panel holding Status *and* Order by | PASS |
| All + Open → 2 rows; switching to Resolved → 2 rows; Snoozed → 1 row | PASS |
| Mine + Snoozed → 0 rows, and the empty state reads "No conversations with this status / The status filter is set to Snoozed. Conversations with another status are hidden." with a "Show all conversations" button | PASS |
| Clicking it sets the chip to All and the list to 3 rows | PASS |
| The choice survives a reload — the single persistence path holds | PASS |

**WhatsApp failure UX (P7-B), on the three seeded failures:**

| Message | Retry | Doc link | What it says |
| --- | --- | --- | --- |
| 131049 | **withdrawn**, with the reason | yes | "WhatsApp limited marketing messages to this person", the per-recipient cap explained, then `WhatsApp said: 131049: …` |
| 131042 | kept | yes | "WhatsApp could not bill this message", the billing explanation, then `WhatsApp said: 131042: …` |
| 470 (unclassified) | kept | no | the raw refusal only, exactly as before |

Zero hidden-until-hover descendants in all three blocks: nothing about a failure is behind a hover any more.

**Navigation:** the sidebar reads "Help & Support" / "المساعدة والدعم"; "Portals" and "Help Center" appear
nowhere.

**Responsive and RTL:** zero horizontal overflow on every route at every viewport, English and Arabic.
`div#app` carries `dir="rtl"` under an Arabic account locale, and the Arabic dashboard renders throughout.

## After the fixes

The sweep was re-run against a rebuilt bundle: the 401, the unhandled rejection and the `RangeError` are gone.
What remains across 63 route/viewport combinations is items 8 and 9 above, both expected, plus the benign
redirects. No console errors, no 5xx, no overflow.
