# 02 — Provider security, and the Zid webhook registration defect

---

## 1. The Zid webhook registration defect

Found while answering A6.1's instruction to verify Zid's *official* webhook contract rather than assume it. The
code itself carried the open question:

```ruby
# VERIFY(zid-webhook-auth): … The request field that
# carries them could not be read from Zid's documentation from Lynomia's build environment, so it is set here only;
# a delivery without these credentials is refused whatever Zid did with them.
```

It can be read, and the field was wrong.

### 1.1 The old registration payload

```ruby
{ event: event, target_url: target_url, original_id: Commerce::Zid::Config.client_id,
  authentication: { type: 'basic', username: auth['webhook_username'], password: auth['webhook_password'] } }
```

### 1.2 The official Zid contract

From `docs.zid.sa/create-a-webhook`, read **2026-10-06**. `POST /managers/webhooks` takes:

| Field | Required | Meaning |
|---|---|---|
| `event` | yes | the event name |
| `target_url` | yes | where Zid delivers |
| `original_id` | yes | the subscribing app's own id |
| `conditions` | no | `status`, `delivery_option_id`, `payment_method` |
| **`username`** | no | Basic Auth username — **top level** |
| **`password`** | no | Basic Auth password — **top level** |

> "If `username` and `password` are provided when creating a webhook, Zid will include a `Basic Authentication`
> header when sending webhook requests."

Two further facts from the same source set:

- **Basic Auth is the only mechanism Zid offers.** There is no HMAC and no signing secret. An invented signature
  would not have been provider-compatible, which is why the brief's instruction not to invent one was correct.
