# P10 — UAT runbook

What a human has to do on a real installation, in order, and what each step proves. Nothing in this file has
been run: there is no staging server, no provider credential and no production access in the session that wrote
P10, and the brief forbids touching production. Every step is therefore **PENDING REAL UAT**.

Read this with `docs/p9/07-uat-runbook.md` and the P8 items still pending: P10 adds to that list, it does not
replace it.

---

## 0. Before anything

| check | why |
| --- | --- |
| The branch deployed is `claude/p10-omnichannel-unified-identity`, and P8 and P9 are in it | P10 builds on both; the Operations Center and the support module must already be present |
| `bundle exec rails db:migrate` has run and `db/schema.rb` matches | two migrations: `contact_identities`, and the partial index on `contacts` |
| `ChatwootApp.extensions == ["custom"]` and `ChatwootApp.enterprise?` is `false` | P10 assumes the Enterprise overlay is absent |
| A **pilot account** is chosen, and it is not the busiest one | every step below writes to it |

**Do not enable anything for every account at once.** `lynomia_unified_identity` is per account and off by
default; turn it on for the pilot only.

## 1. The feature flag, both ways

1. With the flag **off**, open a contact. There must be **no Identities tab**. The product must behave exactly
   as it did before P10.
2. `GET /api/v1/accounts/<id>/contacts/<contact>/identities` must answer **404**, not 403 and not an empty list.
3. Super Admin → Accounts → the pilot account → enable **Lynomia Unified Customer Identity**.
4. Reload. The Identities tab must appear.

**Proves:** the flag means what §9 of docs/p10/03-unified-customer-identity.md says.

## 2. The permission split

| as | expected |
| --- | --- |
| administrator | sees the tab, the add form and the Unlink controls |
| agent with no custom role | sees the tab and the list, **no** add form, **no** Unlink |
| agent whose custom role grants `contact_manage` | sees everything the administrator sees |

Then, as the plain agent, POST to the identities endpoint directly (curl or devtools). It must answer
**401**, and no row must be created.

**Proves:** reading follows the contact, writing follows the merge, and the boundary is on the server rather
than in the UI.

## 3. Link a second number, and prove the inbound match

1. Pick a contact that already has a phone number. Note it.
2. On the Identities tab, link a **second, real number you control** (type: Phone).
   - The list must show it under *Also reachable at*, marked *Linked by an agent*.
3. From that second number, send a message to a channel the pilot account has connected **that the contact has
   never used** — a different WhatsApp number, or an SMS inbox.
4. The message must arrive in the **existing contact's** conversation list. The account's contact count must
   not increase.

**Proves** the thing P10 exists for. Before P10 this created a second contact
(docs/p10/03-unified-customer-identity.md §2).

### 3a. The same for an email address

Link a second email address, then send mail from it to the account's email inbox. Same expectation.

## 4. A conflict must be refused, and must name the other contact

1. Find a **different** contact's phone number.
2. Try to link it to your test contact.
3. The form must show a refusal naming the other contact's id, and **no row** must be created.
4. Try the reverse: edit the other contact and set its primary phone number to a value already linked to your
   test contact. The save must be refused with *"is already linked to another contact in this account"*.

**Proves:** one value, one contact, checked from both sides, and the product refuses rather than guesses.

## 5. A local number with no country must be refused

Type `0551112233` (no `+`, no country) and link it. It must be refused with a message mentioning the country.
Then set the contact's `additional_attributes.country_code` to its country and try again — it must now be
accepted and stored in `+…` form.

**Proves** PART M: no default region, no guessed country.

## 6. The merge, end to end

Set up a contact pair that exercises everything:

| on the contact that will be **destroyed** | why |
| --- | --- |
| a conversation with messages | OSS already moves these |
| a note | OSS already moves these |
| a label the survivor does not have | the gem's counters must stay right |
| a campaign that was sent to it | was **deleted** before P10 |
| a support case | lost its customer before P10 |
| a commerce store link, and an abandoned cart on that link | the link was **deleted** before P10 |
| a CSAT response | was **deleted** before P10 |
| a second phone number as its primary field | was **destroyed** before P10 |

Also give the **surviving** contact a campaign recipient for the *same* campaign and a link to the *same* store,
so the discard path runs.

Then merge, and check every one of these:

1. The conversation, messages, note and label are on the survivor.
2. The campaign recipient from the destroyed contact is on the survivor; the duplicate for the shared campaign
   is gone and **counted** (step 7).
3. The support case points at the survivor.
4. The commerce link for the store the survivor did not have is on the survivor; for the shared store the
   survivor's own link is kept and the cart that was on the discarded one now points at **the kept link**.
