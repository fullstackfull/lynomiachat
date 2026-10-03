# Deferred decisions

Things found during the phase that are real, that are not scope creep, and that are deliberately
handled in a later commit rather than the one that found them. Each entry says what, why it waits, and
where it lands.

## 1. Tables at narrow widths need a sticky action column, not just a scroll wrapper

**Found in:** the table-system commit, verified at 390px in the harness.

Fifteen tables render `min-w-full table-auto` with no overflow wrapper. At 390px the columns spill past
the card: in `labels-list-en-390` the edit and delete buttons draw *outside* the white panel, on the
page background. Wrapping the table in `overflow-x-auto` fixes the spill — and the before/after capture
showed it also pushes the action column out of view, reachable only by a horizontal swipe inside the
card.

That is a worse trade on a phone: a control that looked untidy became a control you have to discover.
The right answer is the scroll wrapper **plus** an action column stuck to the end edge, which needs the
row to carry a real background so the sticky cell can inherit it — and that depends on which surface
each table sits on.

**Status:** `BaseTable` gained a `scrollable` prop, off by default, so nothing regresses now.
**Lands in:** the responsive commit, where the settings list pages get a designed mobile treatment and
a per-page parity table.

## 2. The z-index ladder is migrated piecemeal, not in one sweep

**Done:** `z-60` generated no CSS — Tailwind's default scale stops at 50 — so the three menu *bodies*
written with it (`LocaleCard.vue:137`, `CategoryCard.vue:123`, `InboxDisplayMenu.vue:140`) had shipped
with no z-index at all, and now use `z-dropdown`. The two on `DropdownMenu`'s menu *items* were dead
either way and are deleted.

**Not done:** the rest of the ladder — `z-40 → z-50 → z-[100] → z-[1000] → z-[9990] → z-[9999] →
z-[10001]` — still runs on raw values. Collapsing it onto the five named steps means changing relative
order in at least one real case: a dropdown teleported to the body at `z-[1000]` currently paints
*above* a drawer, and would paint below it afterwards. Proving that is safe needs captures of an
overlay opened inside another overlay, which the harness does not have yet.

**Lands in:** a commit that first adds nested-overlay surfaces (a dropdown inside a drawer, a dialog
over a popover) to the capture set.

## 3. Two token-layer defects that change appearance when fixed

- `select/Select.vue:58` outlines errors with `outline-n-red-9`. There is no `n-red-*` ramp, so the error state renders nothing. Fixing it to `n-ruby-*` makes an invisible state visible.
- `spinner/Spinner.vue:18-20` passes `strokeWidth`, `strokeLinecap` and `strokeLinejoin` in camelCase, which are not valid SVG attribute names. All 89 spinners therefore render at the SVG default stroke width of 1 instead of 8.

**Lands in:** the forms commit and the loading-states commit respectively, each with a capture.

## 4. Discovered capability gaps — documented, not implemented

Per the phase's scope rule, these are written down and left alone:

- **Campaigns has no list controls at all** — no search, no sort, no filter — while every other first-class list has at least two.
- **Companies has search and sort but no filter**, although `CompanyHeader` is otherwise a copy of `ContactHeader`.
- **Settings search disappears below `sm`** on 18 pages with no replacement. The responsive commit restores a path to it; making search itself better is not this phase's job.
- **Conversations has no active-filter chips and no numeric filter count** — Contacts has both.
- **The sidebar's Segments and Tagged-with sub-groups have no sort menu**, while the four parallel sub-groups rendered by the same component do.
- **Empty sub-groups vanish silently** in the sidebar: an account with no teams has no Teams section at all, and the `SIDEBAR.NEW_TEAM` / `NEW_INBOX` / `NEW_LABEL` strings that would populate an empty state sit unused.

## 5. Settings list pages still have a bare-sentence empty state

`SettingsLayout` now exposes an `emptyState` slot, so a page can offer the action that fills the list
instead of only stating that it is empty — but no page uses it yet. Eighteen settings lists still fall
through to the default message. Giving each one an icon, a sentence and its primary action is page
work with an information-architecture decision attached (which action, and whether the search box
should still be there when there is nothing to search).

