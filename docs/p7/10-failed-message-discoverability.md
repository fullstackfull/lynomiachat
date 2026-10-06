# P7-H — Making a conversation with a failed message findable

This was the open item. It is closed: `message_status` is a conversation filter, on both filter surfaces, with
the SQL to back it and the gates to keep it honest.

## The problem, precisely

A reply that WhatsApp refused is recorded on the **message** — `messages.status = failed`, with the provider's
own words in `external_error`. The conversation carries nothing that reflects it. Its `status` is still `open`,
its `last_activity_at` moved when the failed message was created, and in the conversation list it looks exactly
like every other conversation.

So the failure was discoverable in precisely one way: already knowing which customer it was. If the agent who
sent it had moved on, the usual way to find out was the customer asking again. There is no notification on a
failed message, and there was no query that could ask for one.

## What was added

One attribute, `message_status`, which asks whether a conversation **contains** a message with a given delivery
status.

```sql
EXISTS (
  SELECT 1 FROM messages
   WHERE messages.conversation_id = conversations.id
     AND messages.status IN (:value)
)
```

`NOT EXISTS` for `not_equal_to`. Three decisions in that query are deliberate:

- **Correlated, not a join.** A conversation with three failed messages would be returned three times by a join,
  which duplicates rows *and* makes `all_count` wrong. A spec asserts a conversation with two failures appears
  once and the count is 2.
- **Bounded by `conversations.id`**, which is the leading column of
  `index_messages_on_conversation_account_type_created`, so each candidate conversation costs an index lookup.
  No migration was needed.
- **`IN` over a mapped enum.** The name is mapped through `Message.statuses`, and an unknown name becomes `nil`,
  so a filter naming a status this version does not have compiles to `IN (NULL)` and matches **nothing**.
  Matching everything would have been a silent lie.

## Where it lives, and why not in the shared helper

The obvious place was `Filters::FilterHelper`, beside the `labels` branch. It went into
`Conversations::FilterService` instead, overriding `handle_standard_attributes` and `filter_values`:

- `message_status` is meaningless for a contact filter, and the helper is shared with `Contacts::FilterService`.
  A contact payload naming it now falls through to the custom-attribute path and is refused as an invalid
  attribute, which is correct.
- It follows the precedent already in the tree: `tag_filter_query` lives in `FilterService` rather than the
  helper, because it assigns `@filter_values` — and `Rails/HelperInstanceVariable` is the cop that says so.
- Both the helper and the base service were already at their RuboCop length limits. Discovering that is what
  prompted re-reading where the existing `labels` query actually lives, which turned out to be the better
  answer rather than a workaround.

## Validation at the boundary

`message_status` joins `status` and `priority` in `STRING_VALUE_ATTRIBUTES`, so a payload whose values are not
strings is refused as `InvalidValue` before it reaches the query. `filter_keys.yml` allows only `equal_to` and
`not_equal_to`, so anything else is refused as `InvalidOperator`. Both are 422s through the existing error path;
nothing new was invented for them.

## Both filter surfaces

The product has two: the legacy `advancedFilterItems` registry and the newer `components-next/filter` provider.
A filter in one and not the other is a filter half the product cannot reach, so it is registered in both as a
multi-select with the four delivery statuses, named **Message delivery**, with *Failed to send* listed first
because it is the reason anyone opens this.

`customViewsHelper` needed one line too: `message_status` resolves its saved values the way `status` does, so a
**saved folder** reopened for editing gets back every value it stored rather than only the first. That is what
makes the queue reusable — set the filter once, save it, and it is one click from then on.

## The working-queue default is untouched

The brief was explicit: do not change `ConversationFinder`'s default status. It is unchanged. Open is still the
working queue, and this filter is something an administrator or agent applies on top of it — which is also why
the documentation suggests combining it with *Status is Open* rather than replacing the default.

## Proven against the database

Ten examples in `spec/services/conversations/filter_service_message_status_spec.rb`, plus a direct probe against
Postgres before the spec was written:

| Case | Result |
| --- | --- |
| `equal_to failed` | the two conversations containing a failed message |
| a conversation with two failures | returned once; `all_count` is 2 |
| `not_equal_to failed` | the delivered-only conversation **and** the one with no messages at all |
| `equal_to [failed, delivered]` | the union of both |
| `equal_to` an unknown status name | empty, not everything |
| combined with `status equal_to open` via `AND` | only the open one |
| `contains` | `InvalidOperator` |
| a Hash as a value | `InvalidValue` |
| the same filter run as another account's administrator | only that account's conversation |

## Gates

| Gate | Result |
| --- | --- |
| `filter_service_message_status_spec.rb` | 10 examples, 0 failures |
| the existing conversation, frontend-alignment and contact filter suites | 83 examples, 0 failures |
| `customViewsHelper.spec.js`, `filterHelper.spec.js` | 47 tests, including four new registration and saved-folder gates |
| `rubocop` on the helper, the base service and `Conversations::FilterService` | no offenses |
| eslint / prettier on all five touched JS files | clean (pre-existing `no-dynamic-keys` warnings only) |
| documentation corpus | 289 examples, 0 failures after rewriting the two articles |

## What it does not claim

- **A conversation whose failure was retried successfully still matches.** The original failed message is still
  in the thread, so the filter answers "something failed here", not "something is still broken here". Both
  locales of the article say so.
- **Nothing is notified.** The filter is something a person has to look at; no alert was added, and the
  documentation does not imply one.
- **No count badge, no default folder.** A saved folder is one click, but nobody is nudged toward it. Adding a
  shipped folder to every account is a product decision rather than a gap, and it is not made here.
