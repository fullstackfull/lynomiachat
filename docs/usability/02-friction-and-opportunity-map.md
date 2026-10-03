# Lynomia usability: friction and opportunity map

## 0. Evidence discipline

**There is no product usage data for this installation.**

- Amplitude (`helper/AnalyticsHelper`) only initialises when `analyticsToken` is configured, and the events it would
  send are feature events, not navigation or frequency data.
- The Enterprise audit log records **mutations** (`Flows::Audit`, `Custom::Audit::CustomFilter`, Commerce's trail).
  It records no page views, no clicks, no searches.
- No route-usage table, no feature-usage counters exist.

So this document never says "users frequently do X". Every row is tagged:

- **[CODE]** — observed in the repository: the control exists, or demonstrably does not.
- **[HYP]** — expected-usage hypothesis derived from product structure (what the page is *for*), not from measurement.

Frequency columns are therefore **[HYP]** by construction. Impact, risk and confidence are judged against **[CODE]**.

## 1. The friction list

Scored Frequency / Impact / Risk / Confidence, each Low–Medium–High. "Already covered" rows are kept deliberately:
not implementing them is a finding.

| # | Friction | Evidence | Freq | Impact | Risk | Conf | Decision |
|---|---|---|---|---|---|---|---|
| 1 | Flow Builder and Commerce are missing from the command bar, although both routes carry correct `meta` | [CODE] `useGoToCommandHotKeys.js` has 30 entries, neither of these | High [HYP] | Medium | **Low** | **High** | **implement** |
| 2 | A saved-but-unpublished flow draft is invisible in the flow list; the row renders `flow.published` only while the payload already carries `draft` | [CODE] `flows/Index.vue`, `flows_controller#flow_json` | High [HYP] | **High** (admin believes edits are live) | **Low** | **High** | **implement** |
| 3 | No flow duplicate; a variant of a multi-node flow is rebuilt by hand | [CODE] no duplicate in `Index.vue`; node-level duplicate exists | Medium [HYP] | **High** | **Low** | **High** | **implement** |
| 4 | Every flow starts blank (`Flows::Versions::STARTER` = Start → End); no templates | [CODE] | High [HYP] | **High** | Medium | **High** | **implement** (recipes) |
| 5 | Flow list empty state is one sentence with no next action | [CODE] `SettingsLayout` | High [HYP] (first run) | Medium | **Low** | **High** | **implement** |
| 6 | `Cmd/Ctrl+S` in the builder opens the browser save dialog instead of saving the draft | [CODE] no binding | High [HYP] | Medium | **Low** | **High** | **implement** |
| 7 | A browser reload or tab close discards an unsaved graph silently; only in-app navigation is guarded | [CODE] `onBeforeRouteLeave` only | Medium [HYP] | **High** (lost work) | **Low** | **High** | **implement** |
| 8 | From an open audience there is no way to use it in Automation — you leave, navigate, and re-find it by name | [CODE] segment header offers edit + delete only | High [HYP] | **High** | **Low** | **High** | **implement** |
| 9 | Same for Campaigns | [CODE] | High [HYP] | **High** | **Low** | **High** | **implement** |
| 10 | No audience duplicate; currency/threshold variants are rebuilt condition by condition | [CODE] | Medium [HYP] | **High** | **Low** | **High** | **implement** |
| 11 | No audience copy-link, although `/contacts/segments/:id` is a clean deep link | [CODE] | Medium [HYP] | Low | **Low** | **High** | **implement** (same menu, one line) |
| 12 | Audience dependency counts are visible only inside the edit popover | [CODE] `ContactsFilter.vue` | Medium [HYP] | Medium | **Low** | **High** | **implement** (surface in the actions menu) |
| 13 | No audience presets; a "high-value customers" audience needs the Commerce field model to be understood first | [CODE] | High [HYP] | **High** | **Low** | **High** | **implement** (recipes) |
| 14 | Automation empty state is one sentence; a new rule opens on a shape nobody wants | [CODE] `START_VALUE` | High [HYP] (first run) | Medium | **Low** | **High** | **implement** (empty state + recipes) |
| 15 | No automation recipes; the same Commerce-event rule shape is rebuilt per event | [CODE] clone exists, the first rule does not | High [HYP] | **High** | Medium | **High** | **implement** (recipes) |
| 16 | Commerce order number is plain text with no copy affordance, unlike email/phone one panel above | [CODE] `CommerceOrderItem.vue` | High [HYP] | Medium | **Low** | **High** | **implement** |
| 17 | Customer 360 is unavailable on the contact page (conversation-only) | [CODE] panel API is `/conversations/:id/commerce/...` | Medium [HYP] | Medium | **High** (backend change) | Medium | **defer** → P2 |
| 18 | Recently-visited records have no list | [CODE] none exists | Medium [HYP] | Low | Medium | **Low** | **reject** — the command bar + sidebar + browser history already cover return-to-record; a recents store is new persistent data for convenience only (stop condition 7) |
| 19 | No favourites/pinning for inboxes, audiences, flows, teams | [CODE] none | Low [HYP] | Low | Medium | **Low** | **reject** — the sidebar already lists all of them; pinning adds a concept without removing a step |
| 20 | Conversation quick actions (assign, label, priority, status, snooze, copy link, open in new tab, bulk variants) | [CODE] **all already exist** in the context menu *and* the command bar | High | — | — | — | **reject — already covered** |
| 21 | Global search / command palette | [CODE] **exists** (`@chatwoot/ninja-keys`, 30 gated destinations) | High | — | — | — | **reject — stop condition 3.** Extend the array only (#1) |
| 22 | Keyboard productivity | [CODE] **7 hotkey composables + discoverable modal** | High | — | — | — | **reject — already covered.** One page-scoped gap implemented as #6 |
| 23 | Bulk actions | [CODE] **exist** for conversations and contacts | High | — | — | — | **reject — already covered.** Audience membership is dynamic and must never be bulk-mutated |
| 24 | User preferences platform | [CODE] **exists** (`ui_settings` via `useUISettings`) | — | — | — | — | **reject — stop condition 4.** Reuse it |
| 25 | Campaign recipient count before send | [CODE] **exists**, server-side, debounced, abortable, unknown ≠ 0 | — | — | — | — | **reject — already covered** |
| 26 | Automation clone | [CODE] **exists** (`automations/clone`) | — | — | — | — | **reject — already covered**; recipes reuse the same mental model |
| 27 | Flow unsaved-changes guard on in-app navigation | [CODE] **exists** | — | — | — | — | **reject — already covered**; only the reload case is added (#7) |
| 28 | Contacts list context on return (search / page / filter) | [CODE] **already correct** — `query: route.query` is forwarded, `router.back()` returns | — | — | — | — | **reject — already covered** |
| 29 | Contact copy email / phone, open contact in new tab | [CODE] **exist** | — | — | — | — | **reject — already covered** |
| 30 | Commerce open-provider-order, track-shipment, send-tracking, remembered panel view | [CODE] **exist** | — | — | — | — | **reject — already covered** |
| 31 | Smart defaults: last selected inbox / store / team | [CODE] partly — Commerce panel view is remembered; campaign and flow forms are not | Medium [HYP] | Low | Medium | Medium | **narrow to one case** — recipe wizards preselect when exactly one candidate exists (§"smart resource mapping"); no new remembered-form state |
| 32 | Double-submit protection on convenience actions | [CODE] existing forms use `isLoading` / `disable-confirm-button` | — | Medium | Low | High | **follow the existing pattern** in everything added |

## 2. What the scoring selects

Implement = **High frequency ∧ High impact ∧ High confidence ∧ Low–Medium risk**, and not already covered.

That is rows **1–16**, of which 4, 13 and 15 are the recipe work, plus the guard rails from 31–32 applied to
everything new. Rows 17–19 are deferred or rejected on their merits; rows 20–30 are rejected because the
functionality already exists, which is itself the main finding of this phase:

> **Chatwoot's conversation loop, search, shortcuts, bulk actions and preference storage are already strong. Lynomia's
> own additions — Flow Builder, Audiences, Commerce — are where the product still makes people start from nothing and
> navigate by memory.** That is where this phase spends its budget.

## 3. Risk notes on the selected rows

| Row | Risk | Mitigation |
|---|---|---|
| 1 | a command entry could expose a page the user cannot open | entries are gated by the resolved route's `meta` exactly like the existing 30 — the mechanism is not changed |
| 2 | mislabelling draft state | the signal is exact: publishing converts the draft row into the published row, so `draft && published` **is** "unpublished changes". No heuristic |
| 3 | duplicating a flow could copy references the target account must not have | a flow is duplicated inside its own account only; the copy's graph is re-validated by `Flows::GraphValidator` on draft save, and the copy starts unpublished with no inboxes |
| 4/13/15 | a recipe could create an invalid or unsafe object | recipes go through the same create + draft-save + validate path as hand-built objects; flows start as a draft, rules disabled, audiences saved only on explicit confirm |
| 6/7 | intercepting keys / `beforeunload` could annoy | `Cmd+S` is bound only inside the builder and only prevents the default when it saves; the `beforeunload` guard is registered only while the graph is dirty and removed on unmount |
| 8/9 | prefilled creation could bypass a policy | the prefill is a route query the target page reads; the target page's own `meta.permissions`, its form and the server's policies are unchanged. A user without Campaign permission cannot reach the campaigns route at all |
| 16 | none | clipboard write with an existing shared helper, with an alert on success |
