# 02 — Approved template → new contact: BLOCKED

## 1. Status

**SCENARIO 3: BLOCKED — NO APPROVED REAL TEMPLATE EXISTS YET.**

A read-only live Meta query against WABA `4584909965122758` (inbox #77) returned exactly one template:

```
name     = order_delivered
language = en_US
status   = PENDING
category = UTILITY
id       = 1898998951089221
```

That is a **real Meta template**, correctly created through the supported flow. It is simply not approved yet.

## 2. Why PENDING genuinely blocks the send, rather than being a detection problem

The send-time gate is the **channel's synced snapshot**, `Channel::Whatsapp#message_templates`, searched by
`Whatsapp::TemplateProcessorService#find_template` on name + case-insensitive language + `status == 'approved'`.
`Flows::Template.problem` wraps that into one error code. A `PENDING` template is absent from the approved set, so
every send path refuses it with `template_not_approved` — including the new Automation action (`03`), which is
pinned by a regression for exactly this case.

So the block is WhatsApp policy correctly enforced, not a Lynomia limitation.

## 3. What was explicitly not done

- No local record was flipped to `APPROVED`.
- No fake or local-approved template was created.
- No second template model was created — the P3 Template Manager already exists (§4).
- Scenario 3 is **not** marked PASS.

## 4. Correcting an earlier probe artefact

A temporary probe guessed three constant names (`WhatsappTemplate`, `Whatsapp::Template`, `MessageTemplate`) and
printed `local template model: NOT FOUND`. **That was a bad guess list, not a missing model.** The real P3 Template
Manager is:

| | |
|---|---|
| model | `Whatsapp::MessageTemplate` — `custom/app/models/whatsapp/message_template.rb:31` |
| table | `whatsapp_message_templates` — already in `db/schema.rb:1796-1814` |
| scope | per WABA, via the `business_account_id` string column |
| status | `meta_status`, a plain nullable string — **not** a Rails enum |
| value list | `Whatsapp::Templates::StatusUpdate::STATUSES` — APPROVED ARCHIVED DELETED DISABLED IN_APPEAL LIMIT_EXCEEDED PAUSED PENDING PENDING_DELETION REJECTED |
| local draft | `meta_status` NULL (`scope :local`) |

There are deliberately **two** stores answering different questions: this management store for authoring and
lifecycle, and the channel's jsonb snapshot as the send gate — *"a send must not depend on a projection having
run, so the snapshot stays the live gate."*

## 5. What unblocks it

1. `order_delivered` reaches **APPROVED** at Meta.
2. The approval arrives as a `message_template_status_update` on the now-correct app-level callback (`01`) and is
   applied by `Whatsapp::Templates::StatusUpdate`, keyed on the WABA id. **This is the first real test of the
   app-level repair** — before it, that event was dropped (`00` §6).
3. The channel's snapshot syncs, so the template becomes visible to the send gate.
4. Then Scenario 3 runs against one real new contact outside the 24-hour window, recording local message id, Meta
   wamid, template name and language, send result, and SENT / DELIVERED / READ, or FAILED with Meta's reason.

Note for step 4: error **131049** is a per-recipient marketing cap (`00` §4). `order_delivered` is **UTILITY**,
which is the right category to avoid it, but a capped recipient can still refuse — and that would be Meta's
decision, not a Lynomia failure.