**Lands in:** the settings commit, against the parity manifest in `audit/surface-settings-crud.md`.

## 6. Six "Learn more" links have no help page to point at

`BaseSettingsHeader` resolves its help link through `FEATURE_HELP_URLS`. Six values passed by call
sites index nothing, so those pages silently have no link: `assignment-policy`,
`conversation-workflow`, `slack_integration`, `linear_integration`, `notion_integration` and
`shopify_integration` (the table has `shopify`, not `shopify_integration`).

The helper now normalises hyphens to underscores, so `assignment_policy` and `conversation_workflow`
will resolve the moment a URL exists for them; the four integration ones need a decision about whether
each integration gets its own help page or they all point at the integrations guide. That is content,
not code, so it is written down rather than guessed at.

Two were unambiguous and are fixed: `automation` passed a `linkText` that was translated and never
rendered, and **custom roles linked to the canned-responses help page** while its link read "Learn
more about custom roles". Both now have entries following the file's own slug pattern — worth a
confirmation that `chwt.app/hc/automations` and `chwt.app/hc/custom-roles` resolve.

## Status and priority icons carry hard-coded hex with no dark-mode form

`theme/icons.js:216-250` fills the four `priority-*` glyphs and `status-resolved` /
`status-snoozed` with literal hex (`#e5484d`, `#ffc53d`, `#e4e4e9`, `#0D9B8A`, `#FFBA1A`)
rather than `currentColor`. Only `priority-empty` uses `currentColor`. Two consequences:

- The status and priority columns of the conversation list keep their light-mode colours in
  dark mode, while every token-driven neighbour re-tones around them.
- A component cannot influence them, which is why `CardPriorityIcon.vue`'s `text-n-slate-5`
  has no effect on a real priority (and why audit finding H4 was withdrawn).

Not done in this phase: the fix is to replace the fills with `currentColor` in the icon set and
move the colour decision into the two components, which changes how these glyphs look on every
surface that renders them — the conversation list in both card forms, the conversation header,
search results and the reports. That needs its own before/after pass with captures of all of
them, and `conversation-card-expanded` is not in the capture set yet.

## Reachability gaps in the conversation workspace that are capability work, not presentation

Found while modernising the workspace. Each is a feature a mouse user has and a keyboard or touch user
does not. The ones that could be fixed without inventing new behaviour were fixed in that commit — the
row context menu's submenus now open on click and Enter, the SLA chip is a real button, the composer's
expand control is no longer behind the Captain flag, the bulk-select checkbox is revealed where there is
no hover, and the contact-field pencils are visible on touch. These three are what is left.

### Focusable conversation rows

`ConversationCard.vue` and `ConversationCardExpanded.vue` are `<div>`s with `@click` and no `tabindex`,
`role` or `@keydown`, so a keyboard user cannot Tab into the list at all. The product's answer today is
Alt+J / Alt+K, which navigate by querying `div.conversations-list div.conversation` and calling
`.click()` on the result. Giving a virtualised list a focus model has to be designed together with that
layer — two systems moving the same selection — and it is a new capability rather than a restyle.

### A real error state for the conversation list

Every fetch failure in `ChatList.vue` ends in a transient toast and the list then falls through to "There
are no active conversations in this group", so a failed load is indistinguishable from an empty inbox and
there is no retry anywhere in the panel. New copy and a new control.

### Telling "nothing matches your filter" from "this inbox is empty"

`CHAT_LIST.LIST.404` is one fixed string whatever the tab, folder or five advanced filters. The empty
state now renders through `EmptyStateLayout` so it is centred and has an icon, but the branch and a
second entry point to `resetAndFetchData` are new content and a new control, and the back chevron in the
header is the existing route to clearing a filter.

## Column headers for the expanded conversation list

`ConversationCardExpanded.vue` lays out ten semantic columns — three of them identical 16px icon slots —
with no header row anywhere, so the list cannot say what its columns are and cannot be sorted from them.
Whether that becomes a `BaseTable` is the open question, and answering it needs
`conversation-card-expanded` in the capture set first.

