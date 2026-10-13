# Platform Support Desk — integration record and combined gate

> **STATUS: INTEGRATION COMPLETE. GATE GREEN.** Branch `claude/platform-support`, cut from `lynomia-custom`
> `3cff6eb0`. Nothing is merged into `lynomia-custom`. Nothing is deployed. Merging waits on owner approval.

## 1. What was merged, in the contract's order

| # | Workstream | Branch tip | Scope |
|---|---|---|---|
| 1 | Core backend — domain, migrations, tenant API, policies, audit | `f252c6a3` | 66 files. Six migrations, six models, the tenant API, `PlatformSupport::TicketPolicy`, `AuditWriter`, `ReferenceAllocator` |
| 2 | Customer and staff surfaces | `0269680c` | 42 files. The tenant Vue pages and store, EN+AR locales, the Super Admin desk (queue, detail, six decisions), the Operations Account 360 seam |
| 3 | SLA engine, notifications, attachments, hardening | `62c18487` | 40 files. `Sla::{Clock,PolicyResolver,State,Sweeper}`, `Notifications::ReplyNotifier`, `TicketMailer` + 7 templates, the notification allow-list branch, Rack::Attack throttles, the security suite |
| — | **Integration** | `69b7b373` … `b206ec48` | The wiring in §2, the seams in §3, the review closure in §4 |

Against the baseline: **~170 files changed, ~16.5k insertions, 41 deletions**; 6 migrations; 40 spec files.

## 2. What integration wired, and why there

Three agents each built a half of the same conversation. Integration gave every write exactly one owner, so the
staff desk and the tenant API cannot drift apart — a reply typed in Super Admin and a reply posted to the API
are the same write.

| Service | Gained | Reason it lives there |
|---|---|---|
| `TicketCreation` | resolves the SLA policy, applies the clock, records `sla_policy_applied`, then mails the customer and the desk after the commit | Creation is the one moment a policy attaches. Measured from `created_at`, because the promise starts when the customer asked |
| `MessageCreation` | `Clock#record_first_response` in place of its own duplicate stamp; the met/breached event; `Clock#restart_resolution` on a customer reopen; after the commit, the one notification row and one email per side | A reply is the only trigger for all four, and this is the only writer of a reply |
| `TicketTransition` | `Clock#sync_pause` on every status change, `Clock#restart_resolution` and a cleared breach on a reopen, and the two customer emails that ask something | The pause rule reads the ticket's *current* status, so it belongs between the assignment and the save |
| `SuperAdmin::PlatformSupportActionsController` | validates input, then delegates to `MessageCreation`, `NoteCreation`, `TicketTransition`, `TicketAssignment`; `StaffAuthorizer` answers both "is this person staff" and "may they reassign" | Eight inline writers deleted. The surface decides what a refusal says and where the operator lands; nothing else |
| `config/schedule.yml` | `platform_support_sla_sweep_job`, every five minutes, `housekeeping` | The job existed with no schedule; the tenant desk's own sweep is its neighbour at the same cadence |
| `lib/tasks/platform_support.rake` | `grant_agent`, `revoke_agent`, `agents` | **The bootstrap paradox**: no page can create the first `PlatformSupport::Agent`, and none is seeded. A page that created agent rows would need an agent row to protect it, or be open to every Super Admin — the distinction this module exists to draw |

Three services also **lock the ticket row** (`@ticket.lock!`) as the first statement of their transaction:
`TicketTransition`, `TicketAssignment` and `MessageCreation`. The staff controller held `with_lock` around every
mutation, and consolidating onto the services would otherwise have dropped that silently.

## 3. Cross-agent seams closed at integration

1. **Route drawer vs. views.** Agent 1 drew one-controller routes; Agent 2 built two controllers calling eight
   helpers. Rewritten to the singular `resource … collection` form; all 8 helpers verified against a booted
   app, and Administrate still enumerates both controllers.
2. **A duplicated opening message.** The detail page synthesized an opening bubble from `description` while
   `TicketCreation` writes it as a real message row. The computed property is gone; the fixture now carries the
   opening message the API returns.
3. **Operations Account 360 key shape.** The view read a flat key; the snapshot ships it nested — and always
   ships it, so the view now reads it directly instead of falling back to a stub-era "not recorded".
4. **The mailer's `%{account}` interpolation**, missing from two operator subjects. All 9 EN subject keys now
   render with no `%{` left.
5. **A contract disagreement about zero.** Agent 1's `SlaPolicy` refuses a non-positive threshold; Agent 3's
   clock spec built a policy holding `0`. Resolved in favour of the model: the refusal is the guarantee.
