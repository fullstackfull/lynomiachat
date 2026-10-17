# The Odoo adapter

Every rule here came out of Odoo's own source or its own documentation, not from a general idea of how
accounting APIs behave. Sources are named so a future reader can re-check them against a newer Odoo.

---

## 1. Transport

**JSON only.** `xmlrpc` is not in this bundle and `require 'xmlrpc/client'` fails, so XML-RPC is not an option.
That is a constraint rather than a preference, and it happens to point at the better design: Odoo serves the
same `common` and `object` services over JSON.

| Odoo major | Transport | Endpoint | Credential | Arguments |
|---|---|---|---|---|
| 19 and above | `json2` | `POST /json/2/<model>/<method>` | `Authorization: Bearer <api_key>` header | named only |
| 16, 17, 18 | `jsonrpc` | `POST /jsonrpc` | inside the request body, after `common.authenticate` | named (via `execute_kw` kwargs) |
| 15 and below | refused | — | — | — |

Odoo's own 19.0 documentation schedules `/xmlrpc`, `/xmlrpc/2` and `/jsonrpc` for removal in **Odoo 22 (autumn
2028)** and **Odoo Online 21.1 (winter 2027)** — Online loses them a year earlier. JSON-2 is the replacement,
which is why 19+ prefers it.

The JSON-2 endpoints are served by the `rpc` addon, which is `auto_install: True`, so they are present on an
ordinary Odoo 19 install with nothing for the customer to enable.

**Version detection happens before any credential is sent.** `common.version` on `/jsonrpc` needs no
authentication and no database, and returns `server_version`, `server_version_info`, `server_serie` and
`protocol_version`. Guessing the dialect wrong would not merely fail — it would send the customer's accounting
credential in the wrong shape to the wrong endpoint.

**`server_version_info[0]` is not always an integer.** Odoo's `release.py` says the major version "can become
an arbitrary string (saas~xx)" during release, and a live call to www.odoo.com answers:

```
server_version_info => ["saas~19", 3, 0, "final", 0, "e"]      server_version => "saas~19.3+e"
```

An integer check would refuse every real Odoo Online tenant. The major is read as the first run of digits, so
both `19` and `"saas~19"` answer 19. There is a spec for exactly this.

## 2. Authentication

**Odoo 19+ (JSON-2).** The API key identifies the user: one step, no uid, and the key travels in a header
rather than inside the body, so it cannot reach a body-logging proxy.

**Odoo 16–18 (JSON-RPC).** Two steps: `common.authenticate(db, login, api_key, {})` returns a numeric uid, and
every later `object.execute_kw` repeats the database, the uid and the key. API keys work in place of a password
from Odoo 14 onwards. Odoo answers a bad credential with `false` rather than an error object, so the falsy
answer **is** the failure and must not become a uid of `false` in the next call's arguments.

**Operational facts for the runbook:** API keys become mandatory for RPC when 2FA is enabled on the user
(`auth_totp` overrides `_rpc_api_keys_only?`); manually generated keys last at most three months and the value
is shown only once; on Odoo Online, external API access is restricted to Custom plans and a user has no local
password until one is set.

**What a connection test can and cannot prove.** It proves the key authenticates and the user can read
`account.move`. It proves nothing about the journal, the company, the user's posting rights, or whether this
server's chart of accounts accepts the line shape we send. Those are separate questions — see
[04-diagnostics.md](04-diagnostics.md).

## 3. The invoice lifecycle

Each step is a **separate RPC call and therefore a separate SQL transaction**. Odoo documents that calls to the
JSON-2 endpoint each run in their own transaction and that chaining them inside one is not possible. This
integration never claims otherwise.

```
1. res.partner.search_read(domain: scope + [ref = stamp])      -> [] | [row] | [row, row]
2. res.partner.create(vals_list: [{name, ref, email, company_id}])   -> partner id
3. account.move.search_read(domain: scope + [move_type, ref])   -> recovery from a lost answer
4. account.move.create(vals_list: [{move_type: 'out_invoice', partner_id, journal_id,
                                    currency_id, invoice_date, ref, invoice_line_ids}])  -> move id
5. account.move.read(ids: [id], fields: [...])                  -> COMPARE TOTALS HERE
6. account.move.action_post(ids: [id])                          -> false (always re-read after)
7. account.move.read(ids: [id], fields: [...])                  -> the assigned name, and the real date
8. account.payment.register.create(vals_list: [{payment_date, amount, journal_id, communication}],
                                   context: {active_model: 'account.move', active_ids: [id]})  -> wizard id
9. account.payment.register.action_create_payments(ids: [wizard]) -> act_window dict; res_id is the payment
```

### The rules behind those calls

- **`move_type` must be set.** `account.move.move_type` defaults to `'entry'`, so an invoice created without it
  is not an invoice — it is a bare journal entry, and nobody notices until an accountant does.
- **A posted move cannot be created.** `account.move.create` raises `UserError` on any vals carrying
  `state: 'posted'`. Draft then post is the only sequence the server allows.
- **`name` is never pre-assigned.** The journal sequence assigns the legal number when the move leaves draft,
  and `_compute_name` silently **resets** a name that does not match the move's date. A draft legitimately has
  no number.
- **`account_id` is never set on a product line.** `_compute_display_type` turns a line whose account is
  receivable or payable into a `payment_term` line, which silently changes the invoice's totals.
- **x2many values are literal triples.** Odoo's own source: *"Via RPC, it is impossible nor to use the
  functions nor the command constant names."* So lines go as `[[0, 0, {...}]]`, never `Command.create`.