5. The CSAT response is on the survivor.
6. The destroyed contact's phone number appears on the Identities tab, marked **From a merge**.
7. Send a message from that number to a channel neither contact had used. It must reach the survivor.
8. The merge modal said, before you confirmed, that it **cannot be undone** and listed what carries over.

## 7. The audit record

Settings → Audit Logs (needs the `audit_logs` account feature and an administrator).

- There must be one new row, `contact.merged`, against the surviving contact.
- Its payload must carry `base_contact_id`, `mergee_contact_id`, `moved`, `discarded_duplicates` and
  `identities_absorbed`.
- It must contain **no phone number, no email address and no name**. Read it and confirm.

## 8. Channel connection state

For every channel the pilot account has connected, open the inbox settings and compare what the page says with
what `GET /api/v1/accounts/<id>/inboxes/<id>` returns in `connection_state`:

| channel | expected `status` |
| --- | --- |
| Website, API | `unknown`, reason "no external provider" |
| Telegram, LINE, Twilio, Bandwidth SMS, X | `unknown`, reason "nothing in this installation reports…" |
| WhatsApp, Email, Facebook, Instagram, TikTok — working | `healthy` |
| any of those five — latched | `critical` |

Then **break one on purpose**, on a channel you can restore:

1. Change the IMAP password at the mail provider (or enter a wrong one), and let
   `Inboxes::FetchImapEmailsJob` run ten times (`AUTHORIZATION_ERROR_THRESHOLD = 10`).
2. The inbox must show the sidebar warning — **to an agent as well as to an administrator**. Before P10 a plain
   IMAP inbox showed nothing to anybody (docs/p10/06-channel-lifecycle-health.md §1).
3. `connection_state.status` must be `critical`.
4. Fix the password and save. The latch must clear and the warning must go.

## 9. The Operations Center channels column

Super Admin → Operations.

1. With the broken inbox from step 8, the pilot account's **channels** column must read `critical`, with
   "N channels cannot connect" — not `healthy`.
2. On an account whose only inbox is Telegram, LINE, Twilio, Bandwidth SMS or X, the column must read
   `unknown`, with "N channels do not report whether they are connected".
3. On an account with only a web widget, it must read `healthy`.

**Known limitation to expect:** a channel that was already latched **before P9 shipped** has a Redis flag but no
signal row, so the console counts it as unreported until its next transition. The inbox page itself is right
either way (docs/p10/06-channel-lifecycle-health.md §4).

## 10. The credential masking

1. Open an email inbox's IMAP settings as an administrator. The password field must be **empty**, with the
   placeholder *"Leave blank to keep the current password"*.
2. In devtools, inspect the inbox response. There must be **no** `imap_password` and **no** `smtp_password`,
   only `imap_password_configured` / `smtp_password_configured`.
3. Change the IMAP **address** only, leave the password blank, save. Mail must keep arriving — the stored
   password must still work.
4. Now type a new (correct) password and save. It must take effect.
5. For a Twilio inbox, confirm the response has no `auth_token`, only `auth_token_configured`, and that
   `account_sid` is still there.

**Proves** PART P for the three credentials that were sent in plaintext, and proves the masking did not become
a data-loss bug.

## 11. TikTok — PENDING, no credential here

There is no TikTok credential in the environment P10 was built in, so this is untested against the provider:

1. Connect a TikTok inbox.
2. Have one TikTok user start a conversation, resolve it, then start a **second** conversation.
3. The second conversation must attach to the **same contact**. Before P10 it created a new one
   (docs/p10/02-channel-capability-matrix.md §3).
4. Contacts already duplicated by the old behaviour stay duplicated. Join them with the merge (step 6); no
   backfill is proposed and none should be run.

## 12. WhatsApp — unchanged, and still gated

The P3 gate is **carried forward exactly as it was** and P10 changed nothing about it:

- template `order_delivered`, language `en_US`, status APPROVED
- sent to a **genuinely new Contact**, from the real production number
- **not** during development, and not from this branch's test environment

P10's only WhatsApp-facing changes are that a manually configured number now reports its reauthorization latch,
and that the inbox payload reports the latch for plain IMAP email. Neither sends a message. Confirm in passing
that connecting a number still works and that the number's health still syncs.

## 13. What is NOT in this runbook, and why

- **Nothing to deploy to production.** Production stays on
  `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4` until the combined P8+P9+P10+P11+P-FINAL plan.
- **No backfill.** `contact_identities` starts empty by design, and nothing in P10 asks for one.
- **No voice calling.** The four endpoints the dashboard posts to do not exist
  (docs/p10/02-channel-capability-matrix.md §3b); that is a known broken surface, not a P10 step.
- **No Bandwidth SMS repair.** Its unauthenticated webhook and always-raising delivery receipts are recorded for
  the P-FINAL security audit, not fixed here.
