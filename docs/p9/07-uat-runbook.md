# P9 UAT runbook — and the combined P8 + P9 release pass

P8 and P9 will be deployed **together**, in one controlled deployment, because P8 was deliberately left
undeployed while P9 was built. So this runbook covers both: §1–§7 are P9, §8 is the P8 regression smoke that
has to pass on the same build, and §9 is the matrix with every item classified.

Written so a non-author can run it.

---

## 0. Before you start

| Requirement | Why |
| --- | --- |
| **`lynomia_support_tickets` enabled on the pilot account** | the hard prerequisite. The routes carry the flag and so do the sidebar entries, so with it off there is no Support entry, no Cases tab and no SLA settings — and the API answers 404. Nothing below is reachable. |
| **`reports` enabled on the pilot account** | §4 and the whole of §8. |
| A **super admin** login | §5 and §6. |
| An **administrator** login on the pilot account | everything in §1–§4, and all of §8. |
| An **agent** login *without* `support_ticket_manage` | §3, the ownership rule. |
| A second **agent** login *with* `support_ticket_manage` | §3. |
| The account's **reporting timezone** set | §8's first check. |
| At least one **inbox with working hours configured** | §2's business-hours check. Without one, record that item NOT APPLICABLE rather than failing it. |

```ruby
Account.find(<id>).enable_features!('lynomia_support_tickets', 'reports')
```

Grant `support_ticket_manage` in Settings → Team → Custom roles, on a role assigned to the second agent.

### What this runbook will and will not do

**Writes**: it opens, edits, resolves, reopens and closes support cases, writes internal notes, creates and
deletes an SLA policy, and opens one operational case from the Operations console. All of that is inside the
pilot account and inside tables P9 introduced.

**Does not**: send a message to anybody, run a campaign, call a provider, change a feature flag other than the
two above, touch a credential, or mutate Sidekiq. §8 is read-only throughout.

---

## 1. The support workspace

### U1 — Support appears, and only with the flag

1. With `lynomia_support_tickets` **off**, load the dashboard as the administrator.
2. Enable it, reload.

**Pass**: no **Support** entry, no **Cases** tab on a contact, no **Support → SLA policies** in Settings while
the flag is off; all three appear after it is on. **Fail**: any of them visible with the flag off (an entry that
leads to a redirect is a fail, not a cosmetic issue).

### U2 — Open a case with a customer and a channel

1. Sidebar → **Support** → **New case**. Title it something recognisable. Pick a category and a priority.
2. Save.

**Pass**: the case opens with reference `TCK-000001` (or the next number for this account), status **Open**, and
a history containing exactly one entry, *Case opened*, attributed to you.
**Fail**: no reference, a reference that is not account-sequential, or an empty history.

### U3 — Open an internal case with no customer at all

1. **New case** again. Leave contact, conversation and inbox empty. Category **Operational**.

**Pass**: it saves. This is the case a conversation cannot represent, and it is the architectural claim of the
whole phase — if it fails, the phase is wrong.

### U4 — The six views, and the URL

1. Click each view in turn: All, Mine, Unassigned, Overdue, Resolved, Closed.
2. Read the address bar on each.
3. Copy the URL of a filtered view, open it in a new tab.

**Pass**: the view, the filters, the sort and the page are all in the URL, and the new tab shows the same list.
The number on each tab matches the length of the list under it when you open that tab.
**Fail**: a tab count that disagrees with its own list — that is a disclosure, not a rounding error.

### U5 — Filters refuse rather than silently ignore

1. Edit the URL by hand: set `status=nonsense`.
2. Then `per_page=5000`.
3. Then `sort=whatever`.

**Pass**: each gives a clear message naming what is allowed. **Fail**: any of them returns a page as if the
filter had been accepted, or an empty page with no explanation.

### U6 — Search is reference-first

1. Type the case's full reference (`TCK-000001`) into the search box.
2. Then type a word from its title.
3. Then type a reference that does not exist (`TCK-999999`).

**Pass**: (1) returns exactly that case; (2) returns title matches; (3) returns **nothing**, not a title search.
**Fail**: (3) falling back to a title match — that hides the fact that the reference does not exist.

### U7 — Status transitions offer only what is reachable