- **Everything is read back after posting.** `action_post` returns `false`, assigns the sequence number, and
  **moves the move's date** if it falls in a locked period.
- **Posting needs `account.group_account_invoice`**, or `_post` raises `AccessError`.
- **`payment_state` is never written.** Stored, computed, no inverse.
- **The payment wizard reads its target from the context**, not from arguments: `active_model` and `active_ids`.
  `default_get` raises if `active_model` is anything but `account.move` or `account.move.line`.
- **`dont_redirect_to_payments` is not passed.** With it, `action_create_payments` answers `true` and the
  payment's id is lost — and a document we cannot name is one we cannot reconcile later.

### Credit notes

| Case | Operation |
|---|---|
| Full refund | `account.move.reversal.create` (context `active_ids`) → `reverse_moves` → read `new_move_ids` off the wizard |
| Partial refund | `account.move.create` with `move_type: 'out_refund'` and `reversed_entry_id`, then `action_post` |

**Why two.** Odoo 17 removed `account.move.reversal.refund_method` (which in 15 and 16 offered 'Partial
Refund'). `reverse_moves` now reverses the whole move and the wizard has no amount field anywhere in it. A
future-dated reversal is created with `auto_post: 'at_date'` and is **not** posted when `reverse_moves`
returns, so its state is read rather than assumed.

## 4. Idempotency

| Layer | What it gives |
|---|---|
| Odoo | **nothing.** No idempotency parameter on `create()`, no header on either endpoint. `account.move.ref` has no uniqueness for customer invoices. |
| Lynomia | `odoo_document_mappings.idempotency_key` with a unique index, and `odoo_sync_events.dedup_key` with another |
| Recovery | search Odoo for our own stamp inside our own scope, and adopt what is there |

**The failure window, named.** A `create` succeeds on the server and the response is lost in transit. The
attempt row says `unknown_outcome`. The next attempt does **not** write: it searches `account.move` for our
stamp in our company and journal. One match is our own earlier work and is adopted. Two matches is a
`CONFLICT` for a person — our stamp on two records means somebody duplicated one in Odoo, and picking either
would split or merge a customer's ledger.

For payments the evidence is different, because `account.payment.register` does not stamp `ref` the way a move
does: the **invoice's own** `payment_state` is consulted, because Odoo computes it from reconciliation rows. An
invoice that already reads paid, in payment or partial has something reconciled against it, and rather than
guess whether that something is ours the document goes to a person. One confirmation is cheaper than one double
payment in a real ledger.

## 5. Error classification

| Odoo / HTTP | Our code | Classification | Client action |
|---|---|---|---|
| `AccessDenied`, 401, falsy `authenticate` | `AUTH_INVALID` | permanent | operator fixes the key |
| `AccessError`, 403 | `PERMISSION_DENIED` | permanent | operator grants the right |
| `UserError`, `ValidationError`, `RedirectWarning` | `BUSINESS_RULE` | permanent | fix the payload or the config |
| 422 | `INVALID_REQUEST` | permanent | our payload is wrong |
| 404 on the RPC route | `ENDPOINT_MISSING` | permanent | re-detect the version |
| 429 | `RATE_LIMITED` | transient | back off and repeat |
| 5xx, `SerializationFailure`, `TransactionRollbackError` | `SERVER_ERROR` | transient | back off and repeat |
| DNS, refused, connect timeout, SSRF refusal | `UNREACHABLE` | **not_sent** | safe to repeat |
| read timeout, unparseable body | `TIMEOUT` / `INVALID_RESPONSE` | **unknown_outcome** | search for the stamp |
| `MissingError` | `RECORD_MISSING` | needs_review | a person looks |
| scope mismatch, stamp on two records | `CONFLICT` | needs_review | a person decides |

No provider prose reaches a message or a JSON response. Odoo's own one-line explanation — the part that tells
an operator *which* journal setting is wrong — travels in `detail` through `Odoo::SyncAttempt.scrub`, which
reuses `Operations::SignalRecorder::CREDENTIAL_PATTERNS`. The Python traceback (`debug`) is never carried at all.

## 6. Version branch matrix

| Odoo | Transport | `payment_state` has `blocked` | `account.payment` has its own `state` | Partial refund |
|---|---|---|---|---|
| 19 | `json2` | yes | yes | create `out_refund` |
| 18 | `jsonrpc` | yes | yes | create `out_refund` |
| 17 | `jsonrpc` | no | no (delegates to `account.move`) | create `out_refund` |
| 16 | `jsonrpc` | no | no | create `out_refund` |

The adapter does not branch on these from a version number where it can ask instead: the capability probe reads
`payment_state`'s selection with `fields_get`, so the branch comes from the server rather than from an
assumption about it.

## 7. Network safety

`Odoo::Http` applies, to the same class of risk, every decision `Commerce::HttpClient` already made for store
APIs — an operator-supplied hostname the server will then connect to:

- every request through `SsrfFilter`, which resolves the host, refuses private, loopback, link-local and
  cloud-metadata addresses, and **pins the connection to the address it checked**, so DNS cannot be rebound
  between the check and the connect;
- redirects never followed — a 3xx is an error, so nothing can bounce an authenticated accounting request to
  another host;
- bounded: connect 5 s, read 30 s, whole body 20 s and 5 MB;
- TLS verification never disabled, and a non-https base URL refused at validation time and again at request time;
- nothing retried at the socket — whether an accounting write may be repeated is not a question a socket can
  answer;
- the one log line is the method, the path, the status and the elapsed time. Not the header, not the key, not
  the body, not the response.
