# Who decides what, and how the two systems reconcile

Companion to [ADR-001](ADR-001-partner-scoped-consent.md). Its subject is the one failure this
design exists to prevent: **Store Syria and Lynomia becoming competing authorities over
consent state**, each confident and each wrong in a different way.

---

## 1. The split

There is no shared authority over "the consent state". There are two different questions, and
each has exactly one owner.

| Question | Authority | Why it cannot be the other one |
|---|---|---|
| **What did this customer tell this store?** | **Store Syria**, for its own installations | The capture happened on its checkout, under its notice, in its session. Lynomia was not there and can only be told. |
| **May this message be sent, right now?** | **Lynomia**, always | Lynomia owns the send path. A decision made anywhere else is a recommendation that the sender is free to be unable to honour. |

So Store Syria is the **primary merchant-facing interface** and the **origin** of partner
consent, and Lynomia is the **enforcement point**. Those are compatible because they are not
the same claim. Store Syria never decides eligibility; Lynomia never invents a grant.

**Lynomia is also an origin, for its own channels.** A shopper replying STOP on WhatsApp
creates a native withdrawal, and Store Syria must be told. That makes the flow bidirectional
without making either side authoritative over the other's records.

## 2. What each side may write

| Record | Written by | Never written by |
|---|---|---|
| `partner_consents` / `partner_consent_events` | Lynomia, from events a partner submits over the authenticated write API | A merchant UI directly; a partner writing rows itself |
| `commerce_messaging_consents` (native) | Lynomia — its own consent surface and the opt-out keyword listener | Any partner, ever |
| Store Syria's own consent records | Store Syria, from its checkout and merchant UI, and from Lynomia's outbound feed | Lynomia writing into Store Syria's tables |

**No partner can write a native record, and no native path writes a partner record.** The two
stores are read together at the send boundary and never merged, which is what keeps "where
did this come from" answerable afterwards.

## 3. Reconciliation rules

These are the rules an engineer needs when two reports of the same thing disagree.

**R1 — Order is the event's id, not any timestamp.** `partner_consent_events.id` is assigned
by Postgres at insert. It is server-controlled, monotonic in assignment order and unforgeable
by a caller. `captured_at` is the partner's claim about when the customer acted and is kept as
evidence; it orders nothing, because a skewed or dishonest clock would otherwise decide
whether somebody who opted out gets marketed to.

**R2 — Identity is `(commerce_store_id, decision_ref)`, and it is a unique index.** A
redelivery is refused by the database rather than applied twice. At-least-once delivery, retry
storms and replayed backlogs are therefore no-ops by construction. Scoped to the installation
because `decision_ref` is the partner's identifier and two partners may mint the same one.

**R3 — A withdrawal is not overturned by a grant.** A grant arriving while the state is
withdrawn is refused whatever its id or timestamps. This is what makes a delayed grant
harmless rather than merely unlikely to win.

**R4 — Except by an explicit re-consent.** A customer who changes their mind says so through a
`re_consent` event, which is separately verified and recorded as its own event. It is the one
grant that may follow a withdrawal and is never the default.

**R5 — A suppression is not overturned by anybody but an operator.** It means the provider
reported the number cannot receive. No customer agreement makes a dead number alive, so even a
re-consent is refused; it is cleared through the native `clear_suppression` path once the
cause is fixed.

**R6 — Every event is kept, applied or not.** `outcome` is `applied`, `duplicate`,
`superseded` or `refused_withdrawal_dominant`. Without the ignored ones, "the partner never
sent it" and "the partner sent it and we correctly ignored it" are indistinguishable, which is
precisely the question a reconciliation run exists to answer.

**R7 — Negatives union; positives do not.** At the send boundary either store may refuse and
neither may overturn the other. A positive counts only within its own scope: a partner grant
needs the installation, the purpose and the channel all to match.

**R8 — A negative reaches as far as its own scope and no further.** A native decision is
account-wide. A partner decision is installation, purpose and channel scoped. A marketing
withdrawal at one store does not silence that store's transactional messages, and says nothing
about another store.

## 4. Divergence, and how it is resolved

Delivery is asynchronous, so the two sides will differ, briefly and routinely. That is
expected and is not a conflict.

| Situation | Resolution |
|---|---|
| Store Syria has a grant Lynomia has not received | Lynomia refuses the send. **Fail closed** — the message is delayed, not wrongly sent. |
| Lynomia has a withdrawal Store Syria has not received | Lynomia refuses the send. Store Syria's display is stale; the feed corrects it. **No message goes out.** |
| Both have decisions that disagree | Whichever is a negative wins (R7). If both are negatives, both apply. |
| An event arrives out of order | R1 and R3 decide; the loser is kept with `outcome: superseded` or `refused_withdrawal_dominant`. |
| An event is lost entirely | Reconciliation: Store Syria replays its decisions with their original `decision_ref`, and R2 makes the already-received ones no-ops. |

**Every divergence resolves toward not sending.** That is the only asymmetry worth having: a
message delayed by a sync lag is recoverable, and a marketing message sent to somebody who
opted out is not.

## 5. What is simulated and what is not

**Nothing in this document has been verified against a live peer.** Both sides are exercised
against scriptable fakes shaped to match the other's contract as this work understands it,
which is agreement between two expressions of one reading rather than evidence the reading is
right. The feed, the write API and the reconciliation path in particular will behave correctly
in tests and are unproven in fact.

Blocker **A1** in `PRODUCTION-READINESS-BLOCKERS.md` stays open until a real non-production
integration run has happened.