1. Open a case. Open the status control.
2. Resolve it. Open the control again.
3. Close it. Open the control again.

**Pass**: an active case offers all four active states plus Resolved and Closed; a resolved case offers Closed
and Open; a closed case offers only Open. The history reads *Resolved*, then *Closed* — not two identical
"status changed" rows.

### U8 — Reopening clears the right things and keeps the right things

1. Resolve a case, note the resolved time. Close it, note the closed time.
2. Reopen it.

**Pass**: reopening clears both timestamps and the history says **Reopened**. Going `resolved → closed` did
**not** clear the resolved time — "resolved Monday, closed Friday" must still be readable.

### U9 — Notes

1. Add an internal note. Add a second.
2. Try to save an empty one.

**Pass**: both appear in the history, newest at the bottom, attributed to you; the empty one is refused.
**Fail**: a note attributed to anyone else.

---

## 2. SLA

### U10 — Create a policy

1. Settings → **Support** → **SLA policies** → new. Set a first-response target of 15 minutes and a resolution
   target of 4 hours. Leave business hours off. Save.
2. Try to save a second policy with **both** targets empty.

**Pass**: the first saves and the list shows the thresholds in readable units; the second is refused. A policy
that can compute nothing must not be creatable.

### U11 — Attach it, and watch the clock start from now

1. Open a case that has existed for a while. Attach the policy.

**Pass**: the due times are **15 minutes and 4 hours from now**, not from when the case was created, and the
history gains an *SLA applied* entry naming the policy and both due times.
**Fail**: a due time in the past. A commitment nobody made is the one thing the clock must never invent.

### U12 — `waiting_on_customer` stops the clock; `waiting_on_internal` does not

1. Note the resolution due time. Move the case to **Waiting on customer**. Wait two minutes.
2. Move it back to **In progress**. Read the due time again.
3. Now move it to **Waiting on internal**. Wait two minutes. Read the due time again.

**Pass**: after (2) the due time has moved **forward by about two minutes** and the case shows the pause; after
(3) it has **not** moved. Waiting on ourselves is our own delay.

### U13 — Business hours, where an inbox has them

1. On an inbox with working hours configured, create a business-hours policy and attach it to a case **linked to
   that inbox**.
2. Attach the same policy to a case with **no inbox**.

**Pass**: the first case's due time respects the inbox's working hours and timezone; the second says plainly
that it is on calendar time. **Fail**: the second silently claiming business hours it cannot apply.
If no inbox has working hours configured, record **NOT APPLICABLE**.

### U14 — Overdue is not breached

1. Create a policy with a 1-minute resolution target, attach it to a case, and wait for the sweep (≤ 5 minutes).

**Pass**: before the sweep the case reads **Overdue**; after it, **Breached**, with a
*Resolution target missed* entry in the history. It reads as exactly one of the two at any moment, never both.

### U15 — The first response is detected from the conversation

1. On a case **linked to a conversation**, send an outgoing reply in that conversation. Wait for the sweep.

**Pass**: the case records a first response at the reply's time, and if that was inside the target the history
says *First response met*. **Fail**: a first-response breach on a case that was replied to in time.

---

## 3. Permissions

### U16 — An agent sees their own work and nothing else

As the agent **without** `support_ticket_manage`:

1. Open **Support**.
2. Then open, by URL, a case assigned to somebody else in the same account.

**Pass**: the list holds only the cases assigned to them, assigned to one of their teams, or that they opened;
the other case gives **not found**, not "forbidden".
**Fail**: a 403 (it confirms the case exists), or the case being visible.

### U17 — A support lead sees everything

As the agent **with** `support_ticket_manage`: open **Support**.

**Pass**: every case in the account, and the tab counts agree with the lists.

### U18 — SLA settings are administrator-only

As either agent, try the SLA policies URL directly.

**Pass**: refused. Setting an account-wide commitment is not a per-case decision.

---

## 4. Where a case shows up elsewhere

### U19 — The conversation panel

1. Open a conversation. Find the **Cases** section in the right sidebar.
2. Use its button to open a case.

**Pass**: the new case arrives with the conversation, contact and inbox already filled in, and then appears in
that panel. **Fail**: having to pick the customer again on a screen that already knows who it is.

### U20 — The contact's Cases tab and timeline

