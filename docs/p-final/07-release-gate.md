# P-FINAL release gate — 71 questions

One row per question. **PASS** means measured on this branch and the evidence is named. **OPEN** means it
cannot be closed from here and what would close it is stated. **RULE** means it is a product decision an owner
should confirm rather than inherit. Nothing is marked PASS on the strength of an intention.

Statuses were not assigned by reading earlier P-FINAL documents. Several of those documents were wrong, and
where this gate disagrees with one it says so.

---

## A. Provenance of the replaced implementation (1–10)

| # | Question | Status | Evidence |
|---|---|---|---|
| 1 | Is the Enterprise-derived implementation out of the tree? | **PASS** | 39 production files removed at `487276f2`; `git ls-files \| grep -c '^enterprise/\|^spec/enterprise/'` = 0 |
| 2 | Was the replacement written without access to it? | **PASS** | separate parentless repository `fullstackfull/lynomia-cleanroom`, root `82c3529d`, head `ac09224a`, six commits, no Lynomia history (`04-code-provenance.md` §8.1) |
| 3 | Was it imported byte-for-byte? | **PASS** | each file read with `git show ac09224a:<path>` and re-verified after writing; 53 files at `4c15603d`, 12 spec files at `a7c14aa9` |
| 4 | Did any clean-room history enter this repository? | **PASS** | no remote was added. `git log --all` contains no clean-room commit; `ac09224a` is not an ancestor of this branch |
| 5 | Does residual textual overlap with the historical files survive? | **PASS, with judgement stated** | re-sweep at two thresholds; residue is language syntax, schema-dictated declarations, framework-mandated action names, contract-fixed capability strings, and idioms attested many times in clean code (`04-code-provenance.md` §8.6) |
| 6 | Was any replacement file edited to reduce the similarity figures? | **PASS** | none. The brief forbade it and the measurement is unedited (`§8.6`) |
| 7 | Does every file in the affected register have a final state? | **PASS** | all 39 are REPLACED or REMOVED (`§8.3`) |
| 8 | Was any file removed that should not have been? | **PASS — one error found and corrected** | three upstream OSS specs were removed as Enterprise-derived; their history shows upstream Chatwoot authorship, an upstream OSS file cannot be Enterprise-derived, and all three are restored and pass unchanged (`00-affected-files.md`) |
| 9 | Did the exchange lose any original-Lynomia behaviour? | **PASS — two found, both restored** | two Flow Builder behaviours rode in Enterprise-derived files: the interactive-reply attributes and the list-button label, both restored with zero-hit grep evidence that they were never Enterprise-derived |
| 10 | Is a legal conclusion claimed? | **PASS** | no. `04-code-provenance.md` §8.7 states explicitly that this is technical process evidence and that legal clearance is a question for qualified review |

## B. Correctness of the integrated replacement (11–22)

| # | Question | Status | Evidence |
|---|---|---|---|
| 11 | Does the stored state encoding match the rows in production? | **PASS — the one true blocker, found and closed** | `campaign_recipients.status` was rewritten to the funnel order `sent:1…skipped:5` from a specification table that was wrong. Production is `queued:0, skipped:1, sent:2, delivered:3, read:4, failed:5`, identical at the production baseline and at the last pre-removal commit. Restored, and pinned by an assertion, not a comment |
| 12 | Was that the only stored encoding at risk? | **PASS** | sweep of every numeric mapping in all 44 imported Ruby files: `campaign_recipients.status` is the only enum among them |
| 13 | Did the clean-room's own suite catch it? | **No — recorded** | the suite asserted the same wrong mapping, so it agreed with itself. The one edit made to an imported spec, with the reason in the file |
| 14 | Does every shipped UI control reach a server that honours it? | **PASS — one gap found and closed** | the audit trail's search box sent `q`, which nothing read, so an unfiltered trail was presented as filtered. The specification's parameter table and the integration contract both omitted it; both corrected |
| 15 | Can a malformed query parameter produce a 500? | **PASS** | an array-shaped `page`/`user_id` reached `to_i`; and an out-of-range unix bound reached PostgreSQL, whose `timestamp` maximum is 294276 AD. Both closed; specification A requires that an unparseable value never 500 |
| 16 | Is the analytics denominator correct while a campaign runs? | **PASS** | recipients were written only as each contact's turn came, so `audience` grew with the loop and `status_counts.queued` could never be positive. The audience is now seeded before the first provider call, batched, idempotent on re-run |
| 17 | Do the six headline counters agree with `status_counts`? | **PASS** | measured: all six agree with an independently computed value and `status_counts` sums to `audience` |
| 18 | Does a provider report ever lose ground already made? | **PASS** | `record_outcome!` under `with_lock` walks a forward-only ladder; a failure over a delivered or read row is dropped |
| 19 | Is a member's cached visibility invalidated when it changes? | **PASS** | editing a set's capability list now invalidates every holder; the delete path already did, one row at a time so the callback fires |
| 20 | Can a rejected audit row fail the product action that caused it? | **PASS** | `Custom::Audit::Capture` wraps each write in a savepoint; the one capture point that had not prepended it now does, proven by the examples failing without the fix |
| 21 | Can an account be destroyed with its permission sets left orphaned? | **PASS** | the async dependent destroy runs only after the account row is gone, where the detach could not save. Fixed and covered |
| 22 | Can two concurrent recordings of one operations signal lose a raised severity? | **PASS** | the increment is now under a row lock; it computed both the count and the risen severity from an unlocked read |

