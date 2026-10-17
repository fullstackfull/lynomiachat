# ADR-001 — Partner Consent & Messaging Eligibility

**Status:** proposed, for approval before implementation
**Phase:** 5E
**Date:** 2026-10-15
**Supersedes:** the proposal to ungate `Api::V1::Accounts::Commerce::ConsentsController` for every account

---

## 1. Context

P5E.1 and P5E.2 closed a live defect: no campaign sender checked consent, opt-out, suppression
or `contact.blocked?`. Enforcement now sits at `Campaign#audience_contacts`, the one entry
point all four senders, the preview and the recipient snapshot share, and the class of a
message is taken from the provider's own classification.

Making that fail-closed exposed a gap. The consent **store** is universal —
`Commerce::ConsentListener` writes a withdrawal for any account on any inbound STOP — but the
consent **grant surface** is behind `ensure_commerce_enabled`. An account that does not run
Commerce therefore has no authorized way to record that a shopper agreed, so under the
corrected policy its promotional campaigns reach nobody and it cannot fix that itself.

The rejected fix was to ungate the native surface for everyone. That would change the product
for independent Lynomia customers to solve an integration problem, which is the wrong trade.
This ADR takes the other path: a partner-scoped subsystem that leaves the native one alone.

---

## 2. What already exists (verified against `db/schema.rb`, not assumed)

**Most of the required architecture is already here.** This is the central finding of the
inspection and it determines how small the change can be.

| Requirement | Existing mechanism | Verdict |
|---|---|---|
| Registered partner/platform identity | `platform_apps` (id, name) + `Commerce::Providers::REGISTRY` (`woocommerce, salla, zid, shopify, storesyria`) | **reuse** — two complementary identities: the app is *who authenticated*, the provider is *which platform* |
| Partner installation identity | `commerce_stores` — `UNIQUE (provider, external_store_id)`, with `status`, `credentials`, `settings` | **reuse** — this is the installation registry for commerce partners |
| Bound Lynomia account | `commerce_stores.account_id`; `platform_app_permissibles` confines an app to accounts it may reach | **reuse** |
| Partner-specific customer identity mapping | `commerce_customer_links` — `UNIQUE (commerce_store_id, contact_id)`, carries `external_customer_id` and `match_source` | **reuse** — already the verified subject mapping |
| Integration lifecycle / revocation | `commerce_stores.status` (connected / disconnected) | **reuse** |
| Partner-scoped quota precedent | `platform_app_entitlement_grants` — `UNIQUE (platform_app_id, account_id, resource)`, composes by MAX | **the pattern to copy** |
| Suppression & eligibility primitives | `Commerce::MessagingEligibility`, `Campaigns::Eligibility` | **share, do not fork** |
| Sending engines | four senders + `TriggerScheduledItemsJob` | **do not touch** |

**The only genuine gaps are two:**

1. No consent record carries a partner, an installation, a channel, a policy version, a capture
   or withdrawal time, or the actor who asserted it. `commerce_messaging_consents` is
   `UNIQUE (contact_id, purpose)` — one decision per person per class, account-wide, with no
   scope and no provenance beyond a 40-character `source` string.
2. Nothing records that a campaign originated with a partner. `campaigns` has no
   `platform_app_id`, `commerce_store_id` or equivalent column (verified).

---

## 3. Decision

### 3.1 Minimum schema changes

**One new table and one new column.** Nothing else.

```
partner_consents
  platform_app_id      bigint  not null   -- who asserted it (provenance)
  account_id           bigint  not null   -- bound Lynomia account
  commerce_store_id    bigint  not null   -- the partner INSTALLATION
  contact_id           bigint  not null   -- the verified subject in Lynomia
  external_subject_id  string(128) not null -- the partner's own customer id
  purpose              integer not null   -- transactional | promotional
  channel              integer not null   -- any | whatsapp | sms | email
  state                integer not null   -- granted | withdrawn | suppressed
  source               string(40)  not null -- checkout_optin | preference_centre | merchant | ...
  policy_version       string(40)         -- the notice the customer was shown
  captured_at          datetime not null
  withdrawn_at         datetime
  evidence             jsonb   not null default {}
  recorded_by_id       bigint             -- the acting user, where there is one

  UNIQUE (commerce_store_id, contact_id, purpose, channel)
  INDEX  (account_id, state)
  INDEX  (platform_app_id, account_id)
```

```
campaigns.commerce_store_id   bigint  null   -- set when a partner created the campaign
```

