# Clean-room acceptance test plan

**Audience: the clean-room implementer.**

This plan states what the finished implementation must *do*, as scenarios an outside observer can check. Every
scenario is written against the product's public surface — an HTTP request, a visible page, a database row the
product itself wrote. None of it describes or presumes any particular internal design.

**These scenarios are the acceptance criteria.** Write your own tests from them, in whatever structure your
implementation suggests. Do not look for an existing test suite for the five feature packages: there is none in
the workspace you were given, by design, and nothing you are shown is a translation of one.

## How to use this plan

1. Read the feature package specification for the area (`specs/A`–`specs/E`) and the integration contract
   (`04-integration-contract.md`) first. The specifications say what the contract is; this plan says what to
   check.
2. Implement, then satisfy every scenario in the matching section.
3. Sections F and G are cross-package and must pass after all five packages are in place.
4. A scenario marked **[isolation]** is a tenant-safety check. These are not optional and not "nice to have":
   each one is a scenario in which one customer could read or alter another customer's data.

## Conventions used below

| term | meaning |
|---|---|
| **account A**, **account B** | two separate customer accounts, each with its own members. Nothing is shared between them |
| **admin** | a member of the named account whose role is administrator |
| **agent** | a member of the named account whose role is agent, holding no named permission set |
| **role-holder** | an agent of the named account with a named permission set attached (package C) |
| **machine credential** | a non-person actor that can administer an account through the platform API |
| **the trail** | the account's audit trail page / endpoint (package A) |
| **a report** | a delivery-status webhook from the official WhatsApp Cloud API (package E) |
| **observable** | visible in an HTTP response, on a page, or in a row the product wrote — never asserted by reaching into internals |

Unless a scenario says otherwise: requests are authenticated as a member of account A, and the account has the
relevant capability enabled.

---

## Section A — Reading the audit trail

**A-1. The page lists the account's recent events**
- PRECONDITIONS: account A has at least 3 recorded events, created at different times.
- ACTION: admin of A requests the trail with no parameters.
- EXPECTED: `200`. The events are returned newest first. The response states the total number of matching
  events, the page size applied, and the page returned. The total is the total — not the number of rows in this
  page.

**A-2. Oldest-first ordering**
- PRECONDITIONS: as A-1.
- ACTION: request the trail asking for ascending order.
- EXPECTED: the same events, oldest first. The total is unchanged.

**A-3. A time window restricts both the rows and the total**
- PRECONDITIONS: account A has events inside and outside a chosen window.
- ACTION: request the trail with a lower and an upper time bound.
- EXPECTED: only events inside the window are returned, and the reported total counts only those.

**A-4. Filtering by event type**
- PRECONDITIONS: account A has events of at least two different types.
- ACTION: request the trail restricted to one type.
- EXPECTED: only events of that type are returned, with a total matching.

**A-5. Filtering by actor**
- PRECONDITIONS: two different members of account A have each caused at least one event.
- ACTION: request the trail restricted to one of them.
- EXPECTED: only that actor's events are returned.

**A-6. A page past the end is empty, not an error**
- PRECONDITIONS: account A has fewer events than one page holds.
- ACTION: request page 50.
- EXPECTED: `200`, an empty list of events, and the real total.

**A-7. Nonsense filter values do not break the page**
- PRECONDITIONS: account A has events.
- ACTION: request the trail with a non-numeric page, a non-numeric time bound, and an unknown sort direction, in
  one request.
- EXPECTED: `200`. No `500`, no exception reported. Either the values are ignored or the page comes back empty.

**A-8. An event stays attributable after its actor is deleted**
- PRECONDITIONS: a member of account A caused an event, then that member's user record was deleted.
- ACTION: read the trail.
- EXPECTED: the event is still returned and still names who did it in a human-readable form.

