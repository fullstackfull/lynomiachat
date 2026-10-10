# P11 — UAT runbook

What a human has to verify on a real installation before commercial enforcement is switched on for paying
customers. Nothing in this file was executed by the implementation: every row below is **PENDING REAL UAT**.

---

## 0. Before you start

**Use Stripe test mode.** A test-mode secret key (`sk_test_…`) and a test-mode webhook secret
(`whsec_…`). Do not point a staging installation at live keys, and do not run any of this against
production, which remains `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`.

You need:

* a staging installation on this branch, with the four P11 migrations applied,
* Super Admin access,
* two test accounts (**A** and **B**) with at least one administrator and one agent each,
* a Stripe test-mode account with the CLI (`stripe listen --forward-to <host>/billing/webhooks/stripe`) or a
  configured webhook endpoint,
* the Stripe test cards: `4242 4242 4242 4242` (succeeds), `4000 0000 0000 0341` (attaches, then fails on
  charge), `4000 0000 0000 9995` (declines).

Record for each step: date, who ran it, the result, and anything that differed from the expected column.

---

## 1. Deploy safety — do this first, before configuring anything

| # | Step | Expected |
|---|---|---|
| 1.1 | Deploy the branch with **no** Stripe keys and **no** trial plan | Both accounts work exactly as before. No 402 anywhere. |
| 1.2 | As an agent of A, open conversations, send a reply, create a contact | Unchanged |
| 1.3 | As an administrator of A, create an inbox of any channel type | Succeeds — no plan, so no ceiling and no channel rule |
| 1.4 | Invite an agent to A | Succeeds |
| 1.5 | Open Settings → Billing in the dashboard | The subscription page renders; status "inactive"; no crash and no redirect off the product |
| 1.6 | Send a customer message into A from a real channel (WhatsApp or the widget) | Received and attributed as before |

**If any row in §1 fails, stop.** Deploying must be a no-op.

---

## 2. Plans and the console

| # | Step | Expected |
|---|---|---|
| 2.1 | Super Admin → Billing Plans → New: "Starter", 9 USD / month, flat, limits agents 2 / inboxes 2, no channels, no features | Saved. Flash may say Stripe sync failed — expected until §3. |
| 2.2 | Create "Pro", 29 USD / month, limits agents 10 / inboxes 10 / stores 3, features including `lynomia_commerce`, channels: Website, WhatsApp, Api | Saved |
| 2.3 | Open Starter → Edit | **No** blast-radius warning (nobody is on it yet) |
| 2.4 | Plan show page | Limits read "Agents: 2 · Inboxes: 2 · Commerce stores: ∞"; channels read "All channels (no restriction)" |
| 2.5 | Pro show page | Channels read "Api, Website, Whatsapp" |
| 2.6 | Try to save a plan with a negative limit | Refused with a validation error |

---

## 3. Stripe wiring

| # | Step | Expected |
|---|---|---|
| 3.1 | Super Admin → Billing Settings: paste the **test-mode** secret key and webhook secret | Saved. The page shows `sk_test...<last 4>`, never the whole key. |
| 3.2 | Reload the settings page and read the HTML source | No full secret key and no full webhook secret anywhere in the page |
| 3.3 | Super Admin → Billing Plans → Starter → Save (to trigger a sync) | Flash reports success; the plan now has a `stripe_product_id` and a `stripe_price_id` |
| 3.4 | Check Stripe test dashboard → Products | "Starter" and "Pro" exist with the right amounts |
| 3.5 | **Now** check accounts A and B | ⚠️ `enforced?` is true. An account with no subscription is **locked** (402). This is the ordering trap in `06-rollout-compatibility.md` §3. |
| 3.6 | Run `Billing::TrialStarter.backfill!` (or grant a plan to each account) | Both accounts usable again, on a trial or a granted plan |

---

## 4. The customer journey

Use account **A**, signed in as its administrator.

