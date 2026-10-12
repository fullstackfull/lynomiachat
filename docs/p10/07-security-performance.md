# P10 — Security, performance and hardening

What was measured, what was closed, and what was found and deliberately left. The query plans in §3 were run
against fixtures built for the purpose; the method and its one earlier failure are recorded with them.

---

## 1. Secrets (PART P)

### 1.1 Three credentials were sent to the browser in plaintext

| credential | model | was | is |
| --- | --- | --- | --- |
| `channel_email.imap_password` | `encrypts :imap_password` | serialized in full to any administrator | `imap_password_configured` boolean |
| `channel_email.smtp_password` | `encrypts :smtp_password` | serialized in full to any administrator | `smtp_password_configured` boolean |
| `channel_twilio_sms.auth_token` | `encrypts :auth_token` | serialized in full to any administrator | `auth_token_configured` boolean |

Each is **encrypted at rest** when encryption is configured — the code already treats all three as secrets — and
the inbox payload was the one place each existed in plaintext: in the browser's memory, in devtools, in any
log or proxy that captured the response, and reachable by anything that could read it.

**Masking alone would have been a data-loss bug.** `ImapSettings.vue` and `SmtpSettings.vue` pre-filled the
field from the payload and sent it back on every save, so an empty field would have wiped the stored password.
Three things changed together:

1. the serializer reports configured-or-not;
2. `Custom::Channel::Email#with_stored_credentials` makes a **blank value mean keep**, and the inboxes
   controller now asks any channel that responds to it rather than only WhatsApp;
3. the two forms start empty, say *"Leave blank to keep the current password"*, and no longer demand a password
   once one is stored — otherwise an administrator could not change the server address without retyping it.

That is the contract the Super Admin app-config pages already use for their secrets, and the shape
`Channel::Whatsapp#with_stored_credentials` already used for its `provider_config` keys. Twilio needed no
keeper: nothing in the dashboard reads `auth_token` back from the payload — the Twilio form only ever sends one
— and `validates :auth_token, presence: true` would refuse a blank anyway.

Seven examples in `spec/requests/channels/p10_credential_exposure_spec.rb` cover it: the key is absent, the
value appears nowhere in the body, the boolean is right in both states, a blank save keeps the stored password,
a typed one replaces it, and a secret the save did not mention is left alone.

### 1.2 What is still serialized, and why that is right

| field | kept because |
| --- | --- |
| `channel_api.hmac_token`, `channel_api.secret` | these are **this installation's own** tokens, which the administrator has to copy into their client. There is a `reset_secret` / `rotate_hmac_token` endpoint for rotation. Hiding them would break the feature. |
| `channel_web_widgets.hmac_token` | same: it is for the customer's own integration |
| `account_sid`, `api_key_sid`, `page_id`, `instagram_id`, `business_id`, `line_channel_id`, `profile_id` | identifiers, not secrets |
| `provider_config` minus `SECRET_PROVIDER_CONFIG_KEYS` | WhatsApp already masked its own secrets; unchanged |

### 1.3 Nothing P10 added carries a secret

- `contact_identities` holds a phone number or an email address — customer data, never a credential — and those
  values are **never** written to a log line or an audit row. The merge audit carries ids and counts only, and a
  spec asserts the serialized payload contains neither contact's values.
- `Channels::ConnectionState` reports that a WhatsApp health check failed **without quoting the provider's
  message**, because that message can carry a request URL and an id. A spec asserts the component's JSON
  contains neither the planted secret nor `graph.facebook.com`.
- The identities API returns the identity values themselves, which is the point of the panel, to callers who may
  already see `contacts.phone_number` and `contacts.email`. No new class of data is exposed.

## 2. Tenant isolation

`spec/requests/contacts/p10_identity_isolation_spec.rb` builds **two tenants holding the same phone number and
the same email address**, which is the fixture that catches a filter keyed on the wrong thing: a query missing
its `account_id` returns the other tenant's row and looks like a hit.

