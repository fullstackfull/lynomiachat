# واتساب بزنس / WhatsApp Business: real Meta UAT runbook (Phase 4, items 10–16)

**Status in this session: BLOCKED.** This session has no staging server, no Lynomia Meta app credentials and no real test number, and its network policy denies `graph.facebook.com`. Everything below is prepared so the UAT can be run as is.

- **No mock is used here.** The simulated runs are in `../chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md`.
- **Do not run this on production.**

## 0. Prerequisites (owner: Lynomia)

| # | Item | Notes |
|---|---|---|
| P1 | A staging server with a **public HTTPS** `FRONTEND_URL` | Meta only calls HTTPS callbacks. Use a separate DB and Redis from production. |
| P2 | Image built from this repo with `docker/Dockerfile` at the release commit | See `../chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md` §3. Record the tag and `.git_sha`. |
| P3 | Lynomia's Meta app: App ID, App Secret, and a Facebook Login for Business **Configuration ID** of the WhatsApp Embedded Signup type | META-VERIFICATION #14: the configuration and app must be allowed to onboard WhatsApp Business app users (Tech Provider). |
| P4 | One **real WhatsApp Business app number**, used only for UAT | App version ≥ 2.24.17 (META-VERIFICATION #9). Its owner must be able to scan the QR code in the app. |
| P5 | One customer test phone with WhatsApp | For inbound and outbound messages. |
| P6 | Optional: one existing manual Cloud API test number | For the existing WhatsApp API checks on real Meta (item 16). |

## 1. Deploy staging and configure (item 10)

1. Deploy per `../chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md` §5:
   1. backup;
   2. pre-checks;
   3. `POSTGRES_STATEMENT_TIMEOUT=0 rails db:migrate`;
   4. start web + worker;
   5. health checks.
2. In Super Admin → Settings → WhatsApp Embedded, enter:
   - `WHATSAPP_APP_ID`;
   - `WHATSAPP_APP_SECRET` (write-only: the field stays empty after saving);
   - `WHATSAPP_CONFIGURATION_ID`;
   - `WHATSAPP_API_VERSION`.
3. Run the webhook-signature inventory (`WEBHOOK-SIGNATURE.md` §5). Every manual number must be signed by Lynomia's app or have its own `app_secret` stored.
4. Restart web + worker, so that configs cached per process are reloaded.

## 2. Onboard the real number (items 11 and 12)

1. Log in as an **administrator** (agents are refused), then go to Settings → Inboxes → Add inbox → WhatsApp → **WhatsApp Business** (واتساب بزنس).
2. In Meta's popup, choose the option to connect the existing WhatsApp Business app, then finish in the phone app (QR code).
3. Capture the **sanitized server-side diagnostic**. It never contains the code, the token or the App Secret.

   ```bash
   docker logs <web-container> 2>&1 | grep 'WHATSAPP SIGNUP COMPLETION'
   # [WHATSAPP SIGNUP COMPLETION] account_id=.. flow=create is_coexistence=true waba_id=.. business_id_present=.. phone_number_id=..|absent code_present=true result=success
   ```

4. Capture the stored channel **without credentials**:

   ```sql
   SELECT id, phone_number, provider, provider_config->>'source' AS source, provider_config->>'is_coexistence' AS is_coexistence,
          provider_config->>'phone_number_id' AS phone_number_id, provider_config->>'business_account_id' AS waba_id,
          provider_config ? 'verification_pin' AS register_was_called, phone_number_health, phone_number_health_error
   FROM channel_whatsapp ORDER BY id DESC LIMIT 1;
   ```

5. Close VERIFY-META by comparing with `META-VERIFICATION.md` #1–#4 and `../whatsapp-qr/07-meta-coexistence-pivot.md` §D:

| Question | Expected (docs / code) | Observed | Status |
|---|---|---|---|
| Event type | `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` → `is_coexistence=true` | | |
| `waba_id` present | yes | | |
| `business_id` present | not required | | |
| `phone_number_id` present | may be absent; resolved from the WABA if it has exactly one number | | |
| Authorization result | `result=success`, inbox named by phone number | | |
| `/register` not called | `register_was_called` = false (the PIN is stored only after a `/register` call; the query shows no PIN), and no "Phone registration failed" log line | | |
| Channel not flagged for re-auth right after onboarding, and after the next health poll (≤ 6 h) | `reauthorization_required` false | | |

## 3. Real messages (item 13)

Use the customer phone (P5) and the business number (P4). Check in the dashboard and the DB.

| # | Case | Pass criteria | Result |
|---|---|---|---|
| 1 | Inbound Arabic text | incoming, correct text, one conversation | |
| 2 | Inbound English + emoji | incoming, emoji intact | |
| 3 | Inbound image / video / audio (voice note) / document | attachment present and downloadable | |
| 4 | Outbound agent text | delivered to the phone, status `sent → delivered → read` | |
| 5 | Outbound image | received on the phone | |
| 6 | Outbound approved template (Arabic) | received; template sync worked | |
| 7 | Outbound quoted reply | shown as a reply on the phone | |
| 8 | Owner replies from the **phone app**: text, image, quoted reply | appears as **outgoing** in the **same** conversation (`smb_message_echoes`), not duplicated | |
| 9 | Echo of a message sent from Lynomia | not duplicated | |
| 10 | Timestamps | match the phone within a few seconds | |

Duplicate check:

```sql
SELECT source_id, count(*) FROM messages WHERE inbox_id = <inbox> GROUP BY 1 HAVING count(*) > 1;
-- expected: 0 rows
SELECT count(DISTINCT conversation_id) FROM messages WHERE inbox_id = <inbox>;
-- expected: 1 for one customer
```

## 4. Coexistence behaviour (item 14)

| Check | Pass criteria | Result |
|---|---|---|
| The phone app keeps working after onboarding | the owner can still send and receive in the app | |
| No `/register` | see §2 | |
| No false re-auth prompt | no re-auth banner or email over 24 h | |
| Not QR/Evolution | no Evolution service deployed; UI says "WhatsApp Business" / "واتساب بزنس", never "WhatsApp QR" | |
| Webhook signature | `grep 'Rejected Meta webhook' <web logs>` shows no rejections for this number | |

## 5. Disconnect, offboarding and reconnect (item 15)

Record what happens. Only the last row deletes history, and it does so on purpose: deleting an inbox deletes its conversations in upstream Chatwoot.

| Step | How | Expected | Result |
|---|---|---|---|
| Revoke Lynomia's access in Meta Business settings | remove the partner / app from the WABA | sends fail with a Meta error and the message is marked failed; no crash. **Known limitation:** Lynomia is not told (`account_offboarded` not handled, META-VERIFICATION #13) | |
| Disconnect from the phone app | the app's option to disconnect from the partner | incoming stops. Same known limitation | |
| Reconnect / re-authorize | Settings → Inbox → Configuration → Reconfigure (admin) | same inbox and same history; `is_coexistence` kept | |
| Remove the inbox | Settings → Inboxes → delete | inbox and its conversations removed (upstream behaviour); other inboxes on the same WABA keep receiving webhooks (`spec/controllers/api/v1/accounts/whatsapp/shared_waba_inbox_deletion_spec.rb`) | |

## 6. Existing WhatsApp API on real Meta (item 16)

With P6: send and receive text and media, and send a template. There must be no reconnect, no credential change and no re-auth prompt.

The full 41-check regression was run against simulated Meta in the rehearsal. On a disposable staging DB it can be repeated with the harness (it creates test tenants): `../chatwoot-upgrade/staging-harness/README.md`.

## 7. Exit

- Fill the tables above, then update `META-VERIFICATION.md` #4, #9, #13, #14 and #15.
- Attach the sanitized log lines and SQL outputs. **Never attach tokens, codes or the App Secret.**
- If any row fails: stop, keep staging as is, and roll back per `../chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md` §6 if needed.
