# Feature package A — Audit trail: the read surface

> Clean-room specification. It states what Lynomia needs and what its callers already depend on. It does not
> describe any previous implementation, and it must not be read as a design.

## 1. Purpose

An account administrator must be able to answer, without a terminal, "who changed this, when, and from where?"
Lynomia relies on this for three business reasons:

- **Operator accountability.** Several Lynomia subsystems (support cases, contact merges, commercial
  entitlement overrides, WhatsApp template changes, store connections) deliberately write an audit entry at the
  moment a human changes a customer's reality. Those entries are worthless if nobody can read them.
- **Customer support.** When a customer asks why a setting changed, the trail is the answer.
- **Shipped product surface.** Settings → Audit Logs is a documented Lynomia feature
  (`custom/db/documentation/en/administration/audit-logs.md`). It is advertised and must work.

## 2. Public / internal contract

### Endpoint

`GET /api/v1/accounts/:account_id/audit_logs`

Authenticated account API (the same session or access-token authentication every other account endpoint uses).

### Inputs (query parameters, all optional)

| parameter | type | meaning |
|---|---|---|
| `page` | integer | 1-based page number; default 1 |
| `type` | string | restrict to one event type; absent or an "all" sentinel means no restriction |
| `sort` | `asc` \| `desc` | chronological order; default newest first |
| `since` | integer (unix seconds) | lower bound on entry time |
| `until` | integer (unix seconds) | upper bound on entry time |
| `range` | string | an opaque label the client round-trips for its own date-picker state; the server may ignore it |
| `user_id` | integer | restrict to one actor |

Unparseable or out-of-range values must not raise. They are either ignored or answered with an empty page; they
must never produce a 500.

### Output

A JSON object with these keys. Every one is already consumed by
`app/javascript/dashboard/store/modules/auditlogs.js` and must keep its name and type:

| key | type | meaning |
|---|---|---|
| `audit_logs` | array of entries | the page |
| `total_entries` | integer | total matching the filter, not the page size |
| `per_page` | integer | page size actually applied |
| `current_page` | integer | page returned |

Each entry must carry at least these keys, which the frontend reads by name
(`app/javascript/dashboard/helper/auditlogHelper.js`, `routes/dashboard/settings/auditlogs/Index.vue`):

| key | type | notes |
|---|---|---|
| `id` | integer | |
| `action` | string | the verb; see §4 for the vocabulary |
| `auditable_type` | string | the kind of record affected |
| `auditable_id` | integer | |
| `user_id` | integer or null | the actor, when one is known |
| `username` | string or null | a display name for the actor, so a row remains attributable after the actor's own record is gone |
| `audited_changes` | object | see §4 |
| `created_at` | integer or ISO-8601 timestamp | what the UI formats |
| `remote_address` | string or null | see §5 |

The response must **not** include a geographic location for the entry. That capability is deliberately absent
from Lynomia (see §9).

### Errors

| condition | response |
|---|---|
| unauthenticated | the account API's standard 401 |
| authenticated but not an administrator of this account | the account API's standard authorization refusal (403/401 as the surrounding API already does) — never a 200 with another account's data |
| the account does not have the audit capability enabled | **200 with an empty page**, not an error. The page must render as "nothing to show" rather than as a failure |
| a malformed filter value | 200 with an empty or unfiltered page |

### Authorization

Administrators of the account only. An agent — including one holding any named permission from package C — must
not be able to read the trail.

### Tenant scope

Entries for the requesting account only, decided from the authenticated session's account rather than from any
request parameter. A caller must not be able to reach another account's entries by supplying an id, a filter, a
sort or a page.

## 3. Data contract

The `audits` table already exists in `db/schema.rb` and is the accepted store. Available columns:
`auditable_id`, `auditable_type`, `associated_id`, `associated_type`, `user_id`, `user_type`, `username`,
`action`, `audited_changes` (jsonb), `version`, `comment`, `remote_address`, `request_uuid`, `created_at`,
`city`, `country`, `country_code`.

Indexes that already exist and are worth knowing about: `(associated_type, associated_id, created_at)`,
`(associated_type, associated_id)`, `(auditable_type, auditable_id, version)`, `(created_at)`, `(request_uuid)`,
`(user_id, user_type)`.

- `city`, `country`, `country_code` must stay unwritten and unread. They are present because the table is
  shared with upstream; Lynomia does not resolve locations.
- `user_type` exists because an actor is not always a person: a machine credential can act. The read surface
  must tolerate a non-person actor without failing.
- No schema change is required for this package. If the implementer wants one, it must be additive and
  justified separately.

## 4. Observable behaviour

**Event vocabulary.** The frontend builds its label from the entry's `auditable_type` lower-cased, a colon, and
`action` lower-cased — for example `inbox:create`. The full set of pairs it has labels for is enumerated in
`app/javascript/dashboard/helper/auditlogHelper.js`; that file is the contract. An entry whose pair is not in
that list renders unlabelled, which is a defect to avoid rather than an error to handle.

Three pairs need more than the pair itself, and the frontend already expects it:

- a membership change distinguishes self-edit, edit-of-another and edit-of-a-deleted-user, and reads the changed
  role and availability values out of `audited_changes`;
