# 10 — Real WhatsApp UAT results, and the production operator runbook

**Status: BLOCKED — REAL SERVER DIAGNOSIS REQUIRED.**

Every item in this phase that needs the real WABA is blocked here, for four structural reasons that no amount of
further local work removes:

| Why | Detail |
|---|---|
| no real credential | the repository has no production access token, and P5 says not to ask for one. Token-bearing reads return Meta's own `OAuthException 190` from this container |
| fixture identity | the local `business_account_id` and `phone_number_id` are factory values. Meta has no such number |
| no handset | no real phone can send the inbound message or receive the outbound one |
| not the callback destination | Meta delivers to the URL registered for the number. This container is not that URL, so no real webhook can arrive here regardless of configuration |

What is **not** blocked: the network path to Meta works from here. A token-bearing GET reaches the Graph API and
comes back with a genuine Meta error body rather than a timeout or a TLS failure. So the command below will return
real answers when the operator runs it — the only missing ingredient is the credential, and it never has to move.

---

## 1. The exact command

Run on the server whose database owns the real WhatsApp inbox, as the application user, in the application
directory:

```bash
bundle exec rails whatsapp:diagnose
```

Narrow it to one inbox, and optionally test one contact's 24-hour window:

```bash
bundle exec rails whatsapp:diagnose INBOX_ID=12
bundle exec rails whatsapp:diagnose INBOX_ID=12 CONTACT=+9655XXXXXXX
```

**What it does and does not do**, guaranteed by construction rather than by a flag:

- every Meta call is a **GET**, through the installation's existing `Whatsapp::FacebookApiClient`
- **nothing is written** — not to Meta, not to the database, not to Redis. The service has no write path. It does
  not subscribe, register, re-register, rotate, delete or clear anything, including the reauthorization flag
- every token, secret and app id is **masked** (`abcd…yz (211 chars)`); customer phone numbers are masked as
  `+9655•••21`; a callback override is printed as scheme/host/port/path only, never with its query string
- one unavailable endpoint is recorded `BLOCKED` and the rest of the report still runs
- the output is **safe to paste back** into this phase or into an issue

## 2. The report's sections, and what each answers

| Section | Answers |
|---|---|
| `CHANNEL` | what this installation has stored: provider, phone number, ids, masked credentials, the reauthorization flag and the error counter, inactive-number listing, coexistence indicators |
| `META IDENTITY` | what Meta says the number is: `display_phone_number`, `verified_name`, `status`, `code_verification_status`, `quality_rating`, `platform_type`, `messaging_limit_tier` |
| `AUTH` | the token's validity, type, app id, scopes and expiry, from `/debug_token`, plus whether `whatsapp_business_messaging` and `whatsapp_business_management` are present |
| `WABA SUBSCRIPTION` | which apps are subscribed to the WABA and with which fields — and whether the configured app is among them |
| `WEBHOOK` | the callback Meta will actually deliver to, classified (§3), and the subscribed-fields comparison against `messages` / `smb_message_echoes` / `message_template_status_update` |
| `LOCAL PIPELINE` | the app secret and verify token presence, the Sidekiq process and `low` queue depth, dead `WhatsappEventsJob` entries, and the installation's Graph API version |
| `CONTACT TEST` | per-inbox incoming/outgoing message counts and timestamps, failed outbound with their `external_error`, and the 24-hour window state for `CONTACT` if given |
| `SUMMARY` + `WHAT TO FIX, IN ORDER` | every check as `PASS` / `FAIL` / `BLOCKED`, then the failures in priority order |

## 3. The callback classification, and why it is the hard one

A phone-level callback override takes **precedence over the Meta App's own webhook configuration**, and it is not
visible in the Meta dashboard. So "the dashboard looks right" proves nothing, and a boolean answer would hide the
part that matters. The `WEBHOOK` section therefore reports a **verdict** qualified by its **source**:

