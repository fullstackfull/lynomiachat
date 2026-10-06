# 00 — The environment this phase ran in

P5 asks for real UAT against the real WhatsApp number. This document records, first and plainly, **what this
environment can and cannot prove**, because every other document in this set depends on it.

---

## 1. What was checked, and what was found

| | |
|---|---|
| Branch | `claude/practical-thompson-9xfqed` |
| HEAD at the start of P5 | `616f26e4` (P4 closeout) |
| Container | ephemeral cloud container, rebuilt per session |
| Network to `graph.facebook.com` | **reachable** — verified, see §2 |
| Real Meta access token | **absent** |
| Real WABA id | **absent** |
| Real `phone_number_id` | **absent** |
| A phone able to send a WhatsApp message to the business number | **absent** — not something this environment has |
| The server Meta's webhook callback URL points at | **not this container** |

### The only WhatsApp channel in this container

```
channel_id=1  provider="whatsapp_cloud"  phone_number="+96590000001"
inbox_id=1    inbox_name="WhatsApp Support"  account_id=1
provider_config: api_key="fixture_key" (11 chars)
                 business_account_id="WABA_LYNOMIA"
                 phone_number_id="555000111"
                 source="embedded_signup"
```

Every one of those values is **fixture data** created by earlier phases for testing. `WABA_LYNOMIA` is not a Meta
id; `555000111` is not a phone number id; `fixture_key` is not a token. Nothing about this record describes the real
production number, and **no finding in this document set is a statement about the production WABA** unless it says
so explicitly and cites a real response.

---

## 2. The network is not the blocker

Worth establishing separately, because "the container cannot reach Meta" would be a different and much worse
situation:

```
$ curl -o /dev/null -w "%{http_code}" https://graph.facebook.com/v24.0/
400
```

A 400 is Graph's normal answer to a versioned path with no node and no token — TLS, DNS and the egress proxy all
worked. Confirmed again, more usefully, by running the diagnosis task built in this phase against the fixture
channel: it reached Meta and came back with Meta's own error.

```
BLOCKED token debug — RuntimeError: Token validation failed:
  {"error":{"message":"Error validating application. Invalid application ID.",
            "type":"OAuthException","code":190,"fbtrace_id":"..."}}
BLOCKED WABA app subscription (/WABA_LYNOMIA/subscribed_apps) —
  {"error":{"message":"Invalid OAuth access token - Cannot parse access token",
            "type":"OAuthException","code":190,"fbtrace_id":"..."}}
```

That is Meta rejecting a fake token, which is exactly correct. **It proves the client, the request shape and the
egress path all work**, and therefore that the same task run on the real server with the real token will return
real answers.

---

## 3. What that means for each part of P5

| Part | Needs | Status here |
|---|---|---|
| A — channel identity | the real channel row | **code + tooling done**; the real values come from the operator's run |
| B — phone status | a real token | **tooling done, read BLOCKED here** |
| C — WABA subscription | a real token | **tooling done, read BLOCKED here** |
| D — webhook fields | a real token | **tooling done, read BLOCKED here**; the code side is answered in `03` |
| E — inbound trace | a phone, and the real server | **BLOCKED**; the code path is traced statically in `04` |
| F — classify the inbound failure | E's evidence | **candidates ranked with code evidence in `08`**, not asserted |
| G — the fix | F's proof | **not applied**; nothing is changed without the proof P5 Rule 1 demands |
| H, I — new-contact template send | a real token and a real recipient | **BLOCKED** |
| J, K — service-window and old-contact tests | a phone | **BLOCKED** |
| L — delivery statuses | real sends | **BLOCKED** |
| M — coexistence | the real number | **code side audited in `07`**, live behaviour BLOCKED |
| N — phone normalization | — | **done**, `app/services/contacts/phone.rb` audited |
| P — queue/worker | the real server | **tooling done**; checks the real worker when run there |
| R — Graph API version | — | **done**, and not changed; see `08` |
| S — security | — | **done**; no check weakened, nothing logged |

**Nothing in this set is marked PASS on the strength of a guess.** Where the brief asks for a live result that this
environment cannot produce, the answer is BLOCKED and the reason is named.

---

## 4. How the blocked parts get unblocked

The live half of the diagnosis was built as one read-only command, so the operator supplies the evidence rather than
a credential:

```bash
# on the server that owns the real WhatsApp inbox
bundle exec rails whatsapp:diagnose

# narrowed to one inbox, and asking about one contact's 24-hour window
bundle exec rails whatsapp:diagnose INBOX_ID=<id> CONTACT=+<number>
```