**A-9. An event caused by a machine credential is readable**
- PRECONDITIONS: a machine credential changed something in account A.
- ACTION: read the trail.
- EXPECTED: the event is returned without error, and does not claim a person did it.

**A-10. An event whose subject has been deleted is readable**
- PRECONDITIONS: an inbox of account A was created and then destroyed; both events were recorded.
- ACTION: read the trail.
- EXPECTED: both events are returned; neither requires the inbox to still exist.

**A-11. Only administrators may read the trail**
- PRECONDITIONS: account A has an admin, an agent, and a role-holder with every named permission the product
  offers.
- ACTION: each of the three requests the trail.
- EXPECTED: the admin gets `200`. The agent is refused. The role-holder is refused. A named permission set
  does not open this page.

**A-12. [isolation] Another account's events are unreachable**
- PRECONDITIONS: accounts A and B each have events.
- ACTION: admin of A requests the trail, and then re-requests it supplying account B's identifier, B's members'
  identifiers as the actor filter, and a wide time window.
- EXPECTED: in no response does an event belonging to account B appear.

**A-13. Without the capability the page is empty, not broken**
- PRECONDITIONS: account A does not have the audit capability enabled, and has events in the store.
- ACTION: admin requests the trail.
- EXPECTED: `200` with no events. The page shows its empty state rather than an error.

**A-14. Address disclosure is gated**
- PRECONDITIONS: an event of account A recorded the originating address. Run twice: once with the address
  capability off, once on.
- ACTION: read the trail in both configurations.
- EXPECTED: with the capability off, no response contains a full address, and what is shown cannot identify the
  individual machine. With it on, the full address is present. In neither case does a blank or malformed stored
  address raise.

**A-15. No credential is ever rendered**
- PRECONDITIONS: an event of account A whose recorded detail contains a key that looks like a credential
  (plant one deliberately: a token, a secret, a password field).
- ACTION: read the trail.
- EXPECTED: the planted value does not appear anywhere in the response.

**A-16. No location data**
- PRECONDITIONS: account A has events.
- ACTION: read the trail.
- EXPECTED: no response field states a city, a country or a country code. This capability is deliberately
  absent from the product.

**A-17. Reading a page costs a fixed number of queries**
- PRECONDITIONS: account A has 50 events on one page's worth of data, each with a different actor.
- ACTION: read the trail, counting database queries.
- EXPECTED: the count does not grow with the number of events on the page.

---

## Section B — Recording what happened

Every scenario in this section is verified **through the read surface of section A**. "An entry appears" means a
request to the trail returns it. Nothing here should be checked by inspecting internals.

**B-1. An account settings change is recorded**
- PRECONDITIONS: admin of account A.
- ACTION: change one account setting; read the trail.
- EXPECTED: an entry naming the account, the actor, the changed field, and its value before and after.

**B-2. A role change is recorded with both roles**
- PRECONDITIONS: admin of A, and another member whose role is agent.
- ACTION: change that member's role to administrator; read the trail.
- EXPECTED: an entry naming who was changed, by whom, and both the old and the new role.

**B-3. Editing your own membership is distinguishable from editing someone else's**
- PRECONDITIONS: admin of A.
- ACTION: change your own availability; separately change another member's; read the trail.
- EXPECTED: two entries that a reader can tell apart as self and other.

**B-4. A membership change survives the user being deleted**
- PRECONDITIONS: a membership change was recorded, then that user's record was deleted.
- ACTION: read the trail.
- EXPECTED: the entry is still rendered and still attributable.

**B-5. Inbox lifecycle**
- PRECONDITIONS: admin of A.
- ACTION: create an inbox, change its name, delete it; read the trail.
- EXPECTED: three entries, with three distinguishable actions, all naming the inbox.

**B-6. Inbox membership**
- PRECONDITIONS: admin of A, an inbox, another member.
- ACTION: add the member to the inbox, then remove them; read the trail.
- EXPECTED: two entries naming the member and the inbox.