**Why `commerce_store_id` is the installation rather than a new `partner_installations`
table.** `commerce_stores` is already multi-provider and already carries account binding,
status and credentials. A parallel installation registry would be the "second competing
model" this change is explicitly meant to avoid, and every commerce partner would then exist
in two places that could disagree. The cost is named rather than hidden: **a future
non-commerce SaaS partner has no store row**, and onboarding one means giving it an
installation row — §6 records that as the extension point.

**Why uniqueness is on `(commerce_store_id, contact_id, purpose, channel)` and not on
`contact_id`.** Two stores of the same merchant are two scopes; a grant at one is not a grant
at the other. Making the store part of the key is what makes "do not copy consent grants
across partners or accounts" a property of the schema rather than a rule in code.

**Why `external_subject_id` is stored but no other personal data is.** The subject is
identified by `contact_id`, which already exists. The partner's own id is kept so a withdrawal
arriving from the partner can be matched without a second lookup. No name, phone or email is
copied — `commerce_customer_links` already holds the mapping.

### 3.2 Shared versus isolated

| Component | Disposition |
|---|---|
| `Commerce::MessagingEligibility` | **shared, unchanged.** The native per-contact decision. |
| `Campaigns::Eligibility` | **shared, extended.** Gains the partner layer; the native behaviour is untouched when no partner scope applies. |
| Four senders, scheduler, snapshot | **untouched.** One final-boundary call is added; no sending logic is forked or duplicated. |
| `Commerce::ConsentsController` and the native consent UI | **untouched.** No gate is relaxed; independent Lynomia accounts see no change. |
| `commerce_messaging_consents` | **untouched.** No column, no semantic change, no backfill. |
| `PartnerConsent` model + `Partners::Consents` service | **new, isolated.** |
| Partner write API | **new**, under the Platform API namespace, authenticated as a Platform App and confined by `platform_app_permissibles`. |
| Store Syria merchant UI | **new**, on the Store Syria side, through the partner API. |

### 3.3 Exact final-send eligibility precedence

Evaluated per recipient **immediately before the provider call**, in this order. The first
refusal wins and nothing below it can overturn it.

| # | Check | Scope | Refusal code |
|---|---|---|---|
| 1 | Global outbound kill switch | installation-wide | `outbound_halted` |
| 2 | Partner installation revoked or disconnected | partner-originated sends only | `installation_revoked` |
| 3 | `contact.blocked?` | native, always | `contact_unavailable` |
| 4 | Native suppression for this purpose | native, always | `messaging_suppressed` |
| 5 | Native withdrawal for this purpose | native, always | `consent_withdrawn` |
| 6 | Partner suppression in scope | partner-originated only | `partner_suppressed` |
| 7 | Partner withdrawal in scope | partner-originated only | `partner_consent_withdrawn` |
| 8 | Promotional with no grant from **either** source | both | `promotional_consent_missing` |
| 9 | Provider rule (template category, auth-template guard) | per channel | existing codes |

**The two rules this ordering encodes:**

- **Negatives are unioned; positives are not.** Steps 3–7 mean either subsystem can refuse and
  neither can overturn the other. A native opt-out stops a partner-originated send; a partner
  withdrawal stops it too.
- **A positive grant is scope-bound.** At step 8 a partner grant counts only when its
  `commerce_store_id`, `purpose` and `channel` all match the send. A grant captured at one
  store's checkout authorises nothing at another store, for another class, or on another
  channel. A native grant remains account-scoped, as today.

**Snapshots are never the authority.** `Campaigns::RecipientSnapshot` records who was
addressed; steps 1–9 are re-evaluated against live rows at the boundary, so a withdrawal, a
suppression or a revoked installation taking effect after scheduling or after the snapshot is
honoured. This is the only place a second check is justified — the delay between resolving an
audience and sending to it is a genuine independent path, not a backup guard.

### 3.4 What is explicitly not built

A second messaging engine; a second scheduler; a second account or SSO model; a second
eligibility policy; a partner UI for any partner other than Store Syria; any speculative
partner integration. Cross-partner isolation is verified with **two isolated installation
fixtures**, which is the minimum that can demonstrate it.

---

## 4. Consequences

**Accepted.** Partner consent is a projection beside the native store rather than inside it,
so a reader must consult both — which is the cost of not changing native semantics, and is
mitigated by both being read through one shared entry point.

`campaigns.commerce_store_id` is nullable and unset for every existing campaign, so every
existing campaign is non-partner-originated and steps 2, 6 and 7 do not apply to it. Nothing
historical changes meaning.

**Still open after this ADR.** An account that runs neither Commerce nor a partner
integration still has no grant surface, so its promotional campaigns still reach nobody. That
is unchanged by this design and is deliberately left to the owner as a product decision about
Lynomia's own native product, recorded in the blocker register.