| Printed | Meaning | What to do |
|---|---|---|
| `MATCH (APP_LEVEL_CALLBACK)` | no phone-level override; delivery follows the Meta App's configuration, and it is this installation | nothing — move down the fix list |
| `MATCH (PHONE_LEVEL_OVERRIDE)` | an override exists and points at this installation | nothing, but note that the dashboard no longer governs this number |
| `MISMATCH (PHONE_LEVEL_OVERRIDE)` | an override exists and points somewhere else — the dashboard can look perfect while this is true | the top-priority finding. Re-register via `Whatsapp::WebhookSetupService#register_callback` — do not edit the override by hand |
| `MISMATCH (APP_LEVEL_CALLBACK)` | no override, and the app-level callback is not this installation | fix the app-level callback in the Meta App, then re-run |
| `UNKNOWN` | Meta did not answer the read (permissions, or the field is unavailable) | reported as **BLOCKED, not FAIL**: unproven is not the same as failing, and it must not be read as a pass either. The `BLOCKED` line above it names the Meta error |

Two details that make the verdict trustworthy:

- **The override wins when both exist**, because that is Meta's precedence. A configuration whose `application`
  field matches this installation while its `override_callback_uri` points elsewhere reads `MISMATCH`, which is
  the truth about where the webhook will land.
- **The printed values are scheme, host, port and path only.** An `override_callback_uri` carries its verify token
  in the query string, and this report is meant to be pasted into an issue.

## 4. Per-item status — every live question in this phase

Each row is the question, the document that traces it statically, and what the live run must return.

| # | Live question | Static answer in | Status |
|---|---|---|---|
| 1 | Is the token valid, and what are its scopes and expiry? | `01` | **BLOCKED — RUN ON REAL SERVER** → `AUTH` |
| 2 | Is the number `CONNECTED` and ownership-verified at Meta? | `01` | **BLOCKED — RUN ON REAL SERVER** → `META IDENTITY` |
| 3 | Does the stored `phone_number_id` equal Meta's? | `01`, `04` §4 | **BLOCKED — RUN ON REAL SERVER** → `CHANNEL` vs `META IDENTITY` |
| 4 | Is any app subscribed to the WABA? | `02` | **BLOCKED — RUN ON REAL SERVER** → `WABA SUBSCRIPTION` |
| 5 | Is the **configured** app the subscribed one? | `02` | **BLOCKED — RUN ON REAL SERVER** → `WABA SUBSCRIPTION` |
| 6 | Are `messages` and `smb_message_echoes` among the subscribed fields? | `02`, `07` §3 | **BLOCKED — RUN ON REAL SERVER** → `WEBHOOK` |
| 7 | Where will Meta actually deliver — app-level or a phone-level override? | `03` | **BLOCKED — RUN ON REAL SERVER** → `WEBHOOK`, §3 |
| 8 | Does Meta attempt delivery at all? | `04` step 1 | **BLOCKED — META DASHBOARD** — Webhooks delivery statistics |
| 9 | What HTTP status does the real host return — in particular, is it 401? | `04` §2, §3 | **BLOCKED — HOST ACCESS LOG** + `LOCAL PIPELINE` app-secret check |
| 10 | Is a Sidekiq process consuming `low`? | `04` step 6 | **BLOCKED — RUN ON REAL SERVER** → `LOCAL PIPELINE` |
| 11 | Is the reauthorization flag set on the real channel? | `08` | **BLOCKED — RUN ON REAL SERVER** → `CHANNEL` |
| 12 | Has any inbound message ever persisted for this inbox, and when was the last? | `08` | **BLOCKED — RUN ON REAL SERVER** → `CONTACT TEST` |
| 13 | Is the 24-hour window open for the new contact? | `05` | **BLOCKED — RUN ON REAL SERVER** → `CONTACT TEST` with `CONTACT=` |
| 14 | Do outbound messages reach `delivered` / `read`, or freeze on `sent`? | `06` §1 | **BLOCKED — RUN ON REAL SERVER** → `CONTACT TEST` |
| 15 | What `external_error` do the failed sends carry? | `05`, `06` §3 | **BLOCKED — RUN ON REAL SERVER** → `CONTACT TEST` |
| 16 | Is the number on Coexistence (`is_on_biz_app`)? | `07` | **BLOCKED — RUN ON REAL SERVER** → `META IDENTITY` |
| 17 | Does the realtime update reach the dashboard? | `04` step 12 | **BLOCKED — BROWSER ON THE REAL HOST** |
| 18 | Does a real inbound message now persist end to end? | `04`, `09` §1 | **BLOCKED — REAL HANDSET REQUIRED** |

Nothing in this table is marked passed, and nothing is marked failed. They are unproven here, by design.

## 5. PRODUCTION OPERATOR RUNBOOK