**B-7. Team lifecycle and team membership**
- PRECONDITIONS: admin of A.
- ACTION: create a team, add a member, remove the member, delete the team; read the trail.
- EXPECTED: four entries, each naming its subject.

**B-8. Automation rule lifecycle**
- ACTION: create, change and delete an automation rule; read the trail.
- EXPECTED: three entries naming the rule.

**B-9. Macro lifecycle**
- ACTION: create, change and delete a macro; read the trail.
- EXPECTED: three entries naming the macro.

**B-10. Webhook lifecycle**
- ACTION: create, change and delete a webhook; read the trail.
- EXPECTED: three entries naming the webhook.

**B-11. Agent bot lifecycle**
- ACTION: create, change and delete an agent bot; read the trail.
- EXPECTED: three entries naming the bot.

**B-12. A deleted conversation is named the way a human recognises it**
- PRECONDITIONS: a conversation in account A.
- ACTION: delete it; read the trail.
- EXPECTED: an entry that identifies the conversation by the number shown in the product, not only by an
  internal identifier.

**B-13. A deleted message names its conversation and never its content**
- PRECONDITIONS: a message in account A whose body contains a distinctive phrase, with an attachment.
- ACTION: delete the message; read the trail.
- EXPECTED: an entry naming which conversation it was in. The distinctive phrase appears nowhere in the
  response, and neither does any attachment name or URL.

**B-14. A simultaneous double delete records once**
- PRECONDITIONS: a message in account A.
- ACTION: issue two concurrent deletions of it.
- EXPECTED: exactly one entry for that deletion.

**B-15. Sign-in and sign-out are recorded**
- ACTION: a member signs in, then signs out; read the trail.
- EXPECTED: two entries for that member.

**B-16. A failed sign-in does not record a success**
- ACTION: attempt a sign-in with the wrong password; read the trail.
- EXPECTED: no sign-in success entry for that attempt. (Recording failures is not required.)

**B-17. A channel configuration change is recorded without its credentials**
- PRECONDITIONS: an inbox whose channel holds a provider credential of a known value.
- ACTION: change a non-credential field of the channel configuration; read the trail.
- EXPECTED: an entry naming the changed field. The known credential value appears nowhere in the response —
  neither as an old value nor a new one.

**B-18. A credential rotation records the event, not the credential**
- PRECONDITIONS: as B-17.
- ACTION: change the credential itself; read the trail.
- EXPECTED: either no entry, or an entry that records that the credential changed without disclosing either
  value. Both are acceptable; disclosing the value is not.

**B-19. Asynchronous deletion names the requester, not the worker**
- PRECONDITIONS: admin of A requests deletion of an inbox that is removed by a background process.
- ACTION: let the deletion complete; read the trail.
- EXPECTED: an entry attributing the deletion to the admin who asked for it, not to the system.

**B-20. An entry always carries an account**
- PRECONDITIONS: cause one event of each type listed in B-1…B-19.
- ACTION: read the trail for account A and for account B.
- EXPECTED: every event appears in exactly one account's trail. None is missing from both.

**B-21. A recording failure does not fail the product action**
- PRECONDITIONS: the recording path is made to fail (break the store, or force an error in capture).
- ACTION: change an account setting.
- EXPECTED: the setting change succeeds and returns success to the caller. The user sees no error about
  auditing. The failure is visible to operators in the log or the exception tracker.

**B-22. A machine credential's actions are recorded**
- PRECONDITIONS: a machine credential with administrative access to account A.
- ACTION: have it change an account setting; read the trail.
- EXPECTED: an entry exists, attributed to the credential rather than to a person, and reading it does not
  raise.

---

## Section C — Named permission sets

**C-1. An administrator can create a permission set**
- PRECONDITIONS: admin of account A.
- ACTION: create a named set with a name, a description and two permissions.
- EXPECTED: `200`/`201` with the created set, including its identifier, name, description and permissions as
  given.

