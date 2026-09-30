# Lynomia Commerce: customer matching

**Principle: showing the wrong customer's orders to an agent is a data leak.**
- Matching is **exact and identifier-based**, per store.
- A name alone never links anything.
- Anything not proven by the channel is only a **suggestion** that an agent must confirm.

## 1. Where a contact's identifiers come from (and how much we trust them)

Chatwoot already records the channel identity of a contact in `contact_inboxes.source_id` (unique per inbox, `db/schema.rb:825-835`). Web-widget identity verification sets `contact_inboxes.hmac_verified`.

| Channel | Identifier | Trust | Why |
|---|---|---|---|
| WhatsApp (Cloud or 360dialog) | phone from `contact_inboxes.source_id` (`wa_id`), normalized to E.164 | **verified** | WhatsApp delivers the sender's own number |
| Twilio SMS / SMS | phone from `source_id` / sender number | **verified** (carrier-asserted) | The inbound sender number |
| Email inbox | `From` address (`source_id`) | **channel-asserted** | Can be spoofed; Chatwoot does not check DKIM/DMARC for contact identity. Auto-link is allowed only when exactly one store customer has that email, and it is shown as "matched by email". |
| Web widget with HMAC identity (`hmac_verified = true`) | `identifier`, `email`, `phone_number` set through `setUser` with `identifier_hash` | **verified** | Signed by the merchant's own site |
| Web widget without HMAC | pre-chat or visitor-entered email/phone | **asserted** | Anyone can type any email |
| Instagram, Facebook, TikTok, Telegram, Line | platform user id only | none for commerce | No phone or email from the channel |
| Contact fields edited by an agent | `contacts.phone_number` / `email` | **asserted** | Human-entered |

- **"Verified" in the hierarchy below** means the value comes from the channel identity of a `contact_inbox` of this contact: its WhatsApp or SMS `source_id`, or an HMAC-verified widget identity.
- **Email-inbox addresses** are auto-linkable only under the uniqueness rule above.
- **Asserted values** only ever produce suggestions.

## 2. Matching hierarchy (per store, first hit wins)

| Step | Rule | Auto-link? |
|---|---|---|
| 1 | **Stored link**: `commerce_customer_links` row for (store, contact) with `state: linked` | yes (reuse). If the provider later returns NotFound, the link is removed and matching restarts. |
| 2 | **Verified phone**: every verified E.164 phone of the contact → provider exact search → exactly **one** customer with an identical normalized phone | yes, `match_method: verified_phone` |
| 3 | **Verified email**: lower-cased, stripped, exact → exactly **one** customer | yes, `verified_email` (email-inbox addresses under the §1 rule) |
| 4 | **Provider customer ID**: a store customer id delivered on a verified path (HMAC-verified widget custom attribute such as `commerce_customer_id`, or a store-built integration) | yes, `provider_id`, only through the verified path. A contact custom attribute an agent typed is only a suggestion. |
| 5 | **Manual link**: the agent searches the store by phone, email or order number and picks a result | yes, `manual`, audited, requires permission (`04` §5) |
| — | **Asserted identifiers** (agent-edited phone, unverified widget email) | **no**: shown as "possible match — link?" |
| — | **Name, fuzzy or partial phone** | **never** |

**Refusals:**
- **Ambiguity:** if steps 2–3 return more than one customer in a store, nothing is auto-linked. The panel shows the candidates (name, masked phone or email, order count, last order date) for the agent to pick, which is step 5.
- **Rejected:** an agent can mark a suggestion "not this customer" (`state: rejected`). That customer is never auto-suggested again for this contact.

## 3. Normalization

**Phone**
- Use the existing `telephone_number` gem (`Gemfile:22`). Parse the store's value with the **store country as default** (Salla/Zid → `SA`; WooCommerce → the store's base country from `/wc/v3/settings/general`, else `SA`), and compare E.164 strings.
- Salla: E.164 = `mobile_code` + `mobile` (`+966` + `5XXXXXXXX`).
- Local `05XXXXXXXX` and `9665XXXXXXXX` both normalize to `+9665XXXXXXXX`.
- Values that don't parse are ignored: no match, no error.
- The provider search term uses the provider's preferred format:
  - Salla `keyword=9665…` (confirm that a local form also matches: **VERIFY**);
  - Zid `customer_phone` (format **VERIFY**);
  - Shopify `customerByIdentifier(phoneNumber: "+9665…")`;
  - WooCommerce order `search=5XXXXXXXX` (last 9 digits; results then re-checked for exact E.164 equality).

**Email:** `strip.downcase`. No plus-address stripping and no Gmail dot-folding; those are different identities.

**Always re-check locally:** every provider search result is compared again for exact normalized equality before it counts as a match, because Salla `keyword` and WooCommerce `search` are broad text searches.

## 4. Special cases

- **Guest orders** (WooCommerce `customer_id: 0`; guest checkouts elsewhere): the link row has `external_customer_id: nil` and a `match_key_digest`. Orders are fetched by exact phone or email search.
- **Marketplace orders with masked PII** (Zid `is_marketplace_order`): these can't be matched by phone or email. They are shown only when reached through a linked customer id.
- **Multiple stores:** matching runs independently per store, and the panel groups results by store. One contact may be linked in store A and unmatched in store B.
- **Contact merge:** on `CONTACT_MERGED` (`app/actions/contact_merge_action.rb:54-66`), move links to the surviving contact. If both contacts had different links in the same store, drop the auto ones and keep manual links, which need agent resolution.
- **Identifier changes:** links created from verified identifiers stay valid until the provider says NotFound. Editing `contacts.phone_number` does not remove a verified link.

## 5. Where it runs and how it's cached

- `Commerce::CustomerMatcher.new(store:, contact:).perform` returns one of:
  - `{ state: :linked, customer: }`
  - `{ state: :candidates, customers: [...] }`
  - `{ state: :none }`
- A successful auto-match writes the link row once, so provider searches don't repeat on every sidebar open.
- Search results for unmatched contacts are negative-cached in Redis for 10 min (`commerce:v1:s:{store}:nomatch:{digest}`), to protect rate limits (Zid 60/min, Salla customers 500/10 min).
- **Only digests** (SHA-256 of the normalized phone or email) are persisted in link rows. Customer names, addresses and similar data are not stored locally.

## 6. Examples

1. **WhatsApp +966501234567 → Salla store:**
   `keyword=966501234567` returns 2 customers. One has `mobile_code+mobile = +966501234567`, the other only mentions it in a note. The local exact check keeps one, so it auto-links (`verified_phone`).
2. **Instagram DM, no phone:** no identifiers, so the panel shows "Link a customer". The agent searches the order number `#12891`, picks the customer, and a `manual` link is created and audited.
3. **Email inbox `ahmed@x.com` → WooCommerce:** `customers?email=` returns nothing (guest buyer). Order `search=ahmed@x.com` finds guest orders with an exact `billing.email`, so a guest link is created.
4. **Web widget where the visitor typed a phone:** asserted, so the panel shows "Possible match: Ahmed M. (•••4567), link?". Nothing is shown until an agent confirms.