## RESOLVED — the second design system in `_woot.scss` is gone, and the brand is a component variant

**Was:** ~120 hand-written lines at the end of `app/javascript/dashboard/assets/scss/_woot.scss`, inside
the `@layer utilities` block, attaching styling to Tailwind's own class names and to bare element
selectors. Four of the five rules reached things that never opted in:

| Selector | Did | Reached |
|---|---|---|
| `.bg-n-brand\/10` | `!important` gradient, `uppercase`, `color: white`, `display: block`, `margin: 10px`, `box-shadow: 0 0 20px #eee` | `components-next/button/Button.vue:106` — the **faded blue variant of the shared Button** — plus the Captain FAQ chip, the inbox sort menu's active row, the context-menu hover tint |
| `.bg-n-brand\/20:hover` | background-position, `color: #fff` | that variant's hover state |
| `main` | `border: 2px solid`, `margin: 1rem`, `border-radius: 10px`, a 28px drop shadow | every `<main>` in the product — Help Center, Companies, Campaigns, Contacts, the gallery view |
| `button:has(span.sr-only)` | `background: #111 !important`, `width: 27px`, `height: 17px` | **any button carrying a screen-reader-only label**, so naming a button broke its layout |

The fifth was the "Lynomia brand gradient for primary buttons": a navy→blue gradient, white text,
`font-family: Arial`, `font-size: 16px`, `font-weight: bold`, `text-transform: uppercase`,
`border-radius: 10px`, a sweeping `::before` overlay and `scale(1.05)` on hover — applied to every
`<button>` that happened to carry `bg-n-brand`, and to every button inside anything that did.

**Now:** the whole block is deleted. Not scoped, not guarded, not excepted — removed, because the source
of the conflict was the global selectors themselves and every exception would have been another one.

Lynomia's identity reaches an ordinary primary button the way the design system intends: the `solid`
variant is `bg-n-brand`, and `n-brand` is Lynomia's blue. Nothing about that changed.

The gradient survives as an **explicit, opt-in variant** on the shared Button — `variant="brand"` — built
from the brand token (`from-n-blue-10 to-n-brand`), the product's own elevation (`shadow-raised`), the
shared radius, the shared size scale and `font-inter`. No Arial, no uppercase, no fixed pixel font size,
no `!important`, no hover scale, and no global selector. It is colour-independent, because the gradient
*is* the fill and crossing it with the five colours would mean nothing.

It is deliberately applied **nowhere** by default. Which promotional call to action deserves to stand
apart from an ordinary primary button is a per-call-site design decision, not something to spray across
the product from here. The variant is documented in `Button.story.vue` so it is discoverable, and the
comment on it says why it is not a default.

**Consequences visible in the capture set, all intended:** the faded-blue Button variant renders as the
subtle 10%-alpha tint it was always meant to be instead of an uppercase white-on-gradient block; eight
layout components get their own spacing back instead of a 2px border, a 1rem margin and a 28px shadow
nobody asked for; and a button with an accessible name keeps its size.

## Deleting a contact from the conversation panel leaves the panel open on a deleted record

`ContactInfo.vue` declared `emits: ['panelClose']` and fired it from `ContactDeleteModal`'s `@deleted`,
but no parent ever listened — `@panel-close` appears nowhere in the repository. The emit was removed as
dead code, and this is the gap it was reaching for: after a successful delete the panel keeps rendering
the contact that no longer exists until the agent navigates away.

Closing the panel, or re-rendering it in an empty state, is new behaviour on a destructive path, so it is
not folded into a visual commit.

## Three contact-panel items from the plan that were not taken

- **Default-open sidebar sections.** `isContactSidebarItemOpen` is `key => !!uiSettings.value[key]`, so
  every one of the eleven sections starts collapsed for a new agent. Making conversation actions,
  conversation info and contact attributes default to open would help, but it changes the default of a
  persisted per-user preference, which is product behaviour rather than presentation.