**C-2. Listing, reading, updating and deleting**
- PRECONDITIONS: account A has two sets.
- ACTION: list them; read one; rename it; delete the other.
- EXPECTED: each operation succeeds and the result reflects it. The list contains only account A's sets.

**C-3. An unknown permission is refused**
- ACTION: create a set containing a permission name the product does not define.
- EXPECTED: `422`. No set is created.

**C-4. An empty or nameless set is refused**
- ACTION: create a set with no name; then one with no permissions.
- EXPECTED: `422` for each, with a message naming the problem.

**C-5. Only administrators may manage sets**
- PRECONDITIONS: admin, agent and role-holder in account A.
- ACTION: each attempts to create, update and delete a set.
- EXPECTED: only the admin succeeds. The role-holder's own permissions do not let it manage sets.

**C-6. [isolation] Sets are per account**
- PRECONDITIONS: accounts A and B each have a set.
- ACTION: admin of A lists sets, reads B's set by its identifier, and attempts to update and delete it.
- EXPECTED: the list excludes B's set; the read, update and delete all fail with `404`. B's set is unchanged.

**C-7. A set can be attached when a member is invited**
- PRECONDITIONS: admin of A; a set granting one permission.
- ACTION: invite a new member as an agent with that set attached.
- EXPECTED: the created membership reports the attached set. The member can do what the set grants, and nothing
  else.

**C-8. A set can be attached to and detached from an existing member**
- PRECONDITIONS: an existing agent in A, and a set.
- ACTION: attach the set; confirm; detach it; confirm.
- EXPECTED: while attached, the member can use what it grants; once detached, they cannot.

**C-9. A member's granted permissions are visible to the UI**
- PRECONDITIONS: an agent with a set attached.
- ACTION: that member loads the product.
- EXPECTED: the response that describes their membership states both their role and the attached set's
  permissions, so the interface can decide what to show.

**C-10. A permission actually gates its feature**
- PRECONDITIONS: for each permission the product defines, a member holding only that permission, and a member
  holding none.
- ACTION: each attempts the action the permission is for.
- EXPECTED: the holder succeeds; the non-holder is refused with the product's standard refusal, not an error
  page and not a silent success.

**C-11. Administrators are not narrowed by a set**
- PRECONDITIONS: an administrator with a set attached that grants one narrow permission.
- ACTION: perform an administrator action unrelated to that permission.
- EXPECTED: it succeeds. Attaching a set never *removes* ability.

**C-12. Deleting a set does not delete people**
- PRECONDITIONS: a set attached to two members.
- ACTION: delete the set; then list the account's members.
- EXPECTED: both members still exist, still belong to the account, and have no set attached. Neither loses
  their base role. Nothing they owned is deleted.

**C-13. Renaming a set keeps it attached**
- PRECONDITIONS: a set attached to a member.
- ACTION: rename the set and change its permissions; re-read the member.
- EXPECTED: the member is still attached, and now has the new permissions.

**C-14. [isolation] A set cannot be attached across accounts**
- PRECONDITIONS: account A's member; account B's set.
- ACTION: admin of A attempts to attach B's set to A's member.
- EXPECTED: refused. The membership is unchanged.

**C-15. Without the capability, the feature is unavailable rather than broken**
- PRECONDITIONS: account A does not have the named-permission capability enabled.
- ACTION: attempt to list and create sets.
- EXPECTED: a clear refusal. No `500`. Existing attachments, if any, do not cause errors elsewhere in the
  product.

---

## Section D — Per-recipient campaign outcomes

**D-1. Every addressed contact gets a record**
- PRECONDITIONS: account A, a WhatsApp inbox, a one-off campaign addressing 3 contacts, all sendable.
- ACTION: run the campaign; read the campaign's results.
- EXPECTED: 3 recipients. Each shows as handed to the provider, each with the text that was sent. The reported
  audience is 3.