6. **Both contract stubs deleted** (Agent 3's stub file, Agent 2's 233-line scaffold) in favour of one real
   `spec/factories/platform_support.rb`; 12 spec files rewired to it.
7. **Eight dangling foreign keys in fixtures.** Agents 2 and 3 built against stub schemas with no foreign keys,
   so four tickets carried `sla_policy_id: 7` and four notes carried `agent_id: 1`. The real schema has
   `add_foreign_key` on both, so PostgreSQL refuses every one of those inserts.
8. **A defect in integration's own wiring**, caught by reading Agent 1's spec rather than by running it:
   delegating the reopen's `resolution_breached_at = nil` to the clock stopped clearing it for a ticket with no
   policy — reachable, because `sla_policy_id` is `on_delete: :nullify`.

## 4. The adversarial review, and what it changed

Six reviewers read the merged diff by dimension (wiring, authorization, secrecy, SLA, specs, product surface);
every non-minor finding was then sent to a second agent whose instructions were to **refute** it. **23 findings
raised, 19 survived refutation, 18 are fixed and 1 is recorded below as a limitation.** The ones that changed
behaviour:

| Severity | Finding | What it would have done | Fix |
|---|---|---|---|
| **blocker** | The tenant detail page read the ticket off the response root | `GET /tickets/:id` answers under `payload`, like every other serializer here and like the tenant helpdesk before it, so every field on the page was `undefined` | The page unwraps `payload`; the spec's mock had encoded the wrong contract, which is why 49 green examples never caught it |
| **blocker** | The create page pushed `response.data.id` | 201 answers in the same envelope, so a customer who had just described a problem was pushed to `ticketId: undefined` — a route that resolves to nothing | Unwrapped, plus a new spec that mounts the page, submits, and asserts the route it pushes |
| **major** | A staff reopen never restarted the resolution clock | `TicketTransition` had the pause half of the clock and not the reopen half, so a `resolved → open` move left the old target in the past: the five-minute sweep then stamped a permanent breach, wrote an event and emailed the desk about work that had restarted minutes earlier | Both halves, in the order `custom/app/services/support/tickets/update.rb:46-59` has always used. Proven by a spec that reopens and then runs a real sweep |
| major | Operator emails dropped their triage context | `shared.operator_context` was the bare label "Account context" with none of the four placeholders the template passes it | The key carries account, plan, category and priority, verified by rendering it |
| minor | The sweep breached tickets the desk calls ungoverned | It filtered on the due columns while `Sla::State#governed?` also requires the policy; deleting a policy row makes them disagree | One `sla_policy_id IS NOT NULL` in the shared scope, so the two cannot disagree |
| minor | A swept first-response breach was re-dated by the eventual reply, and integration's outcome event was written a second time | The sweep had already recorded and emailed that outcome | The clock decides once; `MessageCreation` writes the event only when it was the one that decided |
| minor | A first response was judged against a due time not credited with the pause it stood in | An operator replying to a ticket that waited a week on the customer was judged against a target that stopped a week ago | `Clock#effective_due` credits an open pause at comparison time |
| minor | "resolved in time" was decided by whether the sweep got there first | The sweep only looks at open tickets, so a ticket resolved an hour late keeps a NULL breach column for good | `Sla::State#resolved_late?` makes the comparison the sweep would have made; the desk reports the overrun |
| minor | `MessageCreation` read `closed?` before taking the row lock | The 422 could be raced by a close landing in the same instant | Both status reads happen after the lock |
| minor | Two `<label for=…>` pointed at a wrapper `div` | `Select` renders a div and the id lands there, so clicking the label did nothing | The label wraps the control, which associates it for real |
| minor | The staff queue header described the opposite of its own `ORDER BY` | — | The sentence now matches the query |
| majors ×4 | Spec fixtures that cannot exist: six messages with no author id, a memoized reference sequence giving two tickets one number, an agent row for a tenant user, a ticket created with no account | The suite could not have passed against the real schema | Real rows, real deletion path, real membership |
| minors ×2 | A dead billing setup line naming a config nothing reads; an example titled 404 that asserted 401 | Vacuous setup and a misleading title | Removed and renamed, with the real mechanism named |

Four findings were **refuted** by the verifier and left alone.

## 5. Gate results, as run

Ruby suites run in a worktree as the `postgres` OS user against the container's PostgreSQL (its packaged
`pg_hba.conf` authenticates `local` by `peer`, and the session's OS user has no database role). The staff ERB
pages render a Vite tag, so the run needs a built manifest and `VITE_RUBY_AUTO_BUILD=false`; without them every
Super Admin page 500s on `ViteRuby::MissingExecutableError` and 24 examples fail for a reason that has nothing
to do with the product.

