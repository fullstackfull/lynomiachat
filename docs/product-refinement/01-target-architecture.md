# The architecture this project was aiming at

Product Refinement, workstream 0. Branch `claude/product-refinement`.

`00-current-state.md` says what was wrong. This says what shape the fixes were supposed to take, and —
more usefully for whoever works here next — which of those shapes held up and which one had to be abandoned
mid-project.

There are five principles. They are not a style guide; each one exists because a specific defect in
`00-current-state.md` could not have happened if it had been followed.

---

## Principle 1: `unknown` is a state, not a synonym for healthy

**Because of** §7: the operator console rendered an unprobed component the same as a working one.

A health reading has four states, and the third is load-bearing:

| state | meaning |
|---|---|
| `HEALTHY` | observed, and working |
| `WARNING` / `CRITICAL` | observed, and not working |
| `UNKNOWN` | **not observed** — we failed to look, or nothing has reported yet |

`Operations::Health::Component` carries a `source_class` saying how the reading was obtained — `probed`,
`recorded`, `computed` or `absent` — so the console can distinguish "we asked and it answered" from "we have
not asked". A probe that raises returns `UNKNOWN`, never `CRITICAL`: failing to look is not the same as
having looked and found it broken.

The corollary, stated in the brief and kept: **do not equate "no recent error" with healthy.** A store with
no failures and no successes is `UNKNOWN`, and a store whose last success is older than
`COMMERCE_HEALTH_STALE_AFTER_HOURS` goes back to `UNKNOWN` rather than staying green on a stale fact.

### Where it held

Throughout. `Commerce::StoreHealth#api_state` returns `failing`/`healthy`/`stale`/`unknown` and maps `stale`
to `UNKNOWN`; `Operations::ChannelMatrix` reports `unreported` separately from `degraded`; `Probes#unreachable`
is `UNKNOWN`. There is no health score anywhere, because averaging an `unknown` into a number turns missing
information into a reassuring digit.

## Principle 2: one writer per fact, and the writer is the only place the rule lives

**Because of** §9: the unread count had two writers with different ideas of the key, and §5's
`multiple_payments`, where the reason vocabulary lived in one place and its translation in another.

Every fact this project introduced has exactly one writer:

| fact | the only writer |
|---|---|
| machine-observed operational signals | `Operations::SignalRecorder` |
| operator decisions on a signal | `Operations::SignalLifecycle` |
| commerce provider health | `Commerce::StoreHealthRecorder` |
| the notification unread count | the `notifications` Vuex module, from its own state |

The notification fix is the clearest case. The defect was not a typo; it was an **architecture** in which
callers handed the store its own counters back, so every caller was a chance to get the key or the source
wrong. The fix removed the parameter: `read` and `delete` read `state.meta` themselves, and there is no key
left for a caller to name incorrectly. Four call sites lost an argument.

### Where it held, with one deliberate exception

`Commerce::StoreHealthRecorder` accepts **only** a `Commerce::Error` on the failure path, which makes the
"no raw exception text" rule structural rather than disciplinary — a caller cannot pass an arbitrary string
because the method signature refuses it.

The exception: `Operations::Signal`'s two-state fact semantics meant `handling_state` and the incident
timeline are **derived**, not stored. A stored status would have to be swept when a suppression lapses, and a
sweep that falls behind is how a silenced problem stays silent.

## Principle 3: enforce at the earliest shared entry point, and nowhere else

**Because of** CLAUDE.md, and because §1's retirement initially tried to refuse the legacy Shopify hook in
several places at once.

The rule: find the one place every path passes through, enforce there, and do not add backup guards
downstream unless a *proven* independent path bypasses that point.

Worked examples from this project:

* **Commerce provider calls.** `Commerce::HttpClient` is the single choke point every provider interaction
  passes through, so health recording is threaded through it rather than added to each of the four providers.
* **Legacy Shopify hook creation.** `hooks_controller#create` is the only generic writer of
  `integrations_hooks` (the other three writers are Notion-, Linear- and Slack-specific), so the refusal is
  there and the model keeps no second guard.