| asserted | result |
| --- | --- |
| the same value may exist in two accounts | yes — identity is per account, and the unique index is scoped to it |
| the list returns only this account's row | yes |
| reading another account's contact | 404 |
| reading your own contact through another account's id | 401 |
| unlinking another account's identity | 404, row intact |
| linking a value another **account** holds | allowed, no conflict reported |
| the inbound match | resolves to this account's contact, not the other holding the same number |
| merging a mergee from another account | 404, mergee intact |

The account scope itself is not re-implemented: the controller inherits
`Api::V1::Accounts::Contacts::BaseController`, which finds the contact through `Current.account.contacts`, so a
foreign id is 404 before any policy runs.

## 3. Query plans

Method, and the trap it avoids: fixtures are spread across **50 accounts** rather than concentrated in one. A
single account holding the whole table makes a sequential scan genuinely cheaper, so a plan measured that way
proves nothing — the method failure recorded in `docs/p9/06-security-performance.md` §2, pass 2.

Fixture scale and the measured plans are in §3.1. Each new index is justified by a query the product actually
issues (docs/p10/03-unified-customer-identity.md §3, QUERY SHAPES); no index was added speculatively, and the
two controls in §3.1 show what each one is worth.

### 3.1 Fixtures

| table | rows |
| --- | --- |
| `accounts` | 50 |
| `contacts` | 200,000 (4,000 per account; one in five carries a TikTok user id) |
| `contact_identities` | 100,000 (one per even-id contact) |
| `operations_signals` | 20,000, of which 5,000 open, all with `subject_type: 'Inbox'` |

`ANALYZE` was run on all three before measuring. `EXPLAIN (ANALYZE, BUFFERS)`.

### 3.2 The plans

| # | query | plan | time |
| --- | --- | --- | --- |
| Q1 | the inbound identity fallback: `account_id = ? AND identity_type = ? AND value IN (?)` | Index Scan using `index_contact_identities_on_account_type_value` | **0.091 ms** |
| Q2 | the linker's cross-check: the same three columns, one value | Index Scan, same index | **0.027 ms** |
| Q3 | the Contact validation: the same, plus `contact_id != ?` | Index Scan, same index | **0.018 ms** |
| Q5 | one contact's identities panel: `contact_id = ?` | Index Scan using `index_contact_identities_on_contact_id` | **0.022 ms** |
| Q6 | the Operations channels column: open `Inbox` signals for a page of 25 accounts, `COUNT(DISTINCT subject_id)` grouped | Unique over an Index Scan on `index_operations_signals_on_open_feed` | **2.233 ms** |
| **Q7** | **control:** Q2 with `index_contact_identities_on_account_type_value` dropped | **Seq Scan** on 100,000 rows | **8.311 ms** |

Q7 is what the index is worth: the same question, 300× slower, on a table that in production grows with every
link an agent makes and every merge that absorbs a value. Q1 is the one on the hot path — the inbound branch
that was about to create a duplicate contact — and it is an index probe.

### 3.3 The TikTok index was wrong, and the plan said so

The first version of this index was `(account_id, (additional_attributes ->> 'social_tiktok_user_id')) WHERE
additional_attributes ? 'social_tiktok_user_id'`. It read sensibly and it was **never used**. Finding that is
the whole reason PART Q asks for the plan.

Measured on one account holding **200,000 contacts, 40,000 of them carrying the key** — the realistic shape for
a large tenant, and a different question from the 50-account fixture above, which is about index choice rather
than scan-versus-index:

| index | plan | time |
| --- | --- | --- |
| `(account_id, expr)` partial | parallel Index Scan on `index_contacts_on_account_id` — **the new index unused** | 21–26 ms |
| `(expr, account_id)` partial | still unused | 20–22 ms |
| **`(expr, account_id)` not partial** | **Index Scan using `index_contacts_on_social_tiktok_user_id`** | **0.045 ms** |

Two separate mistakes, both now fixed in the migration:

1. **The expression has to lead.** `account_id` is not selective *inside the account doing the asking* — a large
   tenant's own id matches every one of its rows — so an index that starts with it is no better than the plain
   `account_id` index the planner already had.