| Gate | Result |
|---|---|
| **Platform Support Ruby suites + the three existing specs the branch touches** | **508 examples, 0 failures, exit 0** |
| **Combined run with the Operations, notification, Super Admin and installation-config suites** | **866 examples, 0 failures, exit 0** (3 pending: pre-existing MFA skips in the Super Admin devise spec) |
| **Whole frontend suite** (`pnpm vitest run`) | **499 files, 5393 examples, 0 failures, exit 0** (measured at `2ee56349`; the re-run on the final tree was still in flight when this was written, and the module's own 51 examples pass on it) |
| Platform Support frontend specs within it | **51 examples, 0 failures** (49 + the 2 new create-page proofs) |
| `bundle exec rubocop` (whole repository, 3022 files) | **0 offenses**. No cop disabled, no exclusion added |
| `npx eslint` on every changed JS/Vue file | **0 errors**, 2 pre-existing dynamic-i18n-key warnings |
| **Migration round trip** on a scratch database | committed schema loads 6 tables → **rollback of 6 leaves none** → migrate up → **dump byte-identical to `db/schema.rb`**, exit 0 |
| **The agent bootstrap**, end to end | `grant_agent` creates one lead, `agents` lists it, a tenant email is refused loudly, `revoke_agent` deactivates and keeps the row |
| App boot + `Rails.application.eager_load!` | OK — every constant in the wiring resolves |
| The 8 staff route helpers | all present; 14 distinct Platform Support route paths |
| 9 mailer subject keys + `shared.operator_context`, EN, with the real interpolations | all render; none leaves a `%{}` unresolved |
| `config/schedule.yml` | 15 entries; every class constantizes and every cron parses; the new entry fires every 5 minutes |
| EN/AR locale parity, `platformSupport.json` | 93 = 93 keys |
| Static contract proofs | No blob URL, signed id or `url_for` in any tenant serializer; the tenant ticket serializer emits exactly its 18 contract keys and none of the forbidden ones; no `audited` macro on any `platform_support_*` model; no `associated:` on any Platform Support audit write; no feature gate on any endpoint or route; no hard-coded support address; **no SLA target value anywhere** (the only number is a 365-day sanity ceiling on the policy column); five Rack::Attack throttles; `platform_support_reply` and `PlatformSupport::Ticket` present in `NOTIFICATION_TYPES`, `PRIMARY_ACTORS` and the visibility allow-list; every attribute the specs pass to a Platform Support model exists in `db/schema.rb` |

## 6. V1 limitations the owner should decide on

1. **A billing-locked customer cannot attach a file.** The desk is exempt from the billing guard, but the
   shared `/api/v1/accounts/:id/upload` endpoint is not, and doc 03 §7 deliberately routes attachments through
   it rather than adding a second upload path. The customer can still open the ticket and describe the problem;
   the picker shows a readable upload failure. Exempting the shared endpoint would turn a locked account into
   free file hosting with non-expiring blob URLs, so the fix is a product decision, not a patch.
2. **The `assignee_id` partial index cannot serve the `unassigned` filter.** Its predicate excludes the NULLs
   that filter looks for. The queue is correct and paginated; this is an index that does not help. Left alone
   because inventing an index strategy mid-gate would also mean re-proving the schema round trip.
3. **The 25 MB per-ticket aggregate** in doc 03 is not implemented; per-file (10 MB), per-message (5 files) and
   the content-type allow-list are.
4. **No 404-probe throttle** on the attachment route beyond the five existing throttles.
5. **`swagger/swagger.json` is untouched**, so the tenant endpoints are undocumented there (doc 07 §9).
6. **The unread marker is per account, not per user**: `customer_last_viewed_at` is one column on the ticket.
7. **Arabic mailer subjects fall back to English.** Backend strings live in `en.yml` and Crowdin owns the rest
   (CLAUDE.md); `config.i18n.fallbacks` makes that a silent, correct fallback rather than a blank subject.
8. **The staff queue orders by most recent movement** within each priority band, as the frozen contract says.
   If operators would rather see the longest-waiting first, that is one clause in `queue_scope`.
9. **Still required as data, not code**: the SLA target values, the support email alias, and the first agent
   rows. Until they exist the desk promises nothing, sends no operator mail, and refuses every staff action —
   each the intended fail-closed state, and the rake task in §2 is how the third is answered.

## 7. Before this may merge into `lynomia-custom`

1. Owner approval. The gate is green; the merge is not automatic.
2. After merging, the deploy runs `db:migrate` — six additive migrations, no backfill, no data change, and
   reversible as §5 proves.
3. The desk is inert until an operator runs `rake platform_support:grant_agent` and (optionally) sets the
   support alias and SLA policy rows. Nothing about Account 21 changed.
