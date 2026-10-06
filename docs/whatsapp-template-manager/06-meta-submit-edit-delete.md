# 06 — Submit, edit, delete, duplicate

The four lifecycle actions, the rules that decide which are offered, and what a person sees when Meta refuses. Read
with `01-meta-api-contract.md §§6–7`, which is where every rule below comes from.

---

## 0. One decision, enforced twice

`Whatsapp::Templates::Actions` is the only place that decides what may be done to a template. The manager renders the
list it returns; **every lifecycle endpoint calls it again before acting.** Hiding a control is never the only thing
stopping an action, which is the structural requirement rather than a cosmetic one.

What it encodes, each straight from Meta's current rules:

| Action | Allowed when |
|---|---|
| Submit | the template is a local draft, and no submit is in flight |
| Edit | a draft always; a template at Meta only while `APPROVED`, `REJECTED` or `PAUSED` |
| Edit category | a draft always; a template at Meta only while `REJECTED` or `PAUSED` — never while approved |
| Delete | a draft always; a template at Meta unless it is `DISABLED` |
| Duplicate | always — it only ever creates a new local draft, so nothing Meta says can forbid it |

A CSAT template is read-only here but for duplicate: it keeps its own versioned lifecycle
(`03-sync-and-lifecycle.md §5.5`), and the manager points at the inbox's CSAT settings instead. The P0 safeguards
around destructive CSAT operations are untouched by this phase.

## 1. Submit

A draft is handed to Meta by `Whatsapp::Templates::Submission`, and a submit is confirmed first: the dialog states
that WhatsApp will review it, that the name and language cannot change afterwards, and that review takes as long as
it takes. Dismissing it submits nothing.

**Double-clicking Submit cannot create two templates at Meta.** The claim is taken under a row lock and committed
*before* the HTTP call:

```ruby
template.with_lock do
  raise Error, 'ALREADY_AT_META'  if template.meta_status.present?
  raise Error, 'SUBMIT_IN_FLIGHT' if submit_in_flight?
  template.update!(submitted_at: Time.current, submission_error: nil)
end
```

so the second request finds `submitted_at` already set and refuses, instead of racing the first to Graph. A request
spec asserts exactly one Graph call for two concurrent submits.

**The category is taken from Meta's response, never from the request.** Meta assigns the final category and may not
give the one asked for; storing the requested one would make the manager lie about a template a campaign then picks.

**A refusal never destroys the draft.** If Graph refuses, the claim is released and the reason stored on the row:

```ruby
template.update!(submitted_at: nil,
                 submission_error: [error.code, error.reason].compact.join(': ').first(1000))
```

The draft is the only copy of the user's work. Reloading the page still explains why the submit failed, rather than
leaving a draft that looks half-submitted for no reason.

## 2. Edit

`Whatsapp::Templates::Revision`. A draft is a local write with no Graph call at all. A template Meta holds is edited
only in the statuses above, and its category only in the narrower pair — and the controls for the others are not
offered, because `Actions` has already said no.

Two consequences of Meta's contract that the code follows exactly:

- **Meta replaces all components with the ones sent**, so the complete set goes every time. There is no partial edit,
  and building one would silently drop whatever was left out.
- **Meta's response is only `{"success": true}`**, and the documented consequence is that the template re-enters
  review. The status is therefore set to `PENDING` rather than left claiming an approval that may no longer hold.
  Whatever Meta decides arrives by webhook or on the next sync, which stay authoritative.

The name and the language are never in the edit payload: Meta does not allow either to be edited.

## 3. Delete

`Whatsapp::Templates::Removal`. A draft is deleted here and nowhere else, with no Graph call — Meta has nothing to
delete, and the confirmation says so in those words rather than warning about a consequence that cannot happen.

A template Meta holds is deleted **by id together with its name** (`hsm_id` + `name`), the documented single-template
shape. The `name`-only form deletes *every language variant* of that name; it is right for CSAT, whose templates are
one per name, and wrong as a default anywhere else. The confirmation states the real consequence: **WhatsApp does not
allow the name to be used again for 30 days.**

The row goes once Meta confirms. If Meta still holds the template in some state — it moves one that has been sent but
not yet delivered to `PENDING_DELETION` for thirty days — the next sync brings the row back carrying Meta's own
status. That is the truthful outcome, rather than a tombstone this product invented.

## 4. Duplicate

`Whatsapp::Templates::Duplication` creates a **new local draft** and carries nothing of Meta's: no template id, no
status, no submission history, no timestamps. The partial unique index on `(account_id, meta_template_id)` makes
cloning an id impossible to persist even if this code tried to.

The copy gets a genuinely new name — `<name>_copy`, then `_copy_2`, up to a random suffix — because Meta refuses a
duplicate `(name, language)` outright and blocks a deleted approved template's name for thirty days. "Duplicate" can
therefore never mean "reuse the name". A copy of a template Meta recategorised into something a user may not author
starts as `UTILITY`, the conservative choice for a draft about to be edited anyway.

This is also the "new version" path: duplicate, edit, submit. There is no second versioning scheme.


## 5. Errors: what a person sees, and what the log keeps

One error type, `Whatsapp::Templates::Error`, carrying a code, an optional safe reason and optional per-field details.
The UI translates the code; the server never builds an English sentence.

| Code | When | What the user is told |
|---|---|---|
| `INVALID_TEMPLATE` | the published WhatsApp rules are not met | the per-field problems, with "passing them is not approval" |
| `NAME_TAKEN` | Meta's code 100 / subcode 2388024 | this account already has that name in that language |
| `NOT_EDITABLE`, `CATEGORY_NOT_EDITABLE`, `NOT_DELETABLE`, `NOT_SUBMITTABLE` | Meta's lifecycle rules | what Meta allows, in words |
| `ALREADY_AT_META`, `SUBMIT_IN_FLIGHT` | a second submit | that it is already there, or already going |
| `CSAT_MANAGED_ELSEWHERE` | a survey template | where it is managed instead |
| `NO_WHATSAPP_INBOX` | the WABA has no connected channel left | that the inbox is gone |
| `AUTH_INVALID` | Graph code 190 | reconnect the inbox |
| `RATE_LIMITED` | HTTP 429 | try again shortly |
| `META_UNAVAILABLE` | HTTP 5xx | try again shortly |
| `META_REJECTED_REQUEST` | anything else | Meta's own `error_user_msg` when it wrote one, and nothing invented when it did not |

**What never reaches a message:** an access token, a request header, a raw Graph body. The full response and its
`fbtrace_id` go to `Rails.logger` instead, which is also where a developer looks when a user reports a code.

A failed submit is also *kept*: the code and reason are stored on the draft, so reloading the page still explains why,
instead of leaving a draft that looks half-submitted for no reason.

## 6. Retries, and the absence of a polling loop

- **No new job, scheduler or queue.** Status moves on the sync that already runs (at most every three hours per
  channel, 25 channels per five-minute tick) and on the webhook.
- **No per-template polling and no status-watching loop.** Nothing waits on Meta.
- **Transport retries** stay with Sidekiq and `ApplicationJob`, as for every other job in this product.
- A submit, edit or delete is a user action in a request: it either succeeds or returns a code the user can act on.
  Nothing retries behind their back, because a silent retry of a template create is how duplicates happen.