It performs only GETs, through the installation's existing `Whatsapp::FacebookApiClient`; it writes nothing to Meta
and nothing to the database; and it masks every token, secret and customer number, so its output is safe to paste
into an issue. What it answers, and why each check is there, is in `02` and `03`.

**Asking for the token instead would be the wrong trade.** A production WhatsApp token can send messages to real
customers as the business; it does not belong in an ephemeral container, in a transcript, or in a repository. The
task exists so the credential never has to move.

---

## 5. The continuation: what changed about this environment, and what did not

The continuation of this phase asked for inbound reliability hardening on top of the diagnosis. Two things are
worth recording about the environment it ran in, because they bound what its claims mean.

**What did not change.** Everything in §1 still holds. No real token appeared, no real number, no handset, and this
container is still not Meta's callback destination. The continuation therefore produced **no** production finding,
and deliberately does not contain the sentence "production root cause confirmed" anywhere. What it proved is
narrower and stated in exactly those terms in `08`: *the repository contains defects capable of producing exactly
the observed symptoms* — proven by reading the code and by tests that execute the failure.

**What did change.** The local stack was brought up and used as evidence rather than as a formality:

| | |
|---|---|
| Postgres | 16, `/tmp/pgdata`, started per session |
| Redis | `redis-server --port 6379`, which is what makes the reauthorization latch and the dedup lock observable |
| Ruby | via `rbenv`, `eval "$(rbenv init -)"` before every `bundle` command |
| Test suite | the full RSpec suite plus a new request spec, `spec/requests/whatsapp/inbound_reliability_spec.rb` |

That matters because the central defect is a Redis latch. With Redis running, the latched state can be created in a
test, the inbound payload posted, and the drop observed — which is the difference between "this code looks wrong"
and "this code does this". Each claim in `08` marked **PROVEN** is proven that way.

**One environment hazard, recorded because it has now cost time three times.** Two distinct traps, and the second
is the expensive one.

*Editing an autoload path while the suite runs* makes Rails reload constants mid-run, and the result is a wave of
failures that look real and are not — the previous phase lost an hour to 75 of them. So the suite's verdict is
only taken from a run with no concurrent edits, and while a run is in flight only `docs/` is touched.

*`rails runner` against `RAILS_ENV=test` commits rows that no spec transaction will roll back*, and a surprising
number of assertions in this suite query a table **globally** rather than scoping to the records the example
created. One stray row then fails a spec that is perfectly correct. Three rounds of this:

| Round | Leftover | What failed |
|---|---|---|
| P4 | debug rows from a `rails runner` session | 75 spurious failures |
| continuation, first | a `Contact` named "Jane" | 7 in `incoming_message_service_spec.rb` |
| continuation, second | 2 `audits`, 14 orphaned `working_hours`, 1 `installation_configs` | 11, across three unrelated files |

The third round is worth dissecting, because each failure was a *correct* spec meeting a global query:

- `Audited::Audit.where(auditable_type: 'Inbox', action: 'create').count == 1` → `got: 3`, the example's own audit
  plus two leftovers.
- `InstallationConfig.count == 0` as a **precondition** → `got: 1`.
- `WorkingHour.today` resolves its timezone via `first.inbox` — an unscoped `ORDER BY id LIMIT 1`. An orphaned row
  has the lowest id, so `inbox` is nil and `inbox.timezone` raises. Orphans are structurally possible because
  `working_hours` has **no foreign key** to `inboxes` and `out_of_offisable.rb` associates them with
  `dependent: :destroy_async`, so the destroy job never runs under `Sidekiq::Testing` — even a correct `destroy`,
  not just a `delete_all`, strands seven rows per inbox, permanently.

Each was reproduced deliberately — insert the row, watch exactly those lines fail with exactly that message; remove
it, watch the file pass — before being called pollution. None was called a flake. The fix is
`rails db:test:prepare`, which rebuilds the schema rather than guessing which tables to clean, and the
authoritative suite result is only ever taken from a run that started on a rebuilt database.

**And the same trap produced a real finding against this phase's own work.** The leftover
`installation_configs` row was named `WHATSAPP_API_VERSION`, timestamped to the minute the diagnosis task was
first run by hand. That row was the diagnosis writing to the database: `GlobalConfigService.load` is
create-on-read, and `/debug_token`'s app access token is built from `WHATSAPP_APP_ID` and `WHATSAPP_APP_SECRET`
through the same accessor — so on a production server the "read-only" task would have written the app secret into
`installation_configs`. `FINAL-CHECKPOINT.md` §27 records what was changed. A piece of test-database rubbish is a
strange place to find a security defect, which is the argument for root-causing pollution instead of deleting it.
