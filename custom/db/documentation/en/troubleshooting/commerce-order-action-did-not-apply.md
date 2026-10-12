---
title: An order action did not apply
description: What each order-action outcome means, why “we do not know” is a real answer, and why the product refuses to send a refund twice.
position: 64
tags: [troubleshooting, commerce]
seo_description: "A Lynomia Chat order action that failed or is unknown: ORDER_CHANGED, NOT_APPLIED, REFUND_DECLINED and unknown outcome, and what to do about each."
---
An order action — cancelling an order, changing its status, issuing a refund — is the only thing Lynomia
**writes** to your store. Everything about how it behaves follows from one rule: **a write is never sent
twice.** A duplicate refund is worse than a failure you can see.

## Every outcome, and what to do

| What you see | The code | What actually happened | What to do |
|---|---|---|---|
| “The order changed while you were looking at it” | `ORDER_CHANGED` | somebody else changed the order between the panel loading and the action being sent | re-open the order and try again on the current state |
| “That did not apply” | `NOT_APPLIED` | the store accepted the request and the order is provably unchanged | safe to try again |
| “Your store declined the refund” | `REFUND_DECLINED` | the payment gateway refused, not the store | refund from the store's own admin, where the gateway's reason is visible |
| “Your store refused that” | `PROVIDER_REJECTED` | the store rejected the action itself | check the order in the store's admin; it is usually in a state that does not allow it |
| “That action is already running” | `ACTION_IN_PROGRESS` | the same action is in flight | wait; do not start a second |
| “That amount is not valid” | `INVALID_AMOUNT` | the amount is outside what the order allows | check the order total and what has already been refunded |
| “We do not know whether that applied” | an unknown outcome | the request was sent and the answer was lost | **read the rest of this page** |
| “Order actions are turned off” | `ACTIONS_DISABLED` | the switch is off for this store | an administrator turns it on in Settings → Commerce |
| “That action is not available for this store” | `ACTION_UNAVAILABLE` | the platform does not support it | nothing; it is a capability, not a fault |

## “We do not know” is an honest answer, not a bug

If the request reached your store and the answer was lost — a timeout after sending, a dropped connection —
then Lynomia genuinely cannot tell whether the action applied. It will not guess, and it will not send the
action again to find out.

What it does instead:

1. **It reads the order back**, a little later, and judges only by what the store says now. If the order is in
   the state the action asked for, the action succeeded. If it is provably in the state it started in, the
   action failed and is safe to retry.
2. **If reading back cannot settle it**, the action stays recorded as unknown, and the panel says so.
3. **It never re-sends.** An action that may have applied is not sent again by the product under any
   circumstances.

If an action is sitting at unknown, open the order in your store's admin. That is the authoritative answer, and
it takes a few seconds.

## Why actions are deliberate rather than convenient

- they are **off per store** until an administrator turns them on;
- they need credentials that can write — see **Your store keys cannot do that**;
- they are checked against the order **as the agent saw it**, which is what produces `ORDER_CHANGED` rather
  than a surprise;
- every one is recorded with who ran it and what the store answered.

That is four opportunities for an action to be refused, and each refusal is a sentence rather than a silence.