**D-2. An unsendable contact is skipped with a reason, not failed**
- PRECONDITIONS: as D-1, but one contact has no reachable WhatsApp destination.
- ACTION: run the campaign; read the results.
- EXPECTED: that contact is shown as skipped, with a short reason. The other two are sent. The skipped count is
  1 and the failed count is 0.

**D-3. Skip reasons are distinguishable and carry no personal data**
- PRECONDITIONS: four contacts, each unsendable for a different reason (no destination; ambiguous identity; no
  template parameters; template variables resolve to blank).
- ACTION: run the campaign; read the results.
- EXPECTED: four skipped recipients with reasons a reader can tell apart. No reason contains a phone number, a
  name, or any other contact detail.

**D-4. A contact in two audiences is addressed once**
- PRECONDITIONS: a campaign whose two labels both contain the same contact.
- ACTION: run the campaign.
- EXPECTED: exactly one recipient record for that contact.

**D-5. One failure does not stop the campaign**
- PRECONDITIONS: a campaign of 5 contacts where the second send is rejected by the provider.
- ACTION: run the campaign.
- EXPECTED: all 5 contacts have a recipient record; 4 sent, 1 failed; the campaign reaches completion.

**D-6. Delivery advances the record**
- PRECONDITIONS: a sent recipient.
- ACTION: a `delivered` report arrives for it.
- EXPECTED: the recipient reads as delivered, and the delivered count rises by one.

**D-7. Read-before-delivered ends as read, and still counts as delivered**
- PRECONDITIONS: a sent recipient.
- ACTION: a `read` report arrives, with no prior `delivered` report.
- EXPECTED: the recipient reads as read. The campaign's delivered count includes it — a message that was read
  reached the device.

**D-8. A late delivery report does not demote a read recipient**
- PRECONDITIONS: the recipient from D-7.
- ACTION: the `delivered` report arrives afterwards.
- EXPECTED: the recipient still reads as read. The delivered count does not double-count it.

**D-9. A repeated report changes nothing**
- PRECONDITIONS: a delivered recipient.
- ACTION: the same `delivered` report is delivered again.
- EXPECTED: the recipient is identical — same state, same timestamps. No count changes.

**D-10. A failure after a delivery does not erase the delivery**
- PRECONDITIONS: a delivered recipient.
- ACTION: a `failed` report arrives for it.
- EXPECTED: the delivery is preserved. The recipient is not counted as failed.

**D-11. A failure carries an actionable reason**
- PRECONDITIONS: a sent recipient.
- ACTION: a `failed` report with a provider error code and title arrives.
- EXPECTED: the recipient reads as failed; the recipient list shows a reason; the provider's code is visible
  alongside it.

**D-12. Concurrent reports resolve deterministically**
- PRECONDITIONS: a sent recipient.
- ACTION: a `delivered` and a `read` report for it are processed concurrently.
- EXPECTED: the recipient ends as read, whichever order the two finish in. Not sometimes delivered.

**D-13. The recipient list paginates and reports a filtered total**
- PRECONDITIONS: a campaign with 60 recipients in mixed states.
- ACTION: request page 2; then request only the failed ones.
- EXPECTED: page 2 holds one page's worth of rows and reports 60 as the total. The filtered request returns
  only failed rows and reports the failed count as the total, not 60.

**D-14. The counters agree with each other**
- PRECONDITIONS: the campaign from D-13.
- ACTION: read the campaign's totals and the per-state counts in the same response.
- EXPECTED: the per-state counts sum consistently with the audience total, and each state's count matches the
  number of rows the filtered list returns for that state.

**D-15. A running campaign is visibly running**
- PRECONDITIONS: a campaign mid-run, with some recipients not yet reported on.
- ACTION: read the campaign's totals.
- EXPECTED: the not-yet-attempted and awaiting-report counts are positive, so the interface can say the
  campaign is still processing.