## C. Authorization and tenant isolation (23–34)

| # | Question | Status | Evidence |
|---|---|---|---|
| 23 | Can a capability holder grant themselves a capability? | **PASS** | all five role endpoints are administrator-only, asserted from the agent's side including for a set they hold |
| 24 | Does attaching a set narrow the member? | **PASS — defect found and closed** | it did not: an administrator kept `role = administrator`. `05-security-audit.md` §2.1 |
| 25 | Is a contradictory role request refused? | **PASS** | `administrator` + a non-null set is 422 and changes nothing |
| 26 | Can account A reach account B's set? | **PASS** | 404 not 403, from both sides; `Current.account.custom_roles` on every path, including attach |
| 27 | Is there a foreign key enforcing that? | **No — and the scoping is therefore load-bearing** | there is no FK on `account_users.custom_role_id`; stated rather than assumed, and asserted in tests from both sides |
| 28 | Is the audit trail scoped before filtering? | **PASS** | `for_account` first, then filters (`query.rb:41-43`) |
| 29 | Is an installation-wide audit entry visible to an account? | **PASS** | no — it has no `associated`, so it is correctly invisible |
| 30 | Does the capability list derive from the set rather than the request? | **PASS** | `Custom::AccountUser#permissions`; no endpoint permits it |
| 31 | Is the capability vocabulary closed? | **PASS** | validated against a frozen array; a typo cannot become a capability |
| 32 | Do the three `conversation_*` capabilities scope conversation access? | **DECIDED — and now yes** | approved 2026-10-11 and implemented. `Conversations::CapabilityScope` is the one definition; the list, the record policy, global search and the unread counts all read it. Existing sets that name none of the three are grandfathered by `custom_roles.conversation_scope_enforced` until an operator edits their conversation capabilities. `docs/pre-deploy/04-decisions-implemented.md` |
| 33 | Does revoking the `custom_roles` entitlement revoke granted capabilities? | **DECIDED — and now yes** | approved 2026-10-11 and implemented. The bound is applied once, in `Custom::AccountUser#permissions`. No set is deleted and no membership detached; the holder falls back to its built-in `agent` list, which cannot reach administrator, and the set grants again the moment the entitlement returns |
| 34 | Can a nullable `account_id` be an authorization input? | **PASS** | the two nullable columns are on Super-Admin-only surfaces and neither is read to decide access |

## D. Mass assignment and request validation (35–40)

