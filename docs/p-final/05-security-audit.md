# P-FINAL.2 — Security audit of the integrated release

Branch `claude/p-final-commercial-release-hardening`. Everything below was read or measured on this branch, and
each claim names where. Where a measurement in an earlier P-FINAL document turned out to be wrong, the wrong
figure is stated alongside the right one rather than quietly replaced — a security document that silently
corrects itself cannot be audited.

**Scope.** The whole account API surface, with attention to what this release changed: the five clean-room
packages (audit trail read and capture, named permission sets, campaign recipient outcomes, WhatsApp delivery
status), the P8–P11 subsystems, and the channel send paths.

**Not in scope, and not claimed.** No dependency vulnerability scan was run — `bundler-audit` and `pnpm audit`
need their advisory databases over a network this container does not have (`02-license-audit.md` §5). No
penetration test was performed against a running instance. No production data was read.

---

## 1. The endpoint surface

| | count | how |
|---|---|---|
| routed endpoints with a controller | **807** | `Rails.application.routes.routes`, excluding redirects and mounts with no controller |
| endpoints under an unauthenticated prefix | **67** | paths beginning `/webhooks`, `/twilio`, `/sms`, `/public`, `/api/v1/widget`, `/webhook` |

The 67 are the ones an attacker reaches without a session, and they are the surface that matters most. They
were the subject of P5c and P7-WS1 and are unchanged by this release except where the WhatsApp delivery-report
path was rewritten (package E), which is a read of a provider callback that was already authenticated by
signature before it reaches any Lynomia code.

### 1.1 The three endpoint families this release added or replaced

| endpoint | authentication | authorization | tenant scope |
|---|---|---|---|
| `GET /api/v1/accounts/:id/audit_logs` | account API session or access token | `check_admin_authorization?` | `Custom::AuditLog.for_account(Current.account)` is applied **first**, before any filter, so no combination of filter, sort or page can reach another account's entries (`query.rb:41-43`) |
| the five `custom_roles` endpoints | same | `check_admin_authorization?` **and** `feature_enabled?('custom_roles')` | every lookup goes through `Current.account.custom_roles`, so a foreign id is **404, not 403** — a 403 would confirm the id exists elsewhere |
| `campaigns/:id/analytics/{metrics,contacts}` | same | `authorize @campaign, :show?` — the campaign's own policy, deliberately not a wider one | the campaign is resolved inside `Current.account.campaigns`; recipients are then read by campaign id, which belongs to exactly one account |

**Holding every capability the product defines still does not open the roles endpoints.** That is the principal
security property of package C, and it is asserted from the agent's side as well as the administrator's
(`spec/requests/custom_roles_spec.rb`).

---

## 2. Authorization defects found, and what was done

### 2.1 Attaching a permission set did not clear the built-in role — FIXED

**Severity: HIGH.** The agent edit page offers the two built-in roles and the account's permission sets in one
selector and sends only `custom_role_id` when a set is chosen
(`settings/agents/EditAgent.vue:131-136`). Upstream applies a membership's attributes with `.compact`, which
drops the absent `role`, so an administrator "moved" to a narrow set kept `role = administrator`: every
administrator endpoint still open to them — **including the roles endpoint that defines the set meant to
narrow them** — while the page displayed them as holding it.

The acceptance plan asserted the opposite ("Attaching a set never *removes* ability"), and the implementation
followed it faithfully. The specification was wrong: the rest of the product already assumed the invariant,
because the one server reader of a set's capabilities counts only a membership that is **both** an agent and a
holder (`unread_counts/counter.rb:170-172`).

Attaching a set now writes `role: :agent` with it, and a request naming `administrator` and a set together is
refused with 422 rather than resolved silently in either direction. Scenario C-11 is corrected with the reason
recorded beside it. Covered by `spec/requests/p_final/integration_corrections_spec.rb`.

### 2.2 The capability vocabulary is closed, and the list is derived rather than submitted