1. Open that contact. **Cases** tab.
2. Then the **Activity** tab, filtered to **Cases**.

**Pass**: the Cases tab lists the contact's cases; the Activity timeline shows the case's history entries in
order with everything else. **Fail**: an internal note's **body** appearing anywhere in the timeline — the
timeline is a wider audience than the case.

### U21 — Analytics

Analytics → **Support cases**.

**Pass**: the counts match what you created in §1–§2 (created, resolved, reopened, breaches), the breakdowns by
priority, category, status, team and assignee add up, and the footnote names the account's timezone.
There is **no** SLA attainment percentage, **no** first-response average and **no** reopen rate — their absence
is correct and documented (`02-support-tickets.md` §7).

### U22 — The conditional SLA warning

1. Leave at least one active case with **no** policy attached. Reload Analytics → Support cases.
2. Attach a policy to every active case. Reload.

**Pass**: the banner appears in (1), reading in **words** ("SLA breach counts: some open cases have no SLA
policy attached…"), and is **gone** in (2). **Fail**: a banner that is always there — operators learn to ignore
those — or one that reads as raw tokens like `sla could not be included: active_cases_without_a_policy`.

---

## 5. The Operations Center

As the **super admin**: Super Admin → **Operations**.

### U23 — The installation page is honest about what it does not know

**Pass**: database, Redis, workers and migrations each carry a status and, where not healthy, a reason. Areas
with no source in this installation read **absent** with the reason, not green. The computed block says **how
old** the reading is.
**Fail**: any green badge for something this installation has no source for. That is the one failure mode that
makes the whole page worthless.

### U24 — The reading is a real reading

1. Note the worker count. Compare it with Sidekiq Dashboard.
2. Note the WhatsApp delivery figure. Compare it with Analytics → WhatsApp on the busiest account over the same
   24 hours.

**Pass**: they agree, allowing for the console's 5-minute cache.

### U25 — Accounts

**Pass**: 25 accounts per page, each with component badges and **no score**. The page responds in about the time
the other Super Admin list pages take.

### U26 — Issues

1. Open **Issues**. Filter open / resolved / all.

**Pass**: each row names the source, the signal, the severity, the recurrence count, when it was first and last
seen, the account and the subject. If this installation has recorded nothing yet, the page **says so** — that is
a pass, not an empty failure.

### U27 — Read the page with your own eyes for a leak

Slowly read all three pages, and view source on one.

**Pass**: no token, key, password, OAuth token, webhook secret, provider payload, connection string or internal
filesystem path anywhere. **Fail**: any of them — this is a release blocker, not a finding.

### U28 — Open a case from an issue

1. On an account-scoped issue, use **Open case**.
2. Use it again on the same issue.
3. Find an installation-wide issue (no account) and try it.

**Pass**: (1) opens an operational case, priority mapped from the severity, linked both ways; (2) surfaces the
**same** case rather than a second; (3) is refused **with a reason**.
**Fail**: a second case for the same open issue, or a case whose creator is somebody who did nothing.

### U29 — The case the console opened is clean

Open the case from (1) in the agent dashboard.

**Pass**: its title and description describe the problem and carry no credential and no provider payload.

---

## 6. Super Admin boundary

### U30 — Only a super admin gets in

1. Log out. Hit `/super_admin/operations`.
2. Log in as the account administrator. Hit it again.
3. As the agent. Again.

**Pass**: all three refused, on all three pages and on the case button.

---

## 7. Arabic and RTL

### U31 — The workspace in Arabic

Switch the profile language to العربية and walk §1 again, briefly.

**Pass**: every label, status, priority, category, SLA state, history entry, filter and empty state is in Arabic;
the layout mirrors; the list, the filter bar and the detail page all read right-to-left without clipping.
**Fail**: an English string in the Arabic UI, or a layout that uses left/right instead of start/end.

---

## 8. P8 regression smoke — on the same build

P9 touched four things P8 owns: the contact activity timeline (a new `tickets` category), the analytics family
registry (a new `tickets` family), the shared analytics partial-response banner (its copy), and the analytics
API client. So the whole of P8 is re-checked, not just the parts that look related.

Everything in this section is **read-only**.

### R1 — All six P8 analytics screens plus the new seventh

Analytics → Overview, WhatsApp, Campaigns, Automations, Flows, Commerce, **Support cases**.

**Pass**: seven screens, each loading with KPIs, series and a breakdown or an explicit empty state, and each
with a footnote naming the date range, the grouping **and the timezone**.
**Fail**: any screen that errors, or numbers with no footnote.

### R2 — The account timezone still governs

Note a total and the footnote timezone. Change **your own** profile timezone. Reload.

**Pass**: nothing moves. This is the most important P8 check and P9 must not have disturbed it.

### R3 — The partial-response banner still works for P8's own warnings

Find an account with delayed automation rules in the range (Analytics → Automations).

**Pass**: the banner reads in words. **Fail**: raw snake_case tokens — the P9.8 copy change must have improved
this, not broken P8's own two warnings.

### R4 — WhatsApp delivery numbers are unchanged

Compare the WhatsApp screen's counts against the figures recorded in `docs/p8/P8_FINAL_COMPLETION_REPORT.md` for
the same range, if a range overlaps.

**Pass**: unchanged, or explained by new activity since.

### R5 — Campaign analytics

Open Analytics → Campaigns and one campaign's own screen.

**Pass**: the two agree on recipients, delivered and read. No campaign is sent during this check.

### R6 — Automation and flow analytics

**Pass**: both load; the automation screen still carries its retention and immediate-rule notes.

### R7 — Commerce analytics

**Pass**: loads; cart counts by currency, no summed revenue across currencies.

### R8 — The contact activity timeline, with the new category

1. Open a contact with history. **Activity** tab.
2. Walk every filter, including the new **Cases**.
3. Page to the end of a long timeline.

**Pass**: every P8 source still appears (messages, notes, conversations, campaigns, automations, commerce), the
new Cases entries interleave in the right time order, and paging reaches the end without repeating or skipping
a row at a page boundary.
**Fail**: a P8 source that stopped appearing — the adapter signature changed in P9.4, and this is the check for
it.

### R9 — Timeline permissions

As an agent restricted to some inboxes, open the same contact's Activity tab.

**Pass**: nothing from a conversation they cannot open, and no case they have no claim on.

### R10 — The six screens for an agent

**Pass**: refused for all of them (analytics is administrator-only), consistently.

---

## 9. The matrix

Classification, strictly:

| | |
| --- | --- |
| **AUTOMATED PASS** | an automated test in this repository proves it, and the test ran green on the release build |
| **SIMULATED PASS** | proved against seeded or synthetic data, by hand or by harness. **Not** evidence about production data. |
| **REAL DATA PASS** | proved against the installation's own real records, after deployment. Nothing may be recorded here from a fixture. |
| **PENDING REAL UAT** | needs the production deployment and a human; not yet run |
| **BLOCKED** | cannot be run, with the blocker named |
| **NOT APPLICABLE** | the configuration this needs does not exist in this installation |

| # | Item | Now | After the combined deployment |
| --- | --- | --- | --- |
| U1 | flag gating on all three surfaces | AUTOMATED PASS (routes, request specs) + SIMULATED PASS | PENDING REAL UAT |
| U2 | open a customer case, numbered, with history | AUTOMATED PASS | PENDING REAL UAT |
| U3 | open an internal case with no links | AUTOMATED PASS | PENDING REAL UAT |
| U4 | six views, URL as state, counts agree | AUTOMATED PASS (counts, scoping) + SIMULATED PASS (URL) | PENDING REAL UAT |
| U5 | filters refuse with the allowed set | AUTOMATED PASS | PENDING REAL UAT |
| U6 | reference-first search | AUTOMATED PASS | PENDING REAL UAT |
| U7 | transition table | AUTOMATED PASS | PENDING REAL UAT |
| U8 | reopen clears both stamps, resolve→close keeps one | AUTOMATED PASS | PENDING REAL UAT |
| U9 | notes, attribution, empty refused | AUTOMATED PASS | PENDING REAL UAT |
| U10 | policy validation | AUTOMATED PASS | PENDING REAL UAT |
| U11 | clock starts from attachment, never backwards | AUTOMATED PASS | PENDING REAL UAT |
| U12 | pause on waiting_on_customer only | AUTOMATED PASS | PENDING REAL UAT |
| U13 | business hours, inbox-scoped; calendar time without an inbox | AUTOMATED PASS | PENDING REAL UAT — **NOT APPLICABLE** if no inbox has working hours |
| U14 | overdue then breached, never both | AUTOMATED PASS | PENDING REAL UAT |
| U15 | first response detected from messages | AUTOMATED PASS | PENDING REAL UAT |
| U16 | agent ownership scope, 404 not 403 | AUTOMATED PASS (policy + 24 isolation examples) | PENDING REAL UAT |
| U17 | support lead sees the account | AUTOMATED PASS | PENDING REAL UAT |
| U18 | SLA settings administrator-only | AUTOMATED PASS | PENDING REAL UAT |
| U19 | conversation panel, prefilled | SIMULATED PASS (component specs) | PENDING REAL UAT |
| U20 | contact Cases tab and timeline, no note bodies | AUTOMATED PASS (no bodies) + SIMULATED PASS (UI) | PENDING REAL UAT |
| U21 | case analytics add up; three metrics correctly absent | AUTOMATED PASS | PENDING REAL UAT |
| U22 | the SLA warning is conditional and reads in words | AUTOMATED PASS | PENDING REAL UAT |
| U23 | unknown is never green | AUTOMATED PASS | PENDING REAL UAT |
| U24 | the console's figures match the sources | SIMULATED PASS | **PENDING REAL UAT** — this one can only be judged against the real installation |
| U25 | accounts page, no N+1, no score | AUTOMATED PASS + SIMULATED PASS (plans) | PENDING REAL UAT |
| U26 | issue feed, honest when empty | AUTOMATED PASS | PENDING REAL UAT |
| U27 | read-by-eye leakage review of all three pages | AUTOMATED PASS (planted real credentials) | **PENDING REAL UAT** — a human must still read the real pages |
| U28 | case bridge: idempotent, mapped, refuses installation-wide | AUTOMATED PASS | PENDING REAL UAT |
| U29 | the opened case carries no credential | AUTOMATED PASS | PENDING REAL UAT |
| U30 | super admin boundary on all pages and the mutation | AUTOMATED PASS | PENDING REAL UAT |
| U31 | Arabic and RTL across the workspace | SIMULATED PASS (192/192 key parity, both locales) | PENDING REAL UAT |
| R1 | seven analytics screens load with footnotes | AUTOMATED PASS | PENDING REAL UAT |
| R2 | account timezone governs, not the viewer's | AUTOMATED PASS | PENDING REAL UAT |
| R3 | P8's own two warnings still read in words | AUTOMATED PASS | PENDING REAL UAT |
| R4 | WhatsApp delivery figures unchanged | AUTOMATED PASS (metrics specs) | **PENDING REAL UAT** |
| R5 | campaign analytics agree with the per-campaign screen | AUTOMATED PASS | PENDING REAL UAT |
| R6 | automation and flow analytics | AUTOMATED PASS | PENDING REAL UAT |
| R7 | commerce analytics | AUTOMATED PASS | PENDING REAL UAT |
| R8 | every P8 timeline source still appears beside Cases | AUTOMATED PASS | PENDING REAL UAT |
| R9 | timeline permissions for a restricted agent | AUTOMATED PASS | PENDING REAL UAT |
| R10 | analytics refused for agents | AUTOMATED PASS | PENDING REAL UAT |

**Nothing in the left column is a REAL DATA PASS, and nothing in it may be converted into one.** Every automated
and simulated result here was produced against factory records or a synthetic fixture. Production currently
holds zero support cases and zero operations signals, so there is no real-data evidence about this phase to
have.

### The nine P8 items that are still pending, unchanged

Carried from `docs/p8/P8_FINAL_COMPLETION_REPORT.md`. They were pending because P8 was not deployed, and they
are still pending for the same reason:

1. production rollup read-only check;
2. confirm the `reports` feature is enabled for the pilot account;
3. production smoke on the six Analytics screens;
4. Contact Activity Timeline smoke;
5. coexistence-echo validation against real echoes;
6. Meta failure-code validation against real failures;
7. comparison against the real Reports history;
8. the read-by-eye leakage review;
9. the genuine-new-contact WhatsApp UAT — template `order_delivered`, `en_US`, APPROVED. **Not to be sent
   before the deployment.**