| # | Question | Status | Evidence |
|---|---|---|---|
| 35 | Does every new endpoint use strong parameters? | **PASS** | `params.require(...).permit(...)` on each |
| 36 | Can an account be named in a request? | **PASS** | `account_id` is permitted nowhere; it comes from the session |
| 37 | Is an invalid enum value refused at the boundary? | **PASS** | an unknown recipient status is 422 with the allowed list, not a database query |
| 38 | Is an out-of-vocabulary capability refused? | **PASS** | one error naming every unknown value |
| 39 | Does a lenient-parse surface stay lenient for every shape? | **PASS** | corrected for array-shaped and out-of-range values (#15) |
| 40 | Is `granted_by` taken from the request? | **PASS** | no — from the acting Super Admin |

## E. Secrets and disclosure (41–48)

| # | Question | Status | Evidence |
|---|---|---|---|
| 41 | Is any credential committed? | **PASS** | the two dev/test `secret_key_base` values in `config/secrets.yml` now read from the environment; nothing in the tree reads the file at all |
| 42 | Does any send path log a contact's name or number? | **PASS** | three paths did — WhatsApp campaigns at INFO once per contact, Twilio per failure, Instagram the whole message body. All carry identifiers now |
| 43 | Is every declared-secret key covered by the parameter filter? | **PASS** | `verification_pin` was the one gap in `SECRET_PROVIDER_CONFIG_KEYS` and is now named |
| 44 | Can a credential reach the audit store? | **PASS** | excluded by construction at the capture points and dropped again on save, including nested jsonb keys |
| 45 | Is a message body ever written to a log or the trail? | **PASS** | not after #42. The trail never stores one by design |
| 46 | Is a full originating address disclosed by default? | **PASS** | no — coarse unless the account holds `audit_log_ip_address` |
| 47 | Is any unbounded third-party document logged? | **DECIDED — and now no** | the owner overrode the recommendation: the raw body is gone and `Whatsapp::ProviderErrorLog` emits a sanitized structured allowlist (code, subcode, type, fbtrace id, capped sanitized message, status, classification). Unknown fields are not logged at all |
| 48 | Has a dependency vulnerability scan been run? | **CLOSED** | **yes, both, with network access.** `bundler-audit 0.9.1` against `ruby-advisory-db` commit `a6847b06`: 4 records — 1 FIXED (CVE-2026-66066, Rails 7.2.3.2), 1 NOT APPLICABLE (`rack-proxy`), 3 OPEN (`ruby_llm` ReDoS, CVSS 7.5, measured linear on Ruby 3.4.4). `pnpm audit`: 126 → 68 records, every remaining one in build or dev tooling. `docs/pre-deploy/00-security-audits.md` |

## F. Dependencies and licensing (49–56)

| # | Question | Status | Evidence |
|---|---|---|---|
| 49 | Does any dependency declare a source-available or commercial licence? | **PASS** | zero BSL, SSPL, Elastic or Commons Clause in either set |
| 50 | Are the copyleft items identified? | **PASS** | one LGPL-3.0 server-side library and one bundled into the browser asset, both named for legal review |
| 51 | Are all direct dependency licences known? | **CLOSED** | **yes, all twelve.** The ten development-group gems were measured from the published `.gem` for each locked version, cross-checked against the rubygems API, with artifact SHA-256s verified: 8 MIT, 1 BSD-2-Clause (`annotaterb`), 1 Apache-2.0 (`tidewave`, which ships no `NOTICE`, so §4(d) adds nothing). The two production gems do declare nothing in their gemspec — confirmed, not contradicted — but each ships a verbatim licence file: `ai-agents` MIT, `gmail_xoauth` Unlicense. Zero LEGAL REVIEW REQUIRED. `docs/pre-deploy/01-license-closure.md` |
| 52 | Are transitive dependency licences tallied? | **OPEN** | no — only the 152 direct gems and 114 direct JS packages. The 381 resolved gems and 1,144 locked packages are not, and the document now says so |
| 53 | Do vendored assets carry their licences? | **CLOSED for the fonts** | the 38 binaries are Inter **4.000, `git-a52131595`**, read from their own `name` table. `app/javascript/shared/assets/fonts/OFL.txt` is the upstream `LICENSE.txt` from that exact commit, byte for byte, SHA-256 `262481e8…5935a`; the `v4.0` tag returns the identical file. `NOTICE.md` now names the copyright holder correctly (The Inter Project Authors, not the designer) and records that 18 of the 38 are referenced by a `@font-face` rule. `vendor/db/sentiment-analysis.onnx` is unchanged and still named for review. No legal clearance is claimed. `docs/pre-deploy/01-license-closure.md` |
| 54 | Are advisory suppressions still justified? | **PASS — and now verified, with one more removed** | the ten removals were right: **nine of the ten did not reappear** against the live database. The tenth, CVE-2026-66066, returned and was **fixed** rather than re-suppressed (Rails 7.2.3.2). A fourth entry was then also removed — CVE-2026-67991 (`ruby_llm`) — because two sibling advisories with identical `patched_versions` were never suppressed, so the same risk was half-visible; all three are now visible and documented. **Three** remain (one Azure/nokogiri, two Devise), each re-checked rather than inherited |
| 55 | Is JavaScript dependency scanning configured? | **OPEN** | no. The Dependabot config is the discontinued v1 schema at the old path with upstream maintainers as reviewers; no workflow runs `pnpm audit` |
| 56 | Is the repository's own licence position coherent? | **DECIDED — identity fixed, licence still for legal review** | `package.json` now declares `"name": "lynomia-chat"` and `"private": true`, so the repository no longer presents itself as upstream's npm package. The `LICENSE`/`NOTICE` position was deliberately NOT decided here: it remains a matter for qualified legal review (`docs/pre-deploy/01-license-closure.md`) |

## G. Migrations and data integrity (57–64)

| # | Question | Status | Evidence |
|---|---|---|---|
| 57 | Is every migration in this release additive? | **PASS** | new tables, new columns with defaults, new indexes, and two that edit an installation config row. No column is dropped or retyped |
| 58 | Does any migration require a data backfill? | **PASS** | none. The state-mapping correction changed code, not rows (#11) |
| 59 | Does any new foreign key use the restricting default? | **PASS — one found and fixed** | both on `billing_entitlement_overrides` did, and nothing nullified `granted_by_id`, so deleting a Super Admin who had granted an override was refused by the database. An additive, reversible migration brings them into line |
| 60 | Is every new index built without an exclusive lock? | **PASS** | the four read-path indexes are `CONCURRENTLY` with `disable_ddl_transaction!`; `audits` takes a row for every audited action and `campaign_recipients` is written during a send |
| 61 | Is every migration reversible? | **PASS** | the three added here were applied and rolled back, and the feature-default one was checked in both directions |
| 62 | Does old code break on the new schema? | **PASS** | nothing old reads any of it, which is what makes a half-applied migration recoverable without the dump |
| 63 | Is in-flight queue state handled across the restart? | **PASS** | this release deletes a job the previous revision enqueued with a delay and retries. Stage 6b quiets the workers and drains before the restart; the dead-set expectation is written into the runbook |
| 64 | Is cached state across the deploy accounted for? | **PASS** | Redis filtered counts are stale for at most one TTL, hold counts rather than access, and no capability check reads them. Decision recorded rather than cleared |

## H. Deployment and rollback (65–71)

| # | Question | Status | Evidence |
|---|---|---|---|
| 65 | Can a failed deploy be re-run? | **PASS — it could not** | the script short-circuited on the SHA and reported "nothing to deploy" with exit 0. A completion marker written only after verification now distinguishes checked-out from deployed |
| 66 | Does the script tell the truth about what is serving? | **PASS — it did not** | one ERR message claimed "nothing was restarted" for failures after the restart, where the new code is serving and unhealthy. Two messages now |
| 67 | Is the pre-deploy backup verified? | **PASS — it was not** | checked for size only, and described as verified. `pg_restore -l` now reads the archive's own table of contents, which is the cheapest thing that fails on an unrestorable dump |
| 68 | Does the pre-flight measure the right filesystems? | **PASS** | it measured the application filesystem while the dump is written to another; both now |
| 69 | Does the rollback leave a tree the next deploy can use? | **PASS** | its `bundle install` was not frozen and could rewrite `Gemfile.lock`; and the stated reason not to re-run the script was wrong — after a detached rollback it cannot run at all. Both corrected, with the deliberate roll-forward spelled out |
| 70 | Does the rollout matrix cover what this release changed? | **PASS — it covered none of it** | nine levers, not one of them from the five replaced packages. All five added, with the two things their flags do **not** gate stated plainly |
| 71 | Has the release been exercised against production? | **OPEN — by instruction** | no. Nothing was deployed, no production host was reached, no flag was activated, no WhatsApp message was sent, and production Stripe was not configured. Real UAT remains pending for a controlled deployment, and `08-production-uat-runbook.md` is what it runs |

---

## Summary

| status | count | |
|---|---|---|
| **PASS** | 58 | measured on this branch, evidence named |
| **OPEN** | 7 | #48, #51, #52, #53, #55, #71, and #27 stated as a load-bearing absence rather than a defect |
| **DECIDED AND IMPLEMENTED** | 6 | formerly RULE. #32, #33, #47, #56, plus the two further product rules recorded in `09-rollback-and-rollout.md` §1.0 (audit capture is not gated by `audit_logs`; turning `whatsapp_campaign` off pauses a scheduled campaign rather than cancelling it). All six were approved on 2026-10-11 and implemented on this branch — `docs/pre-deploy/04-decisions-implemented.md` records the final semantics; `02-product-decisions.md` records the evidence each was taken from. Two caveats on this row. The earlier wording, "and the two product rules inside them", was wrong: neither is inside any of the four, and a literal reading of it yields five. And two of the six are prose in `09` §1.0 rather than rows in this table, which is why these three counts sum to 71 only if those two prose items displace two rows; `02-product-decisions.md` §0 accounts for that discrepancy rather than papering over it |

**Seventeen of the 58 passes are passes because a defect was found and closed in this pass**, not because the
code was already right: #8, #9, #11, #14, #15, #16, #19, #20, #21, #22, #24, #25, #42, #43, #54, #59, #65–#70.
That ratio is the useful number in this table. A gate where everything passed first time would mean the audits
were not looking.

None of the seven OPEN items is a code defect. Five are measurements that need a network (#48, #51, #52, #53,
#55), one is the deliberate production boundary (#71), and one is a structural fact stated rather than hidden
(#27).