**D-16. [isolation] Another account's campaign is unreachable**
- PRECONDITIONS: account B has a campaign with recipients.
- ACTION: admin of A requests that campaign's totals and its recipient list by its identifier.
- EXPECTED: `404` for both. No recipient of account B is returned.

**D-17. Recipient data does not leak into aggregates**
- PRECONDITIONS: recipients with distinctive names and phone numbers, some failed and some skipped.
- ACTION: read the account-wide campaign analytics (the cross-campaign view, not the per-campaign one).
- EXPECTED: no contact name, phone number or message body appears. Failure and skip groupings show codes and
  fixed reasons only.

**D-18. A deleted contact does not break the list**
- PRECONDITIONS: a campaign with 3 recipients; one contact is then deleted.
- ACTION: read the recipient list.
- EXPECTED: the list renders. The remaining recipients are present, and the response does not error.

**D-19. Re-running does not duplicate the snapshot**
- PRECONDITIONS: a campaign that has already produced recipients.
- ACTION: cause the run to be repeated (a retried job).
- EXPECTED: still one recipient per contact. No duplicate-key error surfaces to the operator.

---

## Section E — Delivery reports reaching the right record

**E-1. A conversation message still behaves as before**
- PRECONDITIONS: an agent reply sent through WhatsApp, in state sent.
- ACTION: a `delivered` report arrives for it.
- EXPECTED: the message shows as delivered in the conversation. No campaign recipient is touched.

**E-2. A campaign send is advanced although it has no conversation message**
- PRECONDITIONS: a campaign recipient in state sent, with no associated conversation message.
- ACTION: a `delivered` report arrives for it.
- EXPECTED: the recipient reads as delivered. No conversation, contact or message is created by the report.

**E-3. A report for an unknown identifier is harmless**
- PRECONDITIONS: nothing in the product carries the identifier in the report.
- ACTION: the report is delivered.
- EXPECTED: the webhook responds with success. Nothing is written. No error is logged and no exception is
  reported. (A webhook that fails here would be retried by the provider indefinitely.)

**E-4. A payload with several reports applies all of them**
- PRECONDITIONS: three campaign recipients in state sent.
- ACTION: one webhook payload arrives carrying a report for each.
- EXPECTED: all three advance.

**E-5. One unusable entry does not discard the others**
- PRECONDITIONS: as E-4, but the payload also contains an entry with a state the product does not know.
- ACTION: the payload is delivered.
- EXPECTED: the three known entries are applied; the unknown one is ignored; the webhook succeeds; no unknown
  state is stored.

**E-6. A repeated payload is a no-op**
- PRECONDITIONS: the payload from E-2, already applied.
- ACTION: deliver it again.
- EXPECTED: the recipient is byte-identical to its state after the first delivery.

**E-7. [isolation] A report cannot cross accounts**
- PRECONDITIONS: account A has a campaign recipient with a known provider identifier. Account B has its own
  WhatsApp inbox.
- ACTION: deliver a report carrying A's identifier, signed and routed for account B's number.
- EXPECTED: account A's recipient is unchanged.

**E-8. A rejected campaign send records the provider's own diagnosis**
- PRECONDITIONS: a campaign of 3 contacts; the provider rejects the second send with an error code and title.
- ACTION: run the campaign; read the recipient list.
- EXPECTED: that recipient reads as failed, with the provider's code and its title both visible. The first and
  third contacts were still attempted.

**E-9. A coexistence number needs no special case**
- PRECONDITIONS: a WhatsApp number connected through the business-app coexistence flow, and a campaign sent
  from it.
- ACTION: a `delivered` report arrives.
- EXPECTED: identical behaviour to E-2.

**E-10. A status payload creates nothing**
- PRECONDITIONS: a report whose identifier matches a campaign recipient.
- ACTION: deliver it.
- EXPECTED: no contact, conversation or message is created. The recipient count of the account's contacts is
  unchanged.

