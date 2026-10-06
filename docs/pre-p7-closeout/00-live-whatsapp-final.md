# 00 — The real WhatsApp path, verified on the live server

Every line here is from the production server that owns the real WABA (`chat.lynomia.com`, account 6 "batoul",
inbox #77, channel 32, WABA `4584909965122758`, phone_number_id `1357821967407914`). Nothing is inferred from a
fixture, and nothing below is a Platform Production GO — P7 owns that decision.

---

## 1. What was broken, and what it cost

Meta's **effective phone-level callback** for inbox #77 pointed at `chat2.lynomia.com`, a deleted test
environment whose still-enabled nginx vhost proxied to a dead `127.0.0.1:3001`. Every delivery was answered
**HTTP 502** before Rails saw it.

A phone-scope callback beats the app-scope one (`CallbackClassification#effective` — `override.presence ||
app_level`) and **is not visible in the Meta App dashboard**, which is why it sat there unnoticed. The cost was
not only inbound: delivery statuses ride the same `messages` field, so 13 outbound messages sat at `sent` with no
`delivered`, `read` or `failed` ever recorded.

## 2. The fix, and the evidence it worked

The effective phone-level callback now points at the real host.

| | |
|---|---|
| last webhook request to the old chat2 vhost | **06 Oct 2026 09:36:16 UTC → HTTP 502** |
| first healthy request on the correct vhost | **06 Oct 2026 09:37:48 UTC → HTTP 200** |
| chat2 requests after the correction | **none** |

**CHAT2 CALLBACK ISSUE: CLOSED — HISTORICAL TEST ENVIRONMENT.** It is not reopened unless new traffic appears
there after 09:37:48 UTC on 06 Oct 2026.

## 3. The six live scenarios

| # | Scenario | Verdict | Evidence |
|---|---|---|---|
| 1 | old contact → Lynomia inbound | **PASS** | a contact created 2026-06-21 sent real inbound after the repair |
| 2 | Lynomia → old contact | **PASS** | real outbound reached `delivered` |
| 3 | approved template → new contact | **BLOCKED** | see `02` — no approved template exists at Meta yet |
| 4 | new contact → Lynomia | **PASS** | a new contact was created **by** its own first inbound message |
| 5 | plain reply inside the 24h window | **PASS** | after inbound opened the window, plain replies reached `read` |
| 6 | SENT / DELIVERED / READ / FAILED | **PASS** | all four states recorded on real traffic |
| 7 | coexistence | **NOT ENABLED** | `platform_type: CLOUD_API`, no coexistence keys in `provider_config` |

## 4. Meta refusal codes, and what they are not

Two codes were seen, and neither is a Lynomia transport failure.

**131042 — "Business eligibility payment issue."** Observed before billing was settled. Later real traffic reached
`delivered` and `read` on the same channel, so the pipeline was never globally blocked.

**131049 — "This message was not delivered to maintain healthy ecosystem engagement."** Meta's per-recipient
marketing frequency cap. The proof that it is recipient-level and not platform-level is the interleaving: inside
fourteen minutes on the same inbox, WABA, token and code path, two recipients reached `delivered`/`read` while two
others failed, minute by minute. No credential, webhook or code fault can be selective per recipient like that.

In both cases Lynomia behaved correctly: it sent, Meta accepted and returned a wamid, Meta later reported `failed`
via the status webhook, and Lynomia recorded `failed` with Meta's own reason attached.

## 5. One investigation closed as not-a-defect

A suspicion that current code was dropping status callbacks was **disproven**. `spec/jobs/webhooks/
whatsapp_events_job_live_status_spec.rb` carries the real captured payload — `status: failed` with error 131042 and
Coexistence identity fields — through the job to the stored message and proves the path resolves the channel, finds
the message by `source_id`, applies the status, persists Meta's `external_error`, and survives the ActiveJob JSON
round trip Sidekiq performs. Three successive hypotheses (a retry wiping the error, a string/symbol key mismatch,
a broken channel finder) were each disproven; the last two were faults in the test setup, not the product.

Two Sep 29 rows that stayed at `sent` ran under **pre-P5** code. Surviving logs cannot establish why, and no cause
was invented. They are historical and unrecoverable.

## 6. What P5's own hardening was worth, measured in the wild

The Sep 29 worker log contains `Inactive WhatsApp channel: unknown - +15559655462` — a string that **no longer
exists in the codebase**, removed by `e027ee45`. That line is a real `message_template_status_update` carrying
`event: APPROVED` for this WABA, discarded at `WARN` after the controller had already answered Meta `200 OK`, so
Meta never retried. P5's finding was not theoretical: it cost this installation a real template approval. Since the
fix deployed, that drop has not recurred (`"Inactive WhatsApp channel"` = 1 occurrence, the historical one;
`[WHATSAPP INGEST]` = 0).