| # | Step | Expected |
|---|---|---|
| 4.1 | Settings → Billing | Plan, status, period dates, and a usage card reading "used / limit" per resource |
| 4.2 | Read the usage card with an unlimited resource | Shows "2 / Unlimited" — never "2 / -1", never "2 / 0" |
| 4.3 | Switch the dashboard to Arabic | Every string on the page is Arabic, "غير محدود" for unlimited, layout right-to-left, no clipped or overlapping text |
| 4.4 | Click Subscribe on Pro | Redirected to Stripe Checkout on Stripe's domain |
| 4.5 | Pay with `4242…` | Returned to the product; within a few seconds the status is `active` on Pro |
| 4.6 | Stripe CLI / dashboard → events | `checkout.session.completed` delivered; the installation answered 200 |
| 4.7 | Super Admin → Subscriptions → A | `active`, source `stripe`, a Stripe customer and subscription id |
| 4.8 | Re-send the same `checkout.session.completed` from the Stripe dashboard | Answered 200, and **nothing changes**: no second charge, no duplicate row, and the webhook events table shows one row for that event id |
| 4.9 | Click Manage billing / Payment method | Stripe Customer Portal opens on Stripe's domain |
| 4.10 | In the portal, change the card to `4242…` (a different one) | Succeeds. No card data appears anywhere in the product. |

### Plan change

| # | Step | Expected |
|---|---|---|
| 4.11 | Choose Starter (a downgrade) | A confirmation shows the amount, or the credit, and the currency |
| 4.12 | Confirm | Applied; the status stays `active`; the plan is Starter; Stripe shows a proration line |
| 4.13 | Upgrade back to Pro, leave the confirmation open for **20 minutes**, then confirm | Refused: *"This quote is no longer valid. Please review the amount again."* Nothing was charged. |
| 4.14 | Preview again and confirm straight away | Applied, and the amount charged matches the amount shown |
| 4.15 | As an **agent** of A (not an administrator), try to subscribe or change plan | Refused, 403: "Only administrators can manage billing" |

### Dunning and the lock

| # | Step | Expected |
|---|---|---|
| 4.16 | In Stripe, swap A's payment method to `4000 0000 0000 0341` and force the next invoice to fail (advance the test clock, or void and recreate the invoice) | A webhook moves the subscription to `past_due`; the grace period is set once |
| 4.17 | Use the dashboard during the grace period | Works, with the billing page showing the grace deadline |
| 4.18 | Let the grace period pass (or set `grace_period_ends_at` into the past in the console) | Every account-scoped request answers `402 subscription_required`; Settings → Billing still opens so the customer can pay |
| 4.19 | While locked, send a customer message into A from a real channel | **Received and stored.** Inbound customer traffic is never refused over a billing state. |
| 4.20 | Pay the outstanding invoice in the portal | A webhook returns the subscription to `active`; the dashboard is usable again |
| 4.21 | Cancel in the Super Admin (Cancel subscription now) | Stripe shows cancelled; the row is `canceled`; the account is locked |

---

## 5. Limits

Use account **B** on Starter (agents 2, inboxes 2).

| # | Step | Expected |
|---|---|---|
| 5.1 | B has 2 agents. Invite a third | Refused, 422, *"Your plan allows up to 2 team members. Upgrade your plan to invite more."* |
| 5.2 | The same in Arabic | The Arabic sentence, with the number |
| 5.3 | Create a third inbox | Refused, 422, with the inbox message |
| 5.4 | **Two administrators invite a different agent at the same moment** (two browsers, both click within a second) while B has 1 of 2 seats used | Exactly **one** succeeds. The other is refused. B ends with 2 agents, never 3. |
| 5.5 | Super Admin → B → Overrides → Limit → inboxes → 5, reason "migrating from a competitor" | Saved; the override appears in the table with the reason and the operator |
| 5.6 | Create a third inbox on B | Succeeds |
| 5.7 | B's billing page | The inbox row reads "3 / 5" — the override's ceiling, not the plan's 2 |
| 5.8 | Revoke the override | The row disappears; B's billing page reads "3 / 2"; a fourth inbox is refused; **the three existing inboxes are still there** |
| 5.9 | Grant a limit override with an expiry of tomorrow, then move it into the past in the console | The ceiling falls back to the plan's with no job run; the console still shows the row, marked lapsed |
| 5.10 | Connect Commerce stores up to the plan's ceiling, then one more | Refused with `STORE_LIMIT_REACHED`, shown in English and Arabic from `commerce.json` |
| 5.11 | Disconnect a store, then connect a different one | Succeeds — a disconnected store holds no slot |