A caller cannot set a membership's effective capability list: it follows from the attached set
(`Custom::AccountUser#permissions`), and an unknown capability identifier is refused by the model's validation
against a frozen `PERMISSIONS` array. So a typo cannot become a capability, and a client cannot invent one.

### 2.3 Three capabilities are offered but narrow only the unread counter

`conversation_manage`, `conversation_unassigned_manage` and `conversation_participating_manage` appear in the
client's capability list (`permissions.js:4-12`). The only server reader of them is the filtered unread counter
(`counter.rb:2-4,157-168`). **Nothing narrows what conversations a holder can read.**

This is **not** a regression and not a privilege escalation: a holder of these sees what an agent sees, which
is what they would see with no set at all. But an administrator reading the capability names would reasonably
expect them to scope conversation access, and they do not. Recorded as a product limitation in the release
gate rather than changed, because making them scope conversation reads would narrow access for anyone who
already holds one.

### 2.4 Revoking the `custom_roles` entitlement does not revoke granted capabilities

The flag gates administering sets, not the capability list a membership already holds: neither
`Custom::AccountUser#permissions` nor any of the three policies that read it checks a feature. A downgraded
account therefore stops defining and attaching sets while the sets already attached keep working.

This is a deliberate product rule and it is now written down (`09-rollback-and-rollout.md` §1.0): a downgrade
must not silently strip an agent's access mid-shift. It is stated because it is the question an operator will
be asked, and because enforcing it the other way is a product decision about live tenants, not a bug fix.

---

## 3. Tenant isolation

Measured by reading the account predicate on every read path this release touches, and asserted from both
sides — the asking account and a mirrored second account with the same shape of data — in
`spec/requests/campaign_analytics_spec.rb`, `spec/requests/custom_roles_spec.rb` and
`spec/requests/audit_logs_spec.rb`.

| path | predicate | note |
|---|---|---|
| audit trail | `associated_type = 'Account' AND associated_id = <session account>` | applied before every filter. An entry with no `associated` is installation-wide and correctly invisible to an account |
| permission sets | `Current.account.custom_roles` on all five actions and on the attach path | there is **no foreign key** on `account_users.custom_role_id`, so this scoping is the only thing preventing account A attaching account B's set; it is asserted from both sides |
| campaign recipients | campaign resolved in `Current.account.campaigns`, recipients by `campaign_id` | `account_id` was dropped from the recipients predicate as redundant **and** index-defeating; the campaign-to-account resolution upstream of it is what isolates |
| operations signals | `account_id` nullable **on purpose** | installation-wide signals belong to no account, and the Operations Center is Super-Admin-only |
| billing webhook receipts | `account_id` nullable, no foreign key | an attribution hint for the operator's event list, written after the fact from a value Stripe supplies. **Nothing reads it to decide access** (`03-migration-review.md` §4) |

---

## 4. Mass assignment

Every endpoint this release added or replaced takes `params.require(...).permit(...)`:

- `custom_role_params` permits `:name`, `:description`, `permissions: []` — and `account_id` is **not**
  permitted, so an account cannot be named in a request at all; it comes from the session.
- the agent attach path reads one key, `custom_role_id`, and resolves it inside the account before using it.
- the campaign analytics endpoints are read-only and take no body.

`BillingEntitlementOverride` is reachable only from Super Admin, and its `granted_by` is taken from the acting
Super Admin rather than from the request.

---

## 5. Secrets

### 5.1 What this release found and closed