* **Conversation access.** `Conversations::AccessCeiling` holds the Inbox/Team rule once, as both a record
  predicate and a relation, so the policy and the list paths cannot disagree.

The inverse is also enforced: `destroy` on a retired Shopify hook is **not** refused, because an account
holding one must be able to remove it, and refusing would strand exactly the rows a migration needs.

## Principle 4: a spec must assert what the human can read, not that the page rendered

**Because of** §4, §8 and §9 — three defects that lived in a green suite because every assertion was about
status codes and absence of secrets.

The three failure modes to assert against:

1. **A selector that matches nothing agrees with the fallback.** `.message--unread` returned an empty
   NodeList and the bottom-scroll fallback produced the same answer, so the test and the bug agreed.
2. **A `rescue` next to a raise makes a missing feature look like a working page.**
   `paginate …, theme: 'administrate' rescue nil` returned 200 with no pagination.
3. **A page can contain a string for reasons unrelated to the assertion.** The documentation sidebar lists
   published article titles, so `body).to include(title)` passes with zero search results.

So: assert the pagination markup, assert the rendered `<title>`, assert the empty state rather than the
absence of a title, and — the part that is not optional — **invert the protection and watch the example
fail.** Every spec this project added for a previously-broken behaviour was run against the old code first.
Four of the nine search examples fail when `.published` moves; both Operations console examples fail against
the old templates.

## Principle 5: say UNKNOWN out loud rather than inventing precision

**Because of** §3 (a clock that meant "sending" when nothing had reported) and §6 (a document that said
"forever" when the sweep runs nightly).

Three applications, all shipped:

* **Delivery status.** `MESSAGE_STATUS.UNKNOWN` is documented in `constants.js` as *not a server status*,
  and renders `i-lucide-circle-help` — deliberately not a check (which claims the provider confirmed
  something) and deliberately not a clock (which claims we are still trying).
* **Commerce store health.** A store with no observations reads `UNKNOWN` in the console, with the standing
  caveat that recording began when this change deployed.
* **Documentation.** The audit retention article now names the window, the floor, who can change it, and
  that the sweep errs longer rather than shorter — instead of a single confident adverb.

---

## The one shape that was abandoned

The brief's residual-credential item asked, in effect, for a cleanup that removes the legacy Shopify
`integrations_hooks` rows holding non-expiring offline Admin API tokens. A migration was written for it and
then **deleted**, because the design was wrong in a way that only became clear once the surrounding facts
were assembled:

`hook.reference_id` is the shop domain, and it is the **only remaining record of which shops still have the
legacy app installed** — which is to say, of where the live tokens are. Removing Lynomia's copy of a token
does not revoke it; only uninstalling the app from the shop, or deleting the Partner app, does that. So an
automatic migration would have destroyed the list before anybody used it, left every token live at Shopify,
and printed a reassuring count on the way past.

The audit therefore has to **outlive** the token rather than be replaced by something that deletes it. The
full reasoning is `02-shopify-retirement.md` §residual.

This is recorded here, in the architecture document, because it is the project's one case of a principle
reversing a requirement: Principle 5 — do not manufacture the appearance of closure — outranked the
instruction to clean the rows up.

## Deliberately out of scope

Three things this project was told to leave alone, and did:

* **Platform Support.** Its two dependencies were built (`Notifications::ConversationVisibility` made
  fail-closed with a positive allow-list, and an explicit sidebar navigation contract) and nothing else. The
  branch `claude/platform-support-discovery` is untouched: no implementation, no migrations, not merged.
  `Operations::AccountSnapshot#support` is documented as the seam and does nothing yet.
* **Platform Support notifications.** Not added.
* **Stage two of the CSP.** `script-src` and friends still have to be enumerated from what the dashboard,
  widget, SDK and portal actually load, and a policy that misses one source breaks a feature in production.
  `06-public-surface-audit.md` §3 records why this is not what stands between a visitor and an article's
  markup.