- a deleted conversation prefers a human-facing conversation number from `audited_changes` over the raw id;
- a deleted message needs the conversation it belonged to, from `audited_changes`.

**Scenarios**

- Given an account with audit entries, when an administrator opens the page, then the newest entries are
  returned first with a correct total and page size.
- Given `sort=asc`, when the page is requested, then the oldest entries come first.
- Given `since` and `until`, when the page is requested, then only entries within that window are returned and
  `total_entries` counts only those.
- Given `type=<one event type>`, when the page is requested, then only entries of that type are returned.
- Given `user_id=<an actor>`, when the page is requested, then only that actor's entries are returned.
- Given a page number beyond the last page, when it is requested, then an empty `audit_logs` array is returned
  with the real `total_entries`, and no error.
- Given an entry whose actor record has since been deleted, when the page is requested, then the entry is still
  returned and still attributable through `username`.
- Given an entry written by a machine credential rather than a person, when the page is requested, then the
  entry is returned without error.
- Given two accounts each with entries, when account A's administrator reads the page, then no entry belonging
  to account B appears under any combination of filters.
- Given an account without the audit capability, when an administrator reads the page, then an empty page is
  returned and the UI shows its empty state.

## 5. Security rules

- **Tenant isolation** is the first rule: scope from the authenticated account, never from input.
- **Address disclosure is gated.** `remote_address` must be reduced to a coarse form by default, and returned in
  full only when the account has the `audit_log_ip_address` capability enabled (`config/features.yml`). A
  coarse form for IPv4 must not disclose the host, and for IPv6 must not disclose the interface identifier. A
  blank or unparseable stored address must produce a null rather than an exception.
- **No secret may appear in an entry.** `audited_changes` is rendered to a browser, so the read surface must not
  emit provider credentials, tokens, signing secrets, passwords or payment data. Package B carries the
  obligation not to *write* them; this package must not re-expose anything that slipped through, so a field
  whose name or value looks like a credential should be withheld rather than rendered.
- **No message content.** A deleted message's entry must not carry the message body or its attachments. Today
  this is enforced here, in the renderer, because the body reaches the store; package B §5 asks for it to be
  kept out of the store instead. If that is done, this surface needs no per-type special case — a simpler read
  path and one less place for the rule to be forgotten.
- Authorization is decided on the server. Hiding the menu entry is not sufficient.

## 6. Failure behaviour

| situation | required behaviour |
|---|---|
| the referenced record no longer exists | the entry is still returned; the UI falls back to the recorded id |
| the actor no longer exists | the entry is still returned and still names the actor via `username` |
| `audited_changes` is empty or holds an unexpected shape | the entry is returned; the row renders without the detail rather than failing the page |
| a stored address is unparseable | null, no exception |
| the capability is off | empty page, 200 |
| the page is requested concurrently with new entries arriving | no requirement for a stable snapshot; a shifting total is acceptable |

## 7. Callers and dependents

| caller | depends on |
|---|---|
| `app/javascript/dashboard/api/auditLogs.js` | the route and that it accepts arbitrary query parameters |
| `app/javascript/dashboard/store/modules/auditlogs.js` | `audit_logs`, `total_entries`, `per_page`, `current_page` |
| `app/javascript/dashboard/helper/auditlogHelper.js` | `auditable_type`, `action`, `auditable_id`, `user_id`, `audited_changes`, and the event-pair vocabulary |
| `app/javascript/dashboard/routes/dashboard/settings/auditlogs/Index.vue` | `created_at`, `remote_address`, the meta keys, and the `audit_logs` feature gate on the page |
| `app/javascript/dashboard/routes/dashboard/settings/auditlogs/components/AuditLogFilters.vue` | the `type`, `sort`, `since`, `until`, `range` parameter names |
| `custom/db/documentation/en/administration/audit-logs.md` | the documented behaviour of the page |
| P9, P10, P11 writers | that what they record is readable here |

## 8. Acceptance criteria

1. Every scenario in §4 passes as a black-box request/response test.
2. Every response key in §2 is present with the stated type, for both a populated and an empty page.
3. An agent, and a user holding each named permission from package C, is refused.
4. A member of another account cannot retrieve an entry, under any filter, sort or page.
5. With the address capability off, no full address appears in any response; with it on, it does.
6. No response contains a credential-shaped value. A test that plants a credential-shaped key in
   `audited_changes` and asserts it is not rendered is the clearest form.
7. No response contains a geographic location field.
8. A single page render issues a query count that does not grow with the number of entries on the page.

## 9. Non-requirements

Stated so the new implementation does not grow them back:

- **No IP geolocation.** No city, country or country-code resolution, no lookup service, no background job for
  it. The columns stay unwritten.
- **No export.** No CSV or scheduled delivery of the trail.
- **No retention or purge policy** in this package.
- **No cross-account or installation-wide view.** The Super Admin Operations Center covers operator-wide
  questions; this surface is one account's.
- **No write path.** Package B owns writing.
- **No real-time updates.** The page fetches on demand.
- **No search over free text.** The documented filters in §2 are the whole filter surface.
- **No per-entry permissions.** Administrator-or-nothing.