2. **The index cannot be partial.** PostgreSQL uses a partial index only when it can prove the query implies the
   predicate, and `(additional_attributes ->> 'k') = 'v'` does not prove `additional_attributes ? 'k'`: the two
   operators are unrelated to the prover. Adding the containment test to the query did not help — both partial
   variants above were measured with and without `jsonb_exists(...)`, and neither was used.

So the index covers every contact rather than only the TikTok ones. At this scale that is **4,712 kB against a
61 MB table** — 7.7% — which is the price of an index that is actually used.

Re-measured against the fragment the product actually ships
(`Custom::ContactInboxWithContactBuilder::SOCIAL_IDENTITY_LOOKUPS`): **Index Scan, 0.056 ms**. The branch this
runs on is the one that was about to create a duplicate contact, so the alternative to 0.056 ms is not 21 ms —
it is a second customer record.

Q6 confirms the choice made in docs/p10/06-channel-lifecycle-health.md §4: the Operations Center reads durable
signals with **one grouped query for a whole page**, not a Redis read and a channel load per inbox. 2.2 ms for
25 accounts, and the query count does not grow with the page.

## 4. Rate limiting

No new throttle. The identities endpoints are per-contact writes behind an administrator-or-`contact_manage`
policy, reached from one panel, and `config/initializers/rack_attack.rb` already throttles the account's API
surface. P9 added per-user throttles for the support and analytics paths because those are list endpoints a
dashboard polls; this is not that shape. Recorded as a decision rather than an omission.

## 5. Found and deliberately left

Each of these is real, verified first-hand, and outside what P10 should change blind. They belong in the
P-FINAL security audit with the evidence below.

| finding | evidence | why not here |
| --- | --- | --- |
| **Bandwidth SMS webhook is unauthenticated** and picks the tenant from a body field (`params[:to]`) | `app/controllers/webhooks/sms_controller.rb` has no signature, secret or timestamp check | a cross-tenant injection path on a channel with no credential here to test against; it is a security repair, not identity work (docs/p10/02-channel-capability-matrix.md §5) |
| **Bandwidth delivery receipts always raise** | `app/jobs/webhooks/sms_events_job.rb:19` passes `channel:` to a `pattr_initialize [:inbox!, :params!]` service | same channel, same reason |
| **Bandwidth batched webhooks drop events** | only `params['_json']&.first` is enqueued | same |
| **TikTok OAuth `state` has no `exp`** | `app/helpers/tiktok/integration_helper.rb` builds `{sub:, iat:}` while `decode_token` passes `verify_expiration: true` | needs a TikTok app to verify the round trip |
| **TikTok webhook replay guard is one-sided** | rejects only `delay > 5`, so a future timestamp passes | same |
| **TikTok webhook is never registered** | `Tiktok::AuthClient#webhook_callback` has no callers | same |
| **Voice calling posts to four endpoints that do not exist** | no routes, no controller actions; `InboxPolicy` declares all four | implementing them is a new feature (docs/p10/02-channel-capability-matrix.md §3b) |
| **WhatsApp inbound routes on `display_phone_number`, not `phone_number_id`** | `Whatsapp::WebhookChannelFinderService:12-19` | the inbound path of the channel production runs; cannot be exercised without a real Meta webhook (§3a of the matrix) |

## 6. What was checked and found to be fine

- **`Contacts::ContactableInboxesService` does not leak inbox existence.** An earlier reading of this project's
  own discovery document said it did. It does not: the service is unfiltered, but its only caller filters the
  result through `policy(inbox).show?`, which is `Current.user.assigned_inboxes.include?(record)`. Corrected in
  `docs/p10/00-discovery.md` §10. What remains true is a trap rather than a defect — the filter lives in the
  controller, so a second caller would not inherit it.
- **`SearchService#filter_contacts`** searches all account contacts with no inbox filter. Unchanged, and
  consistent with `ContactPolicy#index?`; conversations and messages in the same response *are* filtered.
- **`reporting_events` has no contact column**, so a merge cannot alter a figure P8 has already reported.
- **`flow_sessions` keys on the conversation**, so a flow's state follows the surviving customer with no change
  to P10's code.
- **`calls`** has a `contact_id` but no model, no foreign key and no writer in this fork, so there is nothing
  for a merge to move. Consistent with voice being non-functional (§5).