- **Widening when an attribute row can be dragged.** The reorder handle is disabled unless the "show all"
  state is on, which also disables it for an account with five attributes or fewer that never needs the
  toggle. Changing the gate needs a decision about what the handle means when there is nothing to
  collapse.
- **An empty-value row rendering the wrong branch.** Reported as a defect; it does not reproduce. Every
  caller already gates `href` on the value, so a row with no value falls through to the non-link branch
  exactly as intended.

## Five correctness defects on the settings surface, found while modernising it

These are bugs, not presentation, so none of them is folded into a visual commit. Each is reproducible
from the file and line given.

- **A failed fetch renders as an empty list.** `data/Index.vue:81-84` `fetchImports` has no `catch`, and
  `refresh` only resets flags in `finally`. If `DataImportsAPI.get()` rejects, `dataImports` stays `[]`
  and the page shows "No imports yet" with a New import button — for a request that failed. `data/Show.vue`
  has the same shape: a rejected `fetchImport` leaves a blank body.
- **The MFA wizard advances past a rejected code.** `MfaSetupWizard.vue:79-88` wraps `emit('verify', …)`
  in `try/catch`, but `emit` is synchronous and returns `undefined`; the parent's `async verifyCode`
  rejects later on its own promise. So `setupStep.value = 'backup'` always runs: on a wrong code the user
  is moved to step 2 and shown an empty backup-codes grid, while the error lands on a step-1 input that is
  no longer rendered. The local `catch` is unreachable.
- **Four silent swallows on paths where silence is wrong.** `MfaSettings.vue:50-52`, `account/Index.vue:126-128`,
  `MfaSetupWizard.vue:61-63` and `NotificationPreferences.vue:102-104`. A failed MFA status read shows the
  user the "not enabled" card as if MFA were simply off.
- **Two downloads and one abandon cannot report failure.** `data/Show.vue:159-179` and `:120-130` use
  `try/finally` with no `catch`, so a failed export or abandon just stops the spinner. The sibling
  `retryImport` in the same file does catch and toast.
- **Two nav items lead to billing and one leaves the product.** `billing_settings_index` is an `onMounted`
  hard redirect to a hardcoded external URL with a bare spinner, no heading and no error path; the
  adjacent "Subscription" item is the real in-app page. All three paywalls' Upgrade buttons point at the
  redirecting one. Which of the two an admin should click, and whether the external URL belongs in
  configuration, are product decisions.

## Copy casing is inconsistent across the product, not only in webhooks

The webhook event list reads "Conversation Created, Message created" because
`INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.EVENTS` mixes Title Case and sentence case across its
eleven values. Fixing those eleven in isolation would make webhooks consistent with itself and
inconsistent with everything around it: the same mixture runs through the settings strings generally.
A casing convention is a copy decision for the whole product, and changing source strings retranslates
them at Crowdin, so it belongs in one deliberate pass rather than in a visual batch.

## FormKit styling in the new-hook modal is contained, not yet moved

`integrations/NewHook.vue` shipped an unscoped global stylesheet: eight rules on `.formkit-*` class names
that applied to every FormKit form in the application for as long as the component stayed loaded. Every
selector is now prefixed with the modal's own root class, so it can no longer leak, and the one raw
`margin-bottom: 0px !important` is a utility. The rules themselves still exist as CSS, which the project
rules would rather they did not: FormKit renders its own wrapper markup, so the real fix is its `classes`
configuration. That is a FormKit-level change whose blast radius covers every form built on it, and it
wants its own verification pass.

## The agent-bots list does not say what kind of bot a row is

`agentBots/Index.vue` renders two columns: the bot's name and avatar, and "Webhook URL"
(`bot.outgoing_url || bot.bot_config?.webhook_url`). A CSML bot has neither, so its row shows a name and an
empty cell, and nothing on the page distinguishes a webhook bot from a CSML one — `bot_type` is in the
payload and is rendered nowhere. Showing it would be useful and is a new piece of information on the
surface, which the contract says to write down rather than add quietly.