- **It became mandatory for every webhook on 2026-09-30** (Zid Partner changelog 57336, "Webhook Security
  Changes") — six days before this phase.

### 1.3 Why the nested object was wrong

`authentication` is not a field Zid defines. A JSON API ignores keys it does not know, so the subscription is
created successfully **without credentials**. Nothing fails, and nothing says so.

### 1.4 Why Lynomia expected Basic Auth on delivery

`Webhooks::ZidController#create` authenticates every delivery before parsing anything:

```ruby
store_id = request.path_parameters[:store_id].to_s   # the path only — `params` would parse the body first
store = Commerce::Store.where.not(status: :disconnected).find_by(provider: 'zid', external_store_id: store_id)
authorized = authenticate_with_http_basic { |u, p| Commerce::Zid::Webhook.authorized?(store, u, p) }
return head :unauthorized unless authorized
```

This is correct and is not what was changed. A delivery with no credentials cannot be authorized.

### 1.5 The resulting failure chain

| Step | Outcome |
|---|---|
| 1 | Lynomia POSTs the subscription with the credentials in `authentication` |
| 2 | Zid ignores the unknown key and registers the webhook **with no credentials** |
| 3 | Zid returns an id, so registration **reports success** and the store is recorded as registered |
| 4 | Zid delivers `order.create` / `order.status.update` / `order.payment_status.update` with **no `Authorization` header** |
| 5 | The controller answers **401** and never parses the body |
| 6 | Every order event is lost. Realtime cache invalidation never runs, so a conversation shows stale orders until the 120-second cache expires and is re-fetched by polling |

Nothing in Lynomia reports an error at any step. The only visible trace is the
`commerce.webhook.rejected` metric event, which looks identical to a misconfigured store.

### 1.6 Zid's documented failure implications, now verified

From `docs.zid.sa/webhook-health-tracking`, read 2026-10-06 — this turns a silent fault into an escalating one:

| | |
|---|---|
| Health model | a circuit breaker over a sliding **one-hour** window of failed deliveries (non-2xx, timeouts) |
| **DEGRADED** | **≥10** failures in the hour |
| **BROKEN** | **≥30** failures in the hour — **Zid stops dispatching new events entirely**, and emails the partner |
| Retries | each event is attempted up to **3** times, backing off 1 min, 5 min, 15 min |
| Not counted | HTTP **429** is not treated as a failure |
| Recovery | a "Recover Broken Webhooks" endpoint takes the webhook UUID and a new target URL |

So a busy store would have reached BROKEN within an hour, after which Zid sends nothing at all — and a later fix
to the registration would not by itself resume delivery.

### 1.7 The new registration payload

```ruby
{ event: event, target_url: target_url, original_id: Commerce::Zid::Config.client_id,
  username: auth['webhook_username'], password: auth['webhook_password'] }
```

**No compatibility fallback was added.** Sending both shapes was considered and rejected: an undocumented key is
what caused this, and sending one again would leave the next reader unable to tell which field Zid honours.

### 1.8 A second defect, in the same method

Verifying "the registration response is checked truthfully" found that it was not:

```ruby
# before
ids = EVENTS.filter_map { |event| client.post_json(PATH, subscription(event, auth)).then { |body| body['id'].to_s if body.is_a?(Hash) } }
```

`filter_map` **drops** any response without an id. A store where two of the three POSTs failed was recorded as
registered, with one id, and `register` returned normally — the same shape of untruthful success as the
`setup_webhooks` defect in `docs/real-whatsapp-uat/09-fix.md`. Now:

```ruby
ids = EVENTS.map { |event| subscribe(client, event, auth) }

def subscribe(client, event, auth)
  body = client.post_json(PATH, subscription(event, auth))
  id = body['id'].to_s.presence if body.is_a?(Hash)
  raise Commerce::Error.new('INVALID_RESPONSE', reason: 'zid_webhook_subscribe') if id.nil?

  id
end
```

The store's metadata is written only after every event is subscribed, so a partial registration leaves no record
claiming otherwise.

### 1.9 Security characteristics of the registration

| Property | How |
|---|---|
| Credentials are per store and random | `SecureRandom.hex(16)` username, `SecureRandom.urlsafe_base64(48)` password, minted fresh on **every** registration |
| Rotation-compatible | registering deletes every subscription sharing the app's `original_id` and re-subscribes with a new pair, so re-authorizing rotates credentials and never duplicates subscriptions |
| Saved before use | the pair is persisted, encrypted, **before** the POSTs, so a delivery can never arrive for a credential Lynomia does not yet hold |
| Serialized | the whole registration runs inside `Commerce::StoreLock.with('zid_webhooks', external_store_id)` |

### 1.10 Tests proving the fix

| Test | Proves |
|---|---|
| `spec/services/commerce/zid/webhooks_spec.rb` — registration asserts the posted body | `username`/`password` are sent at the **top level**, and the generated pair meets its length floors (≥32, ≥64) |
| same file — re-registration | the password changes, i.e. rotation really rotates |
| same file — raw body assertion | the password never appears in the request Lynomia logs or echoes |
| same file — **new** `raises when Zid does not return an id for a subscription, and records no metadata` | a partial registration raises `INVALID_RESPONSE / zid_webhook_subscribe` and writes no `zid_webhooks` metadata |

158 examples across `spec/services/commerce/zid/` and `spec/controllers/webhooks/`, 0 failures.

## 2. The five properties A6.1 asked to verify

| # | Property | Result |
|---|---|---|
| 1 | **No webhook credentials in logs** | **PASS.** Outside specs, `webhook_username`/`webhook_password` appear in exactly three places — minting them, reading them to compare, and sending them to Zid. No log or exception path touches them. `Commerce::Error` carries only a `code` and a safe `reason`, by design, so a provider response can never surface a credential |
| 2 | **Secrets stay server-side** | **PASS.** `Commerce::Store` has `encrypts :credentials`; `serializable_hash` strips them; the API view is an explicit jbuilder allow-list; the model refuses to save at all without encryption keys configured |
| 3 | **Constant-time comparison** | **PASS**, and carefully: both username and password go through `ActiveSupport::SecurityUtils.secure_compare`, combined with `&` rather than `&&`, so the comparison does not short-circuit and leak which half failed |
| 4 | **Duplicate events idempotent** | **PASS at the delivery layer.** `Commerce::WebhookQueue.enqueue` takes `"#{store.id}::#{SHA256(raw_body)}"` under `SET NX EX 1.day`; a repeat within a day is counted as `commerce.webhook.duplicate` and not queued. On an enqueue failure the key is deleted, so a failed enqueue is retryable rather than permanently swallowed. **Caveat for Stage B:** this is Redis-only with a 24-hour horizon, and Zid documents no delivery id, so durable cart state needs its own idempotency — see `05` §6 |
| 5 | **Auth failure observable** | **PARTIAL.** A 401 emits `commerce.webhook.rejected` with the provider and store id, which is the right signal and carries no secret. What it cannot distinguish is *why*: a wrong credential, a store that is disconnected, and a webhook registered without credentials all look the same. `03` proposes the store diagnostic that separates them |

## 3. The other three providers' webhook authentication

| Provider | Mechanism | Provenance |
|---|---|---|
| WooCommerce | a shared secret Lynomia generates and stores in the store's encrypted credentials, registered with the hook | real-capture verified |
| Shopify | HMAC signature; `oauth.rb:7` sets `HMAC_TOLERANCE = 90` seconds | hand-authored fixture |
| Salla | **none — Lynomia registers no Salla webhooks at all.** `registers_webhooks?` is the base `false` and `release` is the base no-op | code-verified |
| Zid | HTTP Basic Auth, per store, as above | provider-contract verified |

## 4. Deliberately not changed

- **No HMAC was invented for Zid.** Zid offers none; adding one would have been unverifiable against the provider.
- **The Shopify HMAC tolerance was left at 90 seconds.** It is within normal practice and nothing in evidence
  suggests otherwise.
- **`Commerce::WebhookQueue`'s 24-hour Redis dedup was left alone.** It is correct for its job — collapsing
  provider redeliveries. Stage B must not lean on it for lifecycle idempotency, which is a Stage B design
  constraint, not a defect here.
