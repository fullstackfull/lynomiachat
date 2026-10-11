# Pre-deploy condition 3 — the six outstanding product rules

Six decisions were recorded by P-FINAL rather than taken. They are reproduced here with the evidence needed to
take them. **Nothing in this document has been implemented.** No product semantics changed in this branch.

---

## 0. Which six, and a correction to the gate's own count

`docs/p-final/07-release-gate.md:131` says:

> `| **RULE** | 6 | #32, #33, #47, #56 and the two product rules inside them — decisions for an owner to confirm |`

That sentence cannot be reconciled with its own table, and an owner reading only that line cannot work out
which six are meant. Two problems:

1. **"inside them" is false.** `grep -n "RULE" docs/p-final/*.md` marks exactly **four** rows: lines 57 (#32),
   58 (#33), 82 (#47) and 96 (#56). Neither of the two extra rules is inside any of them. Both are in
   `09-rollback-and-rollout.md` §1.0, a section none of the four rows references.
2. **A literal reading yields five, not six.** `09-rollback-and-rollout.md` §1.0 holds three
   "recorded rather than changed" items. One of the three (09:48–52, a permission set still granting after the
   entitlement is revoked) **is** #33 and is already counted. The union of {#32, #33, #47, #56} with the two
   remaining §1.0 items is six only if both of those remaining items count — the audit-capture bullet (09:44–47)
   and the `whatsapp_campaign` caveat (09:53–59). The sentence mentions neither by name.

**A third problem, found by counting the rows.** `grep -cE '^\| [0-9]+ \|' docs/p-final/07-release-gate.md`
returns **71**, and the summary partitions exactly 71 (PASS 58 + OPEN 7 + RULE 6). A marker census over the
status cells of the pre-existing table gives PASS-ish 59, OPEN-ish 6, RULE 4, "No —" 2. OPEN 7 reconciles
openly (6 OPEN markers plus #27, which `:130` names explicitly). That leaves 60 rows to split as PASS 58 +
RULE 6 against only **four** RULE markers — so **the summary is counting two PASS/No-marked rows as RULE, and
the document does not say which two.** Counting the `09` §1.0 bullets instead would give 73, not 71, because
they are prose and not rows.

**So the gate's RULE membership is not recoverable from the gate.** What follows is not a reconstruction of
the gate's intent; it is the six decisions that are genuinely recorded in the P-FINAL documents as product
choices rather than defects, which is what an owner actually needs. They are the four marked rows plus the two
"recorded rather than changed" items in `09` §1.0, and they include both rules the brief names. If the owner
wants the gate's own table made self-consistent, the fix there is to re-mark the two intended rows RULE or to
restate `:131` as 4 — a separate, smaller edit than this document.

Six distinct, already-recorded decisions do exist, and the intent is clearly six. **No new question was
invented.** The honest form of that gate row would be:

> `#32, #33, #47, #56, plus the two further product rules recorded in 09-rollback-and-rollout.md §1.0 (audit capture is not gated by the audit_logs flag; turning whatsapp_campaign off pauses a scheduled campaign rather than cancelling it).`

`06-clean-code-review.md` and `03-migration-review.md` were also swept for further RULE-shaped items. They
contain decisions, but the gate scored every one of them PASS, not RULE (03 §8.1 "let them die" = #63 PASS;
03 §8.2 "no action" = #64 PASS; 06 §2 "what was deliberately NOT removed" covered by PASS rows). One item is
RULE-shaped and was **not** promoted: `02-license-audit.md` §6's last bullet, `vendor/bundle/` kept out of git
only by `.git/info/exclude`. It is noted under RULE 4 rather than counted, because the instruction was to find
the six that exist, not to make a seventh.

---

## RULE 1 — The three `conversation_*` capabilities do not scope conversation access

`07-release-gate.md`:57 · `05-security-audit.md` §2.3 · **this is the rule the brief names as (A)**

### Current behaviour

Three identifiers, published in two places that agree — `custom/app/models/custom_role.rb:19-28` (`PERMISSIONS`)
and `app/javascript/dashboard/constants/permissions.js:4-12` — `conversation_manage`,
`conversation_unassigned_manage`, `conversation_participating_manage`. The vocabulary is closed:
`permissions_are_published` (`custom_role.rb:91-96`) validates against the frozen array.

**On the server they do exactly one thing.** Grepping all three strings across `app/`, `custom/` and `lib/`
returns, outside specs, only `app/services/conversations/unread_counts/counter.rb:2-4`, where they become
`MANAGE_ALL_PERMISSION`, `UNASSIGNED_PERMISSION` and `PARTICIPATING_PERMISSION`. They are read in one method,
`Counter#permission_mode` (`counter.rb:157-168`), which selects which Redis keys get summed — `:base` the
account-wide key, `:unassigned_and_mine` the unassigned key plus the member's own, `:mine` only their own, and
`:none` short-circuits the whole payload to zeros at `counter.rb:17`.

**And that reader is off by default.** `conversation_unread_counts` is `enabled: false` with
`chatwoot_internal: true` (`config/features.yml:28-31`), and the controller refuses the endpoint with 403
unless it is on (`unread_counts_controller.rb:27-31`). That endpoint is `Counter`'s only caller. **So with the
shipped defaults these three capabilities have no server-side effect at all.**

**Nothing narrows what a holder may read.** Three independent proofs:

- *The list.* `ConversationFinder#find_all_conversations` narrows through
  `Conversations::PermissionFilterService`, whose entire rule is `return conversations if user_role ==
  'administrator'` then `conversations.where(inbox: user.inboxes.where(account_id: account.id))`
  (`permission_filter_service.rb:11-23`). Inbox membership and the built-in role. No capability is read.
- *The record.* `ConversationPolicy#show?` is `administrator? || agent_bot? || agent_can_view_conversation?`,
  and that last is `inbox_access? || team_access?` (`conversation_policy.rb:10-18`). The policy *defines*
  `assigned_to_user?` and `participant?` (`:38-44`) and **calls neither** — which is itself evidence of the
  intended design.
- *No override exists.* Both carry extension points — `Conversations::PermissionFilterService.prepend_mod_with`
  (`:48`) and `ConversationPolicy.prepend_mod_with` (`conversation_policy.rb:47`) — and `custom/` claims
  neither. `enterprise/` is absent from this distribution (gate #1).

**The browser, meanwhile, implements precisely the semantics the names promise.** `applyRoleFilter`
(`app/javascript/dashboard/store/modules/conversations/helpers.js:74-107`) returns true for
`administrator`/`agent`; `conversation_manage` → true; `conversation_unassigned_manage` → `isUnassigned ||
isAssignedToUser`; `conversation_participating_manage` → `isAssignedToUser`; then a bare `return false`. It is
applied to the live list in two getters. The capability list reaches the browser from
`_user.json.jbuilder:34`. **No P-FINAL document records this.**

So the actual state is: **client-side-only narrowing, plus a server-side effect on a counter that is switched
off.** A holder of `conversation_participating_manage` sees only their own conversations in the sidebar, and
`GET /api/v1/accounts/:id/conversations` returns every conversation in their inboxes.

**One sharp edge worth stating separately.** A set granting none of the three — a commerce-only or
support-only set, both of which the product invites you to create — puts the holder in `applyRoleFilter`'s
final `return false` for every conversation *and* in `Counter`'s `:none` mode. Their inbox renders empty, every
unread badge is zero, and the conversation route is not in their permission list so `validateActiveAccountRoutes`
redirects them away. The server meanwhile still serves them everything. **All five** sets the repo's own
seeder creates carry at least one `conversation_*` capability — Customer Support Lead
(`conversation_manage`), Sales Representative, Escalation Handler (both unassigned + participating), Junior
Agent and Analytics Specialist (participating) — which suggests the trap was understood implicitly and never
written down.

### Who and what is affected

Any account holding the premium `custom_roles` entitlement that has defined a set carrying one of the three and
attached it to a member — the administrators who configure sets, and the agents who hold them. Also affected
indirectly: anyone to whom the restriction was represented, in a security questionnaire, a sales grid, or an
administrator's own belief formed by watching the UI. **Not** affected: accounts without the entitlement,
accounts with no sets, administrators (every administrator check reads the `role` column via `administrator?`,
never this list), and all cross-tenant boundaries.

Population is unknown from here — this analysis had no production database.

### Why a decision is required

The three answers are mutually exclusive and only an owner can pick. If these are meant to be authorization —
and `applyRoleFilter` is direct evidence somebody intended exactly that — the server is missing the check and
the product makes a promise it does not keep. If they are unread-count semantics, they are misnamed:
`conversation_participating_manage` says *manage*, not *count*. If they are vestigial, they should leave the
vocabulary. What tips this from housekeeping into a pre-sale decision is that **the UI already behaves as
though the rule exists**, so an administrator forms a belief about agent reach by watching the product, and
that belief is wrong in a way a URL defeats.

### Security impact

A privilege boundary the product **displays but does not enforce**. Concretely: an administrator attaches the
seeded "Junior Agent" set (`seed_data.yml:199-202`, `conversation_participating_manage` only) to a new hire and
watches the hire's inbox show only their own conversations. The hire can nonetheless call
`GET /api/v1/accounts/:id/conversations` with their own session or access token and receive every conversation
in every inbox they belong to, and open any conversation by `display_id`. Message bodies, contact details and
attachments follow.

**Bounded honestly:** this is **not** a privilege escalation and **not** a regression. The holder reaches
exactly what the same person would reach with no set attached — their inbox memberships. The ceiling is still
`user.inboxes` and still account-scoped. No tenant boundary is crossed. What is wrong is the
**misrepresentation**: the only defence is the browser. This release applied the opposite principle elsewhere
in terms — `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:10-12` says "client gating is not
authorization" — and did not apply it here.

Secondary and smaller: a set with none of the three zeroes every unread count, so a holder can stop being
notified of work they still have access to. Availability of information, not confidentiality.

### Commercial impact

`custom_roles` is premium (`config/features.yml:148-151`, `premium: true`). Three of the eight things it sells
do not do what their names say on the server. If the feature is sold with "restrict agents to their own
conversations", that claim is not true of the API, and a customer security review that tests the API rather
than the UI will find it — in the one feature whose entire value proposition is restriction. The commercial
pressure therefore points **towards** making them real, not towards the status quo.

### Backward-compatibility impact

Option A **narrows** access for existing holders. That is the whole compatibility cost, and it should be sized
against real rows before it ships. But the narrowing is bounded in the way that matters: **it narrows them to
what the client already shows them.** Nobody loses a conversation they can currently see in the product; they
lose conversations reachable only by bypassing the UI. Cached unread counts need no special handling —
`permission_mode` does not change. Invalidation plumbing does exist on both sides — `custom_role.rb:58` fires
`invalidate_holders_visibility` on a permissions change, and `account_user.rb:85-95` does the same for a role
or set change — but note what it invalidates: both call `Conversations::UnreadCounts::FilteredCountInvalidator`,
i.e. the **filtered** counter, which is a different class from the `Counter` these capabilities feed and is
itself behind `unread_count_for_filters`. So the hooks are there to reuse, not already pointed at the right
cache.

The one real trap in option A is the `:none` set. Today a commerce-only set means "empty inbox on screen, full
access by API". Under option A it would mean a genuinely empty conversation list, which for an agent who works
through deep links or search is a functional regression on their actual day. **Option A is only safe if it
ships with an explicit answer for the empty case** — either `:base` (a set that says nothing about
conversations does not restrict them) or a validation that every set must name one of the three.

### Options

**A — Make them real server-side authorization.** Mirror `applyRoleFilter` on the server: a `custom/` mod
prepending `Conversations::PermissionFilterService#perform` to intersect the inbox-membership scope with an
assignee scope derived from `account_user.permissions`, and a matching mod on `ConversationPolicy#show?` so the
record path agrees with the list path. Both extension points exist and are unclaimed, so this is additive in
`custom/` and edits no OSS file — which is what `CLAUDE.md`'s overlay guidance asks for.

**B — Keep count semantics and rename.** Accept that they are about how much of the inbox a member's unread
numbers cover, rename to `unread_count_all` / `unread_count_unassigned` / `unread_count_mine`, and remove the
client-side `applyRoleFilter` narrowing and route gating so the browser stops implying a restriction the server
does not apply. Cheap on behaviour, **expensive on data**: changing the identifiers means rewriting every
existing `custom_roles.permissions` array, because `permissions_are_published` would make those rows
unsaveable the moment anybody edits them — the exact failure already documented at `custom_role.rb:30-34` for
`knowledge_base_manage`.

**C — Remove them from the configurable vocabulary.** Drop the three from
`AVAILABLE_CUSTOM_ROLE_PERMISSIONS` and treat them as `knowledge_base_manage` already is: retained in the
server's `PERMISSIONS` and listed in `RETIRED_PERMISSIONS` so existing rows stay saveable. **This is the one
option with a trap that bites even if you do nothing:** a set whose only capabilities were the three shows as
empty in the editor, and the client's "at least one capability" rule and the server's
`validates :permissions, presence: true` both then refuse it — so an administrator cannot even rename that set
without first adding a capability.

**D — the companion to whichever is chosen:** decide what a set that names none of the three means. This is
not optional under A.

### Recommendation

**Option A, with D.** The product's intent is not ambiguous: somebody wrote `applyRoleFilter` with all three
branches, wired it into both conversation-list getters, and put the three in the conversation route's
permission list. That is a specification, expressed in code. The server simply never got the other half —
almost certainly because that half lived in the Enterprise overlay this release removed, and
`PermissionFilterService.prepend_mod_with` / `ConversationPolicy.prepend_mod_with` are the unclaimed sockets it
plugged into. **A fills a hole; B and C ratify it.**

The decisive argument is direction of error. Under A the error mode is "an agent cannot see something they
arguably should", which surfaces instantly as a support request from a named person and is fixed by widening
their set — and widening is always safe. Under the status quo, and under B and C, the error mode is "an agent
could see something the administrator believed was hidden", which surfaces as an incident or not at all.

**Code change required: YES.** All new files under `custom/`; no OSS file edited.

> **The brief's constraint stands: conversation access is not widened or narrowed in this branch.** Option A
> narrows it. Nothing is implemented until the owner says so.

---

## RULE 2 — A permission set keeps granting capabilities after the `custom_roles` entitlement is revoked

`07-release-gate.md`:58 · `05-security-audit.md` §2.4 · `09-rollback-and-rollout.md` §1.0 ·
**this is the rule the brief names as (B)**

### Current behaviour

`Custom::AccountUser#permissions` (`custom/app/models/custom/account_user.rb:20-24`) returns
`custom_role.permissions + [CUSTOM_ROLE_MARKER]` whenever a set is attached, and `super` otherwise. It reads
**no entitlement**. The `custom_roles` flag gates the administration surface — all five permission-set
endpoints raise `Pundit::NotAuthorizedError` while it is off — but it does not gate capabilities already held.
So when a plan lapses or is downgraded, an agent carrying a set keeps every capability in it.

### Who and what is affected

Any account that held `custom_roles`, defined sets, attached them, and then lost the entitlement — by a
downgrade, a lapsed subscription, or `Billing::FeatureSync` disabling the flag. The agents holding those sets
keep their capabilities; the administrators lose the ability to edit the sets that grant them.

### Why a decision is required

Because the two readings have opposite failure modes and both are defensible. Under "entitlement is a hard
upper bound", a lapse strips access from working agents with no warning. Under "roles grant independently of
plan", a customer keeps using a paid capability after they stop paying for it. Neither is obviously right and
the brief is explicit that it must not be chosen silently.

### Security impact

Low, and it is a commercial-enforcement question more than a security one. No capability in a set crosses a
tenant boundary, and every administrator check reads the `role` column rather than this list, so a lapsed
entitlement cannot turn an agent into an administrator. The security-shaped risk is the reverse of the usual
one: **option A would let a billing event silently remove an authorization**, and an authorization that
disappears for a reason nobody can see from the product is its own kind of incident.

### Commercial impact

This is where it bites. `custom_roles` is premium. Today a customer can hold the entitlement for one month,
have an administrator attach sets to every agent, let the subscription lapse, and keep the capabilities
indefinitely. The administration surface locks, so they cannot change them — but they do not need to.

### Backward-compatibility impact

Option A changes behaviour for every already-downgraded account the moment it ships, with no migration and no
notice: the capabilities simply stop. Option B changes nothing. Option C changes one controller.

### Options

**A — Entitlement as a hard upper bound.** `effective = role_permission AND account_entitlement`, implemented
at the single choke point `Custom::AccountUser#permissions`: return `super` unless the account is entitled,
resolved through `Billing::Entitlements.allowed?(account, 'custom_roles')` so an operator's audited override
still wins. One method, one place, every reader inherits it — which is exactly what `CLAUDE.md` asks for
("enforce eligibility and exclusivity rules at the earliest shared entry point"). **Its cost is abrupt:** the
instant `FeatureSync` disables the flag, a support lead mid-triage drops out of every case in the account.

**B — Roles grant independently of plan.** Today's behaviour, ratified and documented. Not "do nothing": three
things are wrong even under this reading and would have to be fixed to make it honest — the contradiction
between `09:36` and `09:50-51`/`05:87-88` about whether *attach* is gated, an explicit decision that leaving
attach ungated is intended, and naming which capabilities survive a lapse.

**C — Per-capability semantics.** `custom_roles` gates only the administration of sets, and each capability is
additionally subject to **its own feature's** entitlement at the surface it governs. **This is largely already
true**, and it is the option with the smallest delta — verified in the controllers, not inferred:

| capability | read by | its own feature gate |
|---|---|---|
| `commerce_order_manage` | `Commerce::ActionPolicy#manage_orders?` (`custom/app/policies/commerce/action_policy.rb:22`) | **yes** — `before_action :ensure_commerce_enabled` raising on `lynomia_commerce` at `custom/app/controllers/api/v1/accounts/conversations/commerce/order_actions_controller.rb:9,33` |
| `support_ticket_manage` | `Support::TicketPolicy` | **yes** — `custom/app/controllers/api/v1/accounts/support/base_controller.rb:17-21`, 404 rather than 403 |
| `contact_manage` | `Custom::ContactPolicy#merge?` | **no.** `custom/app/controllers/custom/api/v1/accounts/actions/contact_merges_controller.rb:7-9` is `authorize(::Contact, :merge?)` and nothing else |

So C reduces to a single question: **which feature, if any, should gate contact merge?**
`lynomia_unified_identity` already gates the identities endpoint the same policy serves
(`custom/app/controllers/api/v1/accounts/contacts/identities_controller.rb:40-44`), which makes it the
candidate with precedent — though merge predates identity, so this is a judgement rather than a derivation.

### Recommendation

**Option C**, and fix the two documentation errors regardless of which option is taken.

C is the only option already mostly implemented, and it is implemented where this product consistently puts
commercial gates — at the controller for the surface being sold. `support/base_controller.rb:14-16` even
states the house style: "A disabled feature is 404, not 403: the account has no support module, so the endpoint
does not exist for it." C ratifies a pattern the code already follows and closes the one hole in it, instead of
introducing a second competing enforcement layer inside `#permissions`. It also answers the commercial
objection where that objection actually lands: a customer who stops paying for commerce loses commerce, not
their agents' ability to work conversations.

**Code change required: YES, but small** — one feature gate in
`custom/app/controllers/custom/api/v1/accounts/actions/contact_merges_controller.rb`, following the pattern
already used by its sibling at `identities_controller.rb:41`. If the owner decides merge should stay ungated,
**option C requires no code change at all** and the deliverable is documentation only.

Required under every option: correct `05-security-audit.md:87-88` and `09-rollback-and-rollout.md:50-51` to
agree with `09:36` on whether attach is gated.

---

## RULE 3 — The whole Meta error response body is logged on a failed WhatsApp send

`07-release-gate.md`:82 · `05-security-audit.md` §5.2

### Current behaviour

`app/services/whatsapp/providers/base_service.rb:45`, inside `handle_error`, is
`Rails.logger.error response.body` — the provider's entire error response, unbounded and unparsed.

### Who and what is affected

Whoever reads the application log: the operator and anyone with host access. Not customers, and not other
tenants.

### Why a decision is required

It is a deliberate trade between diagnosability and the standing risk of logging an unbounded third-party
document. The decision was taken once and recorded in an audit document, which is not where the next person to
read that line will look.

### Security impact

The body carries **no credential** — the bearer token travels in a request header, which is a structural fact
about the Cloud API rather than an observation about one payload. The repository's own fixtures show no
customer data in it. The risk is a hypothetical future Meta payload shape carrying something today's does not,
logged unnoticed.

### Commercial impact

None directly. Indirectly: a customer security questionnaire asking "do you log third-party response bodies"
has a yes answer that needs the explanation this rule is about.

### Backward-compatibility impact

None under any option. Log format is not an interface anything consumes here.

### Options

**A — Keep it, and put the reason at the call site.** Leave the line, add a comment stating what the body may
contain, that it carries no credential and why, and that the decision was taken knowingly. Optionally cap the
length so a pathological body cannot flood the log.

**B — Reduce it to the named fields the product already extracts.** Build a structured line from Meta's
documented `error.code`, `error.type`, `error.message`, `error.error_subcode`, `error.fbtrace_id` — the fields
the per-provider `error_message` implementations already pull from the same response — plus the `message_id`,
matching the shape the Instagram fix adopted. `fbtrace_id` is the field Meta's own support asks for. **Cost:** a
failure Meta reports in a field nobody enumerated becomes invisible, which is exactly the situation the raw
body saved last time.

**C — Split by level.** Named fields plus `fbtrace_id` at ERROR, raw body at DEBUG. **Its weakness is real:**
the failure you need the raw body for is usually the one that already happened, and DEBUG was off when it did.

**D — Redact then log.** Rejected on sight: `CLAUDE.md` forbids compatibility coercions and speculative
scrubbing of malformed third-party values, and a regex scrubber over an unknown payload shape is the kind of
guard that fails silently.

### Recommendation

**Option A.** The evidence supports keeping it: no credential, no customer data in any known payload, and
**this specific line has already paid for itself once, in a real production diagnosis on the product's most
failure-prone path** (`05-security-audit.md:177-178`). Against that is a payload shape that does not exist
today. `CLAUDE.md` says to build for the expected production path and not to add handling for cases production
has not proven necessary; applied here, that points at A.

What needs fixing is not the behaviour but where the reasoning lives.

**Code change required: NO** (behaviourally). One comment at `base_service.rb:45`.

---

## RULE 4 — The repository makes two different licence declarations and carries upstream's package identity

`07-release-gate.md`:96 · `02-license-audit.md` §6

### Current behaviour

Two declarations that do not describe the same thing. The root `LICENSE` is upstream Chatwoot's, including a
carve-out clause for an `enterprise/` directory **that does not exist in this distribution**, and a
notice-retention clause at `LICENSE:17-18`. `package.json:2-4` says `"name": "@chatwoot/chatwoot"`,
`"version": "4.18.0"`, `"license": "MIT"`, with no `"private": true`.

### Who and what is affected

Anyone performing due diligence on this repository: a customer's legal review, an acquirer, an auditor. Also
anyone who could publish the package, since nothing structural prevents it.

### Why a decision is required

The fork's intended licence position is a business decision, not something a repository audit can derive.
`02-license-audit.md:1-6` says so in its own opening.

### Security impact

None.

### Commercial impact

Real but indirect. A repository asserting it is upstream's package at upstream's version is a finding in any
diligence exercise, and the `enterprise/` carve-out referring to an absent directory invites exactly the
question nobody wants asked on a call.

### Backward-compatibility impact

Changing `package.json`'s `"name"` touches `pnpm-lock.yaml` and any workspace reference, so it must be
confirmed by an install rather than assumed. Everything else is inert text.

### Options

**A — Declare the fork's position explicitly and make the two files agree.** Keep `LICENSE` intact so
upstream's notice is retained as required; add a root `NOTICE` naming the fork, its copyright and the upstream
MIT origin; rewrite the inert `enterprise/` clause with a note that the directory is absent from this
distribution; update `package.json`'s `name`, `license` and `private`. **Cost:** an hour of legal review, which
is the correct hour to spend.

**B — Leave both as upstream wrote them, as a recorded choice.** Defensible: it *is* a fork of MIT software,
MIT genuinely governs, the notice is retained, nothing is misrepresented — merely under-specified. **But this
option is only honest if it is written down.** Left unwritten it is not option B, it is the status quo, which
is what the gate refused to ratify.

**C — Split the decision.** `package.json`'s identity metadata carries no third-party obligation and can be
corrected immediately by an engineer with no legal input. `LICENSE`, `NOTICE` and the `enterprise/` clause
carry the notice-retention obligation and must wait for the review `02-license-audit.md` says is required.

**D — recorded so it is not lost, not part of this rule:** add `vendor/bundle/` to `.gitignore`.
`02-license-audit.md:280-285` calls it "the one-line fix" and it is still undone; today the directory is kept
out of git only by `.git/info/exclude`, which is not committed and therefore protects only this checkout.

### Recommendation

**Option C.** Fix `package.json` now; take `LICENSE`/`NOTICE` to qualified legal review as a scheduled item.

The split is justified by what each file carries. `package.json:2-4` contains no third-party obligation at all
— it is this repository's own identity metadata and it is simply inaccurate. Correcting an inaccurate
self-description needs no lawyer, and it closes the only concrete hazard in the pair: a package named
`@chatwoot/chatwoot` with no `"private": true` has nothing structural stopping it being published. `LICENSE` is
the opposite case: it carries a live obligation on a third party's copyright, and getting it wrong converts a
tidy-up into a liability.

**Code change required: YES for the `package.json` half; NO for the `LICENSE` half**, which is a legal review
rather than an engineering change. **This document claims no legal clearance on either.**

---

## RULE 5 — Audit capture runs whether or not the `audit_logs` flag is on

`09-rollback-and-rollout.md` §1.0, lines 44–47 · counted by the gate at #70

### Current behaviour

The flag gates **reading**, not writing. `AuditTrail::Query#scope` returns `Custom::AuditLog.none` unless the
account has `audit_logs` (`custom/app/services/audit_trail/query.rb:52`), while
`Custom::Audit::Capture#write_audit` (`custom/app/models/custom/audit/capture.rb:21-32`), the twelve
`Custom::Audit::*` modules and seven direct writers all write unconditionally. Turning the flag off hides the
trail; it does not stop it, and the table grows either way.

### Who and what is affected

Every account, entitled or not — all of them accumulate rows. The operator, who pays for the storage. And an
administrator who turns the flag off expecting recording to stop.

### Why a decision is required

Two things are in tension and only an owner can price them: a trail that cannot be switched off (a security
property) against storage that grows without bound on behalf of accounts that are not paying for the feature.

### Security impact

**The current behaviour is the secure one, and that is the decisive fact.** A trail that can be switched off by
whoever is being audited is not a trail. Note that `write_audit` already carries the one early return that *is*
legitimate — the cascade-suppression mark — which shows the author did think about what should and should not
stop a write.

### Commercial impact

Unentitled accounts generate storage cost for a premium feature they do not hold. There is no bound on it: a
search of `config/schedule.yml`, the `audit_trail` services and the `Custom::AuditLog` model found **no
retention mechanism at all** — not a long window, none.

### Backward-compatibility impact

Option A: none. Option C (retention): deletes historical rows past the window, which is irreversible and needs
a check against any regulatory minimum that applies to this installation's customers.

### Options

**A — Keep it: record always, gate reading.** No code change. The work is to say, *where an operator actually
looks*, that turning `audit_logs` off hides the trail rather than stopping it. 09 §1.0 says this for the
release; the flag's own surface and the account features UI do not.

**B — Gate capture on the flag too.** Described for completeness and **recommended against**: it gives an
operator a real off switch and bounds storage, but buys both by destroying the trail's integrity — a read would
silently mix "nothing happened" with "recording was off", and an administrator wanting to hide an action would
have a one-click way to do it. It also makes the premium feature strictly worse on upgrade, since a newly
entitled account's history would start empty with no explanation for the gap.

**C — Keep recording, bound the data.** Add a retention window. The security property survives, the operator
gets a real answer to "how long do you keep this", and storage stops being unbounded. Needs a product decision
on the window and a check against any regulatory minimum — which is precisely why it is a rule and not a task.

**D — Tier the retention commercially:** short window unentitled, long entitled. Turns the storage cost into
part of the feature's value. More moving parts than C.

### Recommendation

**A and C together. Do not touch the capture path.** The rationale at `09:45-46` is correct and the security
property is decisive. What is genuinely unresolved is not the gating but the **absence of any bound**, and that
is a separate, answerable question.

**Code change required: NO for A. YES for C** — a new `config/schedule.yml` entry (which today contains no
audit entry at all) plus a job deleting rows older than the window. The window itself is the decision.

---

## RULE 6 — Turning `whatsapp_campaign` off pauses a scheduled campaign silently instead of cancelling it

`09-rollback-and-rollout.md` §1.0, lines 53–59

### Current behaviour

`Campaign#trigger!` early-returns when the capability is absent (`campaign.rb:77-79`). The campaign keeps
`campaign_status: :active`, the UI keeps saying active, `TriggerScheduledItemsJob` keeps re-selecting it for
three days (`trigger_scheduled_items_job.rb:7`, `scheduled_at: 3.days.ago..Time.current`) and then stops
selecting it. Nothing records that it wanted to send and could not. It is a pause, not a cancellation, and then
a silent abandonment.

### Who and what is affected

The customer whose campaign silently does not go out, and the operator who pulled the lever and has no way to
see what it stopped.

### Why a decision is required

The lever is in the documented first-response path for a WhatsApp incident, so the behaviour is reached on
purpose, under pressure — and the quiet failure is worst exactly then.

### Security impact

None.

### Commercial impact

A customer's campaign does not send and nobody is told. That is a support incident and, at the wrong moment, a
trust incident.

### Backward-compatibility impact

`trigger!` is **shared with SMS campaigns**. Any refusal written inside it lands on the SMS path too, which is
what `09:58-59` declined to do. A new campaign status means auditing every reader of that enum: the campaigns
UI, the analytics denominators gate #16 and #17 touched, and `TriggerScheduledItemsJob`'s own
`campaign_status: :active` predicate.

### Options

**A — Leave it, and make it observable.** Keep `trigger!` exactly as it is and emit one `operations_signals`
row at the early return. The product already uses that mechanism for this class of event — `09:66` describes it
as existing because "a problem which happens while a flag is off is still a problem" — and it is deduplicated
to one row per distinct open problem by a partial unique index, so the three-day retry loop produces one row
with a rising `occurrences` count rather than one per tick. **Cost:** the campaign still reads `active` and is
still abandoned after three days; only the silence is fixed.

**B — Make the refusal explicit in the data.** The honest end state and the expensive one: a new
`campaign_status` value or column, an audit of every reader, a migration, a decision about whether the state is
terminal or recoverable, and a WhatsApp-specific branch so it does not land on SMS.

**C — Fix the abandonment rather than the silence.** Widen the selection window at
`trigger_scheduled_items_job.rb:7`. **Recommended against:** that window is upstream's and bounds every one-off
campaign, not just the flag case. Widening it means old campaigns start sending late for unrelated reasons. It
fixes the wrong thing by moving a shared bound.

**D — Take the lever out of the first-response path.** Leave the code alone and change the instruction: amend
`09-rollback-and-rollout.md:101-103` and `deployment/ROLLBACK.md` so that for an in-flight WhatsApp campaign the
documented first response is to cancel the campaign, not to pull the flag.

### Recommendation

**D now, with A.** Fix the instruction, emit one operations signal, leave `trigger!` untouched. 09's reason for
not changing the code is sound: `feature_enabled?` is deliberately shaped so every non-WhatsApp inbox passes,
`trigger!` is shared with SMS, and a loud refusal inside it changes upstream behaviour on a path this release
did not otherwise touch. `CLAUDE.md` is explicit about preferring the smallest production-ready change and
about not reshaping shared paths for a case that has not proven itself.

**Code change required: YES, small** — one `operations_signals` write at the early return in `campaign.rb`,
plus two documentation edits. D alone is documentation only.

---

## The six decisions, in one table

| # | rule | current behaviour | recommendation | code change? |
|---|---|---|---|---|
| **1** | The three `conversation_*` capabilities do not scope conversation access — the browser narrows, the server does not, and the only server reader is an unread counter that ships disabled | **A + D** — make them real server-side authorization via the two unclaimed `prepend_mod_with` sockets, and decide what a set naming none of the three means | **YES** — new files under `custom/` only |
| **2** | A permission set keeps granting capabilities after the `custom_roles` entitlement is revoked | **C** — per-capability semantics: each capability subject to its own feature's gate at its own controller, which is already true of two of the three | **YES, small** — one feature gate on contact merge, or **none** if merge stays ungated |
| **3** | The whole Meta error response body is logged on a failed WhatsApp send | **A** — keep it; put the reasoning at the call site instead of only in an audit document | **NO** — one comment |
| **4** | Two licence declarations, and upstream's package identity in `package.json` | **C** — correct `package.json` now; take `LICENSE`/`NOTICE` to legal review as a scheduled item | **YES** for `package.json`; the `LICENSE` half is legal review, not engineering |
| **5** | Audit capture runs whether or not `audit_logs` is on, with no retention bound anywhere | **A + C** — keep capture ungated (the secure choice), and add a retention window | **NO** for A; **YES** for C — a schedule entry and a job. The window is the decision |
| **6** | Turning `whatsapp_campaign` off pauses a scheduled campaign silently, then abandons it after three days | **D + A** — change the documented first response, and emit one operations signal at the early return | **YES, small** — one signal write plus two doc edits |

**Three of the six are recommended as no change or documentation only** (3, 5-first-half, 6-if-D-alone). **Two
are small and local** (2, 6). **One is substantial and is the one with a security boundary in it** (1).

**Nothing above is implemented. Awaiting six decisions.**