---

## 6. Channels

| # | Step | Expected |
|---|---|---|
| 6.1 | B is on Starter (no channel list). Create an inbox of any type | Succeeds |
| 6.2 | Set Starter's channels to Website only | Saved, with the blast-radius warning shown first |
| 6.3 | Create a Website inbox on B | Succeeds |
| 6.4 | Create a WhatsApp inbox on B | Refused, 422, naming the WhatsApp channel |
| 6.5 | The WhatsApp inbox B already had | **Still present, still receiving messages, history intact** |
| 6.6 | Super Admin → B → Overrides → Channel → Whatsapp → Allow, reason "contracted separately" | A new WhatsApp inbox now succeeds |
| 6.7 | Override Channel → Whatsapp → **Deny** on an account whose plan does sell it | A new WhatsApp inbox is refused; existing ones keep working |
| 6.8 | POST directly to the inboxes endpoint with a channel the plan does not sell (bypassing the UI) | Refused by the server. Hiding the tile is not the gate. |

---

## 7. Isolation and authorization

| # | Step | Expected |
|---|---|---|
| 7.1 | As an administrator of A, request `/api/v1/accounts/<B>/billing` | Refused — not A's account |
| 7.2 | As an administrator of A, request `/api/v1/accounts/<B>/billing/entitlements` | Refused |
| 7.3 | As an administrator of A, POST to A's `revoke_override` route | The Super Admin routes are not reachable with a user session at all |
| 7.4 | As an agent of A, open Settings → Billing | The page loads read-only; the subscribe and manage buttons are absent |
| 7.5 | Forge a Stripe webhook: POST a plausible JSON body to `/billing/webhooks/stripe` with no `Stripe-Signature` | `400`, and nothing changes |
| 7.6 | Same, with a signature computed using an **empty** secret | `400`, and nothing changes |
| 7.7 | Temporarily clear the webhook secret in Billing Settings, then POST any body | `401`, and nothing changes. Restore the secret. |
| 7.8 | Send a correctly signed event whose `metadata.account_id` names account **A** but whose customer id belongs to **B** | B is updated (the server-owned customer mapping wins); A is untouched |
| 7.9 | Read every billing response and page source you have opened in this run | No `sk_test_`, no `sk_live_`, no `whsec_`, no card number, no payment-method token |

---

## 8. Operator observability

| # | Step | Expected |
|---|---|---|
| 8.1 | Super Admin → Subscriptions → an account | Plan, usage against the enforced limits, status, source, dates, Stripe ids, the plan's channels, and the overrides table |
| 8.2 | Grant and revoke an override, then open Settings → Audit Logs on that account | Two entries: `billing.override_granted` and `billing.override_revoked`, each with the operator and the reason |
| 8.3 | Edit a live plan's limits, then read the audit log | `billing.plan_entitlements_changed` with the before/after and the number of paying accounts affected |
| 8.4 | Break the webhook deliberately (point Stripe at the endpoint with a wrong secret), send an event | Stripe reports the failure; the installation answered 401/400; nothing silently succeeded |
| 8.5 | Cause a sync failure (e.g. revoke the Stripe key mid-flow, then change a plan) | The Operations Center shows a billing signal; Sentry has the exception |
| 8.6 | A customer's card declines (`4000 0000 0000 9995`) | The subscription state reflects it. **No** operations signal — a declined card is a commercial event, not an incident. |

---

## 9. Sign-off

| Area | Result | Who | Date | Notes |
|---|---|---|---|---|
| §1 Deploy safety | PENDING | | | |
| §2 Plans and console | PENDING | | | |
| §3 Stripe wiring | PENDING | | | |
| §4 Customer journey | PENDING | | | |
| §5 Limits (incl. 5.4 concurrency) | PENDING | | | |
| §6 Channels | PENDING | | | |
| §7 Isolation and authorization | PENDING | | | |
| §8 Observability | PENDING | | | |

A row may be marked PASS only by a person who ran it against a real Stripe test-mode account. Seeded
repository tests do not satisfy any row here, and none of these rows is marked passed anywhere in this phase's
reporting.
