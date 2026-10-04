# Label or audience — the product rule

Phase C4. A rule, not an engine. What exists in the product is enough to follow it; what is written here is the
decision somebody makes when they are about to classify a thousand contacts.

---

## The rule

**A label is a durable operational classification.** Somebody decided it, and it stays until somebody decides
otherwise. It is a `tagging` on the contact, so it is a fact the account owns.

> VIP · wholesale · needs follow-up · complaint escalated · event attendee · do not call

**A shared audience is dynamic membership.** Nobody maintains it; it is a saved contact filter whose members are
worked out again every time it is opened, counted or sent to.

> recent buyers · customers with an open order · spend above a threshold · customers of one store ·
> has contacted us · has never contacted us

**The test:** if the answer can change without anybody touching the contact, it is an audience. A contact becomes
a "recent buyer" because time passed; it becomes "VIP" because somebody said so.

---

## Why the distinction is load-bearing here, not just tidy

A label that encodes a dynamic fact goes stale silently, and nothing in the product will tell you. "Recent
buyers" as a label is correct on the day it is applied and wrong a month later — and a campaign sent to it will
reach exactly the people it should no longer reach. The audience that replaces it cannot be stale, because it has
no stored membership to be stale.

It matters in the other direction too. An audience cannot record a decision: there is no filter that means "this
customer complained and we escalated it", because that is not derivable from anything. That belongs in a label,
and no amount of filter conditions will substitute for it.

Both are first-class recipient sources for a campaign — `{ type: 'Label', id }` and `{ type: 'Audience', id }`
(see [06](06-campaign-bridge.md)) — so choosing correctly costs nothing at the point of sending.

---

## Where the rule appears in the product

| Where | What it says |
|---|---|
| The import dialog, under the batch labels picker | "A label is a durable classification you keep: VIP, wholesale, needs follow-up. Membership that works itself out — recent buyers, open orders — belongs in an audience instead." |
| The audience preset gallery | already says a preset's "members are worked out fresh every time it is opened" |
| The duplicate-policy hint in the import dialog | "Labels are added either way, and never replace the labels a contact already has." |

One new string, at the moment the mistake gets made — somebody assigning a label to a whole imported batch. The
rest is this document, because the product already expresses the dynamic half.

---

## The part of the brief this contradicts

The brief proposes a recipe: *conversation created → add label "Contacted us"*, described as labelling **the
Contact** associated with that conversation.

That is not what the action does. `ActionService#add_label` is:

```ruby
def add_label(labels)
  return if labels.empty?

  @conversation.reload.add_labels(labels)
end
```

It labels the **conversation**. `ActionService` is constructed with a conversation and has no contact in scope at
all. So a rule built that way would:

- not put the contact on a contact label page, because that page reads contact taggings;
- not make the contact a campaign recipient, because `audience_contacts` reads
  `account.contacts.tagged_with(...)`;
- and leave a growing pile of conversation labels that look like the contact labels they are not.

The brief anticipates this risk in its own wording — *"Be precise in the UI: this does NOT mean a Contact-level
automation trigger exists. Do not imply one."* — and the precise answer is that the recipe should not exist. The
same intent, "which contacts have ever written to us", is answered exactly by a **shared audience**, which is
what [08](08-recipes-and-presets.md) adds.

---

## What was deliberately not built

No `contact_created` or `contact_updated` automation trigger. No contact-label automation condition. No scheduled
scan of contacts. No rule that runs over an audience's members. No background job that labels every member of an
audience. No audience → label synchronisation of any kind.

All of them would be the thing the rule exists to avoid: stored membership for a question that should be asked
fresh.