**E-11. Entrance guards are intact**
- PRECONDITIONS: a well-formed report payload.
- ACTION: deliver it (a) without a valid provider signature, (b) for a number marked inactive, (c) correctly.
- EXPECTED: (a) rejected, nothing written; (b) rejected, nothing written; (c) applied.

**E-12. A malformed payload does not 500**
- ACTION: deliver a payload with a missing identifier, then one with a missing state, then one that is not the
  expected shape at all.
- EXPECTED: each returns success or a clean client error. None returns a `500`, and none leaves a partially
  advanced record.

---

## Section F — Cross-package behaviour

**F-1. The five packages do not re-break each other's gates**
- PRECONDITIONS: an agent of account A holding every named permission the product defines.
- ACTION: that agent attempts: reading the trail; managing permission sets; reading another member's audit
  entries; reading a campaign's recipients.
- EXPECTED: the trail and set management are refused. Campaign results follow the campaign's own permission, not
  the audit permission.

**F-2. Campaign activity is auditable without campaign data leaking into the trail**
- PRECONDITIONS: a campaign that was created, edited and run.
- ACTION: read the trail.
- EXPECTED: whatever campaign-shaped entries the product records, no recipient phone number and no sent message
  body appears in the trail.

**F-3. Existing data keeps working**
- PRECONDITIONS: a database restored from a pre-rewrite backup, holding permission sets attached to members,
  campaign recipients in every state, and audit entries.
- ACTION: start the product; read the trail; list permission sets; read a campaign's results; sign in as a
  member with a set attached.
- EXPECTED: everything renders. No migration is required, no attachment is lost, and no recipient's state is
  reinterpreted. Rows written before the rewrite read the same as rows written after it.

**F-4. The two analytics views agree**
- PRECONDITIONS: one campaign with recipients in mixed states.
- ACTION: read the per-campaign totals, and the account-wide campaign analytics filtered to that campaign over
  a window containing it.
- EXPECTED: the sent, delivered, read, failed and skipped figures match between the two views.

**F-5. Nothing in the product references an absent dependency**
- ACTION: start the application and exercise each of the five areas.
- EXPECTED: no missing-constant, missing-file or missing-route error. Every page used above renders.

**F-6. The permission vocabulary is complete in the interface**
- PRECONDITIONS: each permission the product defines.
- ACTION: open the permission-set editor.
- EXPECTED: each permission is offered with a name and an explanation in the interface's language, and no raw
  internal identifier is shown to the user.

---

## Section G — Tenant isolation sweep

Run as one suite after everything else. For each row: create the same data in accounts A and B, authenticate as
account A, then attempt to reach account B's version through every parameter the surface accepts — identifier in
the path, identifier in the body, filter value, sort, page, and search term.

| # | surface | must be unreachable |
|---|---|---|
| G-1 | audit trail | any entry of account B |
| G-2 | permission sets | any set of account B, for read, update, delete or attachment |
| G-3 | member list and member update | any membership of account B |
| G-4 | campaign totals | any campaign of account B |
| G-5 | campaign recipient list | any recipient of account B |
| G-6 | account-wide campaign analytics | any recipient of account B, in any count, series or breakdown |
| G-7 | delivery report intake | any record of account B, via a report routed to account A |

EXPECTED, for all seven: a `404` or the product's standard refusal, and no field of account B's data in any
response body. A `403` that still includes the data is a failure. A `200` with an empty result is acceptable
where the surface is a list.

---

## What this plan does not cover

- Performance beyond A-17 and the query-count expectations stated in the specifications.
- The product's existing behaviour outside the five packages. That is covered by the test suite already in the
  workspace, which must continue to pass.
- Anything explicitly listed as a non-requirement in a package specification. If a scenario here seems to ask
  for one of those, the specification wins — report the contradiction rather than implementing it.
