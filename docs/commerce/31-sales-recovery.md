# Lynomia Commerce: sales recovery (Phase 9–10)

How an agent turns an abandoned cart (doc 30) into a message to the customer, without Lynomia ever sending anything on
its own. This is a one-conversation, one-cart, human-reviewed workflow, not a campaign tool: there is no "send to all",
no bulk or broadcast, no automatic coupon, no scheduled or AI-written message.

## 1. Flow

```
Customer 360 → Abandoned carts → "Prepare recovery message"
   POST …/conversations/:id/commerce/stores/:store/carts/:cart/recovery { override_cooldown }
   Commerce::RecoveryMessages#prepare
     1. the installation offers this store's carts (switches, doc 30 §7)          else RECOVERY_DISABLED
     2. the conversation can receive a free-form message now (Conversation#can_reply?)
        — WhatsApp's 24-hour customer service window, the other channels' windows   else CANNOT_REPLY (messaging_window)
     3. at most 30 preparations per agent per hour                                 else RATE_LIMITED
     4. the cart read from the store again: still the contact's (doc 30 §3)         else NOT_FOUND
        still abandoned and younger than 30 days                                   else CART_NOT_ABANDONED
     5. its recovery link is safe (§3)                                             else INVALID_RECOVERY_URL
     6. no recovery message for this cart was sent within the cooldown (§4)        else RECOVERY_COOLDOWN
     7. a pending run "recovery_message" is recorded (prepared), audit commerce.recovery.prepared
   → { recovery_url, first_name, total, currency, store, items_count }
the browser writes the message in the agent's language and inserts it into the reply box (INSERT_INTO_RICH_EDITOR)
the agent reads it, edits it if needed, and presses Send — or doesn't
Commerce::RecoveryListener (message.created): an outgoing, non-private message of that conversation carrying the
   prepared link within 24 h → the run becomes sent (succeeded, message id), audit commerce.recovery.sent
```

Nothing is sent when preparing. If the agent never sends it, the run stays "prepared" and no cooldown starts.

## 2. The message

From two translatable templates (`COMMERCE.CARTS.TEMPLATE`), in the agent's UI language:

- with a name: "Hi {name}, you left {count} items in your cart at {store} ({total}). You can complete your order here: {url}"
- without: "Hello, you left {count} items in your cart at {store} ({total}). You can complete your order here: {url}"

`{name}` is the contact's first name as Chatwoot knows it, only when it is a name (letters), never a phone number or an
email. Totals are formatted in the cart's currency, never converted. There is no discount, coupon or incentive.

## 3. Recovery link safety (`Commerce::RecoveryUrl`)

The link is taken only from the store's own cart, never from an agent or a request, and is used only when it is:

- `https://` (not `http:`, `javascript:`, `data:`, `file:`), without credentials, on the default port, at most 2048
  characters, without whitespace;
- on the store's host or its provider's checkout hosts (`recovery_hosts`: Salla `salla.sa`/`*.salla.sa`, Zid
  `zid.store`/`*.zid.store`, Shopify the shop's myshopify.com host and its primary domain).

A cart whose link fails is shown but cannot be prepared ("The store’s recovery link isn’t safe to send"). The link is
never listed by the API or cached; runs keep only an HMAC digest of it (to recognize the sent message).

## 4. Prepared vs sent, cooldown and override

- **Prepared**: a pending run. The panel shows "Recovery message prepared …, not sent yet".
- **Sent**: the conversation's outgoing message carried the link (the listener). The panel shows "Recovery message sent
  …" and the admin queue shows it too. Whether the channel then delivered it is the channel's own status (WhatsApp
  ticks), unchanged.
- **Cooldown**: after a sent message, no new one for the same cart for `COMMERCE_RECOVERY_COOLDOWN_HOURS` (default 24):
  the panel shows when the next is possible, and agents get `RECOVERY_COOLDOWN`.
- **Override**: an account administrator can prepare one more message during the cooldown ("Prepare anyway"); recorded on
  the run (`override_cooldown`) and in the audit. An agent asking for it gets 401.

## 5. Messaging windows

`Conversation#can_reply?` (Chatwoot's `MessageWindowService`) decides. Outside a WhatsApp conversation's 24-hour window
nothing is prepared and the agent reads: "This conversation can’t receive a free-form message now (the customer last wrote
more than 24 hours ago). Nothing was prepared: reach the customer with an approved template instead." Lynomia never sends
a template automatically and never bypasses the window or the customer's consent.

## 6. Queue (administrators)

Settings → Commerce → **Abandoned carts**, shown when at least one store offers carts:

- the account's stores' recent carts (50 per store, 200 rows), read through the cache;
- filters: store, age (24 h / 7 d / 30 d), status (abandoned / recovered), linked contact or not;
- deterministic priority: carts of a linked contact first, then the most recently updated (no score, no AI);
- each row: total, items, store and provider, age, sent state, and the linked contact (opens the contact); unlinked carts
  say so;
- no contact details, no recovery links, no actions: a message is prepared from the contact's conversation.

## 7. Audit and metrics

Audit: `commerce.recovery.prepared` (store, cart, match, override), `commerce.recovery.sent` (store, cart, message id).
Metrics: `commerce.recovery.prepared`, `commerce.recovery.sent`, plus the cart metrics of doc 30 §8.
