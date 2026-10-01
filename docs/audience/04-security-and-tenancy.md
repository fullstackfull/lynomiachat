# Lynomia Audience: security and tenancy

Audiences reuse Chatwoot's contact filter and saved-segment security, unchanged. This document lists what Lynomia's
additions rely on, what they add, and how each requirement is tested. Test names refer to
`spec/services/contacts/filter_service_audience_spec.rb` (service), `spec/controllers/api/v1/accounts/contacts/audiences_spec.rb`
(request) and `spec/models/commerce/contact_metric_spec.rb` (model); E2E checks to
`docs/audience/e2e/results/e2e_audience.txt` ([05 §E2E](05-performance.md#e2e)).

## 1. Tenant isolation

| Layer | Isolation |
|---|---|
| Saved audience | `Current.account.custom_filters.where(user: Current.user)` (Chatwoot): another account's or another user's audience id is **404** |
| Evaluation | base relation `Current.account.contacts` (Chatwoot); the account comes from the URL **and** the user's membership, so a forged account id is **401** |
| Commerce conditions | every subquery pins `audience_links.account_id = :audience_account` (the current account, bound) and joins the store through the link; a store id of another account matches nothing |
| Conversation conditions | `@account.conversations` scoped by `Conversations::PermissionFilterService` |
| Builder options | `/commerce/audience_fields` reads the current account's counted stores and summaries only |
| Summaries | `commerce_contact_metrics.account_id` is copied from the link at write time and cascades with the account |

Tests: request "never evaluates another account's contacts", "is not reachable by another user, nor through another
account", "is unavailable without Lynomia Commerce and to other accounts"; service "ignores a store id of another
account"; E2E "another account can neither evaluate this account's contacts nor read its audience" (401 / 404).

## 2. Permissions

No new permission flag. The existing ones cover the workflow:

| Action | Policy (existing) | Who |
|---|---|---|
| Filter contacts, preview, count | `ContactPolicy#filter?` | every account member |
| Create / read / update / delete own audiences | `CustomFilterPolicy` | administrators and agents, own audiences only |
| Builder Commerce options | `authorize(Contact, :filter?)` + the `lynomia_commerce` feature | every account member of a Commerce account |
| Conversation conditions | `Conversations::PermissionFilterService` (and Enterprise custom roles) | each user sees only their own conversations' facts |
| Audit log | `AuditLogsController#check_admin_authorization?` (Enterprise) | administrators |

Commerce conditions answer coarse facts (for example "has more than SAR 1,000 of visible spend") about any contact of
the account to anyone who may filter contacts, as contact attributes and custom attributes already do in Chatwoot.
Orders themselves stay behind Customer 360, which still requires access to the conversation. If an account needs
Commerce segmentation restricted to administrators, the place for it is a custom-role permission in Phase 2, not a
second permission system.

## 3. Query safety

- **Fixed SQL per key.** A request selects a key from a fixed list (`ConversationCondition::FIELDS`,
  `CommerceCondition::FIELDS`, `SPEND_FIELD` = `/\Acommerce_spend_([a-z]{3})\z/`); column names never come from input.
- **Bind values only.** Every value, the account, the provider list and the enum integers are bind parameters; label
  names are binds of the outer query (service "keeps label names out of the SQL text": `x') OR 1=1 --` and
  `:audience_0` match nothing and raise nothing).
- **Allowlisted operators and values.** Wrong operator → 422; ids must be base-10 integers, statuses and providers must be
  known values, amounts finite non-negative decimals, dates ISO 8601, `days_before` 1–998 (service "rejects values
  outside what the field documents", including `woocommerce' OR 1=1 --`, `NaN`, `-1`, `closed`, `0`).
- **Bounded work.** At most 10 conversation/Commerce conditions and 50 values per condition (service "bounds the number
  of conditions and of values"); every condition is an indexed `EXISTS` or a per-contact aggregate over that contact's
  few links; the page size is Chatwoot's fixed 15; the count is a single `COUNT(*)`. No user input reaches `ORDER BY`,
  `LIMIT` or a table name.
- **422, not 500.** Every rejection is one of Chatwoot's `CustomExceptions::CustomFilter::*`, rendered as 422 by
  `ContactsController#filter` (request "answers 422 for a condition it cannot evaluate"; E2E "malformed, injected,
  unknown, wrong-operator and oversized conditions answer 422").

## 4. Provider gates and remote calls

- Evaluating, counting or opening an audience makes **no HTTP request**: the SQL reads Postgres only. Tested in the
  service ("never calls a store": WebMock sees no request), the request spec, the E2E (WooCommerce access log unchanged
  across every audience request) and at volume (0 outbound requests over 10k and 100k contacts, [05](05-performance.md)).
- **Hard-off.** Only stores of providers in `Commerce::Providers.enabled` count; in production Salla, Zid and Shopify are
  NO-GO and stay off. Their stores are not offered in the builder and any summaries they left contribute nothing (service
  "never counts a suppressed link, a disabled store or a provider the installation switched off"; E2E "a store of a
  switched-off provider never counts (Hana's Salla summary of SAR 99,999)").
- Summaries are written only by the existing reads, which keep their own gates (03 §4).

## 5. Deleted, unlinked and suppressed

- **Suppressed link** (an agent's unlink): excluded from every condition (store, platform, orders, spend, statuses) and its
  summary deleted at once; only an explicit new link counts again (model "is dropped when its link is removed or points to
  another customer"; E2E "an agent removing Omar's link drops him from the audience at once").
- **Re-pointed link**: summary deleted, unknown until read.
- **Deleted store, link, contact or account**: FK cascades remove the summaries; nothing stale stays queryable.
- **Disabled / disconnected store**: excluded while not active.

## 6. Unknown data

Unknown never matches as zero and never passes a negation (03 §6): service "does not treat a contact whose orders were
never read as zero", "decides 'more than' from the known stores, 'less than' only when every store is known"; model
"records a known empty history as zero, and never lets an older read replace a newer one"; E2E "unknown is never zero".

## 7. Privacy

- The builder receives stores as `{ id, name, provider }` (no URL, no credentials), currency codes, and one count of
  unread contacts. The E2E checks that no response the browser received contains a store key or secret.
- Summaries hold no personal data: no name, email, phone, address, payment record, item, shipment object or raw webhook;
  only counts, a date, paid totals per currency and normalized statuses of an already-matched link (03 §2). Shopify's
  protected-customer-data rules are unaffected (and Shopify is off in production).
- Membership is never stored, so there is no member list to leak or to keep in sync.

## 8. Audit

Chatwoot does not audit saved filters. Lynomia audits **audiences** only:

- `Custom::Audit::CustomFilter` (`audited associated_with: :account, if: :contact?`, when `Enterprise::AuditLog` is
  loaded) records create, update and destroy of contact custom filters, with the account, the user and the changes
  (name, query). Conversation folders and report filters stay unaudited, as in Chatwoot.
- The Enterprise audit log page names them ("{agent} created a new audience (#id)", updated, deleted; English and
  Arabic) and filters them under Configuration → Audiences (`auditlogHelper.js`).
- Membership changes are not audited: they are evaluated, not events, so there are no per-contact audit rows.

Test: request "records audience changes in the audit log, and leaves conversation folders out"; Vitest "should name
saved audiences (contact custom filters)".

## 9. Mandatory security tests

| Requirement | Where |
|---|---|
| Audience cross-tenant access | request: another account / another user (404); E2E (401 / 404) |
| Forged account id | request and E2E: a user of another account posting to this account's URL → 401 |
| Malformed filter payload | request + E2E: 422 |
| Unauthorized saved-audience edit | request: another user's audience → 404 on show and update, name unchanged; another account → 404 |
| Unsupported field injection | service: unknown key → `InvalidAttribute`; E2E 422 |
| SQL / search injection | service: provider and label injection strings; E2E injected condition → 422 |
| Expensive / unbounded query | service: 11 conditions, 51 values → 422; E2E oversized → 422 |
| Deleted store | model: link and store cascades; service: disabled store excluded |
| Suppressed link | service + model + E2E |
| Provider disabled | service + E2E (Salla off) |
| Unknown Commerce metric | service + model + E2E |