**Step 1 — diagnose, change nothing.**

```bash
bundle exec rails whatsapp:diagnose INBOX_ID=<the real inbox id>
```

Read `WHAT TO FIX, IN ORDER` at the bottom. Do not change any Meta configuration for a check that passed. In
particular: do not create a Meta App, do not create a WABA, do not re-register the number (destructive on
Coexistence — `07` §2), do not disconnect Coexistence, do not rotate the token, do not delete a subscription or a
production template, and do not change the webhook configuration because a check looks suspicious.

**Step 2 — fix the top finding, and only that one.** The common findings and their existing, supported fix:

| Finding | Fix | Never |
|---|---|---|
| `LOCAL PIPELINE`: no app secret configured | set `WHATSAPP_APP_SECRET` to the Meta App's secret. This alone turns every inbound 401 into a 200 (`04` §3) | disable signature verification |
| `WABA SUBSCRIPTION`: no subscribed app | re-run the inbox's webhook setup, which calls `Whatsapp::FacebookApiClient#subscribe_app_to_waba` | hand-roll a subscription call |
| `WEBHOOK`: `MISMATCH` | re-register the callback via `Whatsapp::WebhookSetupService#register_callback`, after confirming `FRONTEND_URL` is the public URL | edit the override by hand |
| `CHANNEL`: `phone_number_id` ≠ Meta's | correct it on the inbox, then re-register the callback | change the number at Meta |
| `CHANNEL`: reauthorization flag set | complete the reauthorization flow for that inbox in the dashboard, which is the only supported clear | `redis-cli DEL` the key — it hides the cause and the flag returns |
| `LOCAL PIPELINE`: no Sidekiq process, or a deep `low` queue | restart or scale the worker | nothing — this is infrastructure |
| `CONTACT TEST`: window closed for the new contact | send an approved template, which is what the window is for (`05`) | retry the plain text; it will fail locally again with the same error |

**Step 3 — re-run the diagnosis.** Confirm the finding you fixed now reads `PASS` and that nothing that previously
passed has regressed. Then send one real inbound message from a handset, and check:

- an incoming message appears in the conversation, in the dashboard, without a refresh
- `CONTACT TEST`'s incoming count has increased and its newest timestamp is the message you just sent
- `log/production.log` has no `[WHATSAPP INGEST] event=…` line for that delivery. If it does, the line names the
  exact step that refused and why (`04` §1)

**Step 4 — outbound.** With the window now open, send a plain text reply to that same contact and confirm it
reaches `delivered`. A message frozen on `sent` means status callbacks are not being ingested either, which is
`06` §1 row 2 and sends you back to the `WEBHOOK` section.

## 6. Paste-back

Paste the diagnosis output below and this phase continues from it — no discovery is repeated. The report is already
masked, so it can be pasted as-is.

````markdown
### Diagnosis output — run <date>, server <host>, INBOX_ID=<id>

```text
<paste the whole output of `bundle exec rails whatsapp:diagnose INBOX_ID=…` here>
```

### Observed behaviour at the time of the run

- inbound from a real handset: appears in Lynomia / does not appear
- outbound to the old contact: delivered / stuck on sent / failed with `<external_error>`
- outbound plain text to the new contact: delivered / failed with `<external_error>`
- any `[WHATSAPP INGEST] event=…` lines in `log/production.log` during the test (paste them; they contain no
  secrets and no message bodies)
- Meta → Webhooks → delivery statistics for the number: attempts / failures over the test window
````

With that, the open questions resolve directly:

| Output says | Conclusion |
|---|---|
| `CHANNEL` reauthorization flag `true`, `CONTACT TEST` incoming count 0 | the defect proven in `08` is what production hit. The fix is already in this branch; deploy it and complete the reauthorization flow |
| app secret `<blank>` | every inbound was answered 401 and never reached the job. Configuration, not code |
| `WABA SUBSCRIPTION` no subscribed app | Meta never attempted delivery. Re-subscribe via the existing service |
| `WEBHOOK` `MISMATCH` | Meta delivered to somewhere else. Re-register the callback |
| all of `CHANNEL`, `AUTH`, `WABA SUBSCRIPTION`, `WEBHOOK` pass and `CONTACT TEST` incoming count is still 0 | the remaining suspect is the host: step 9 of §4. Pull the access log for the callback path |