| finding | severity | state |
|---|---|---|
| the WhatsApp campaign loop logged every recipient's **name and E.164 number** at INFO, once per contact, and four more lines logged the name | **HIGH** | **FIXED.** All five lines carry `contact_id`. The log is a single stream shared by every tenant with none of the tenancy, retention or capability controls the API applies to the same data; the safe form already existed one line away in the same method |
| the Twilio SMS campaign logged each failed recipient's number | MEDIUM | **FIXED** — `contact_id` |
| Instagram logged the agent's **whole outbound message body** on any provider rejection | MEDIUM | **FIXED** — `message_id`. A body is the one data class this release's own design treats as never-loggable, and ERROR lines are the ones most likely to be mirrored into an alerting integration |
| `verification_pin` — the Meta phone-registration PIN — was the one `Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS` entry no `filter_parameters` pattern matched | LOW | **FIXED.** One list was honoured by the response layer, the audit layer and the diagnosis layer, and missed by the log layer |
| two 128-hex `secret_key_base` values committed in `config/secrets.yml` | LOW | **FIXED** — both now read from the environment. The file is dead (`Rails.application.secrets` was removed in Rails 7.1; this is 7.2.3.1, and nothing in the tree references it), but a tracked file named `secrets.yml` holding two values called `secret_key_base` is what a scanner and a customer security review are built to flag |

### 5.2 What was left, with the reason

`app/services/whatsapp/providers/base_service.rb:46` logs the whole Meta error response body on a failed send,
where every other reader of that body reduces it to three named fields. Left alone: the body carries no
credential (the bearer token travels in a request header), the repository's own fixtures show no customer data
in it, and the raw body is what made the P5-LIVE diagnosis of a real production failure possible. Recorded here
so the decision is visible rather than absent.

### 5.3 The audit trail's own secret handling

`Custom::AuditLog` drops credentials before save (`before_save :drop_secret_changes`), and
`AuditTrail::Secrets` is the single rule it applies — which names `verification_pin` explicitly, and did so
before the parameter filter caught up. This is the second line of defence: the capture points exclude
credentials by construction, and the model refuses them anyway, including nested jsonb keys.

The originating address is coarse unless the account holds `audit_log_ip_address`, because a full address
identifies a machine and, for a small team, a person.

---

## 6. Logging and disclosure, generally

26 logger call sites in `app/` and `custom/` on the paths this release touches were read. After §5.1, every one
carries identifiers, counts, codes or error classes. The two classes of value that must never reach a log —
a message body and a contact's phone number or name — appear in none of them.

`audited_changes` is scrubbed on write, not on read, so a credential cannot be recovered from the store even by
a future reader that forgets to redact.

---

## 7. AI and third-party model calls

The product cannot reach a model provider today, and the reason is narrower than an earlier draft of
`02-license-audit.md` claimed. The LLM gems **are** called — `lib/llm/config.rb` requires `ruby_llm` and is
reached from `lib/captain/base_task_service.rb` and `lib/integrations/llm_base_service.rb` — so they are live
dependencies, not dormant ones. What stops a provider call is that every path runs through
`Llm::Config.with_api_key`, no installation-level key is configured, the Captain surface is behind a capability
that is off, and the Captain model layer it would operate on is absent with the overlay.

`captain_tasks` now defaults to **off for newly created accounts**, which took a migration and not a
configuration edit: the default is read from an installation config row, and `ConfigLoader` leaves an existing
row's value alone (`db/migrate/20261011160000`). Existing accounts are deliberately untouched.

**No customer data has ever left this installation to a model provider, because no provider call can be made
without a key that is not set.** That is a statement about configuration, which an operator can change; it is
not a statement about the code.

---

## 8. What this audit establishes, and what it does not

It establishes: the authorization rule on every endpoint this release added or replaced, and that one real
authorization defect was found and closed; that tenant isolation is enforced by an account predicate applied
before any filter on every such path, asserted from both sides; that no endpoint added here permits an
account-identifying parameter; that five secret or PII disclosures in logs were found and four of them fixed,
with the fifth's reason recorded; and that the product cannot reach an AI provider in its current
configuration.

It does not establish that the release is free of vulnerabilities. **No dependency scan was run and none is
claimed** (§ scope). No running instance was attacked. Three of the items above are product rules rather than
defects — §2.3, §2.4 and §5.2 — and each is a decision an owner should confirm rather than inherit.
