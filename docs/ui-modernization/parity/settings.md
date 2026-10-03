# Parity record — Settings

What changed across the Settings surface in the tenth batch, and how each change was verified. The
manifests it is checked against are `audit/surface-settings-admin.md` §2 (376 features across 17 pages)
and `audit/surface-settings-crud.md` §2. The gate is `harness/parity.mjs`, run over the 67-surface
capture set in two locales at four widths.

## Verdict

| | |
|---|---|
| Manifest entries touched by this batch | 41 |
| PRESERVED | 41 |
| MOVED WITH JUSTIFICATION | 0 |
| REMOVED | 0 |
| Dead UI removed (declared unreachable in the manifest, or reachable from nothing) | 9 files |

Nothing a user can reach moved, so this batch adds no entry to `parity-exceptions.json`.

## Gate result

```
compared 536 captures
  lost 0   moved-with-reason 8   added 586   newly-named 1402   regressions 0
```

The eight moved-with-reason entries are the pre-existing canned-responses exception from an earlier batch,
not this one. The after capture reports **0 unnamed controls across all 67 surfaces**, against 1514 in the
pre-phase baseline; also 0 horizontal overflow, 0 wrong direction and 0 page errors, in both locales at
390 / 768 / 1024 / 1280.

## The coverage gap this batch opened with

Five settings pages were modernised in earlier batches — tables, `align-last-column-end`, loading
skeletons, the pagination footer — and **none of them had a capture**. The work was committed unverified.
Ten new surfaces were added before anything else was touched:

| Surface | Page | What it verifies |
|---|---|---|
| `webhooks-list` (+ `-empty`) | `integrations/Webhooks/Index.vue` | sortable header, row actions, empty state |
| `dashboard-apps-list` (+ `-empty`) | `integrations/DashboardApps/Index.vue` | two sortable columns, row actions, empty state |
| `integration-hooks` | `integrations/IntegrationHooks.vue` | the scrollable + sticky-actions table, the inbox column |
| `agent-bots-list` (+ `-empty`) | `agentBots/Index.vue` | the avatar column, row actions, empty state |
| `auditlogs-list` | `auditlogs/Index.vue` | the filter bar, the sortable Time column, the pagination footer |
| `integrations-list` | `integrations/Index.vue` | the integration card grid |
| `account-settings` | `account/Index.vue` | the account form, the transcription toggle, the build footer |
| `profile-settings` | `profile/Index.vue` | every profile section, including the notification matrix |
| `security-settings` | `security/Index.vue` | the SAML form and its disclosure |
| `data-imports` (+ `-empty`) | `data/Index.vue` | the import list in three states, and its empty state |

Three of those surfaces found defects on their first run, which is the point of adding them first.

## What the capture found that lint and tests did not

| Defect | Where | Fix |
|---|---|---|
| The access token field had **no label at all**, and its show/hide toggle no name | `profile/AccessToken.vue:35-58` | the field takes an `aria-label`; the toggle takes a name that changes with its state |
| Every copy button on the SAML page was a nameless icon | `security/components/SamlInfoSection.vue:90-98` | `Copy {field}`, naming the value it copies |
| The audio-tone preview button was a nameless icon | `profile/AudioAlertTone.vue:88` | named from the tooltip it already had |
| Every switch in the product announced "Toggle switch" | `components-next/switch/Switch.vue:31` | an optional `label` prop, passed by `SettingsToggleSection` and the seven other call sites |
| Every notification checkbox announced its storage key — `email_conversation_creation` | `v3/components/Form/CheckBox.vue`, `profile/NotificationPreferences.vue:216-222` | an optional `label` prop; the matrix passes "{notification} — {Email\|Push}" |
| Each integration card held a `<button>` inside a `<router-link>`: two controls, one action | `integrations/IntegrationItem.vue:79-91` and three more call sites | the link carries the name, the button is `aria-hidden` + `tabindex="-1"` — the convention the macros table already used |
| The hooks table printed raw setting keys as column headings: `Project_id`, `Language_code` | `MultipleIntegrationHooks.vue:35-41` | the keys are humanised for display; the values they address are untouched |

## Design-system work, not page work

- **A shared `EmptyState`.** The data-imports page had a designed empty state — icon medallion, heading,
  description, CTA — and four other settings pages answered the same situation with one centred sentence
  and no way to act on it, while an Add button sat in the header above. The designed one is now
  `components-next/empty-state/EmptyState.vue`; data imports, webhooks, dashboard apps and agent bots all
  render it, each with the action that fills the list.
- **The deprecated input stops carrying inline styles.** The identical literal
  `{ borderRadius: '0.75rem', padding: '0.375rem 0.75rem', fontSize: '0.875rem' }` appeared five times and
  had already drifted to `'12px'` / `'14px'` in a sixth. All ten `:styles` bindings are gone, the shape is
  said once in utilities, and the `styles` prop — the only route by which a caller could inline-style this
  input — is deleted.
- **Switch and CheckBox take a name.** Both are shared primitives whose accessible name was a constant.

## Nine dead files removed

`integrations/ShowIntegration.vue` imported `./IntegrationHelpText.vue`, which does not exist — the file
could not compile, and nothing imported it. `integrations/hookMixin.js` was referenced only by its own
spec; `useIntegrationHook` replaced it. `billing/components/{PurchaseCreditsModal,CreditPackageCard,BillingMeter}.vue`
were reachable from nothing. `profile/Wrapper.vue` and `profile/NotificationCheckBox.vue` were
unreferenced. `components/BaseSettingsListItem.vue` is manifest entry **S19**, which the audit itself
records as "unused on this surface" — and its hover-reveal action rail was unreachable by touch, so
nothing is lost by its going. `SLA.LIST.EMPTY` was four strings no code read.

Each was confirmed unreferenced by name across `app/javascript` before removal.

## Three things declined

- **Webhook event casing.** "Conversation Created, Message created" is real, and so is the same mixture
  through the rest of the settings strings. Fixing eleven values in one namespace would make webhooks
  consistent with itself and inconsistent with everything around it, and retranslates them at Crowdin.
  Recorded in `findings/deferred.md` as a copy decision for the whole product.
- **FormKit styling in the new-hook modal.** The unscoped global stylesheet is contained — every selector
  now sits under the modal's own root class, so it can no longer reach other FormKit forms — but the rules
  are still CSS. Moving them to FormKit's `classes` configuration touches every form built on it.
- **Five correctness defects** found while reading these pages (a failed fetch rendering as an empty list,
  the MFA wizard advancing past a rejected code, four silent error swallows, two downloads that cannot
  report failure, and the two nav items that both lead to billing). All are bugs, not presentation;
  recorded in `findings/deferred.md` with file and line.
