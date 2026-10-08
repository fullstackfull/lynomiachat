# P7-A — Inbox and Conversations visibility

What this closes: conversations that exist but cannot be found, and a filter that hides them without
saying so or offering a way out.

## The five places the default lives

The Inbox opens on `status=open`. That default is set independently in five places, and all five agree:

| Site | Value |
| --- | --- |
| `app/finders/conversation_finder.rb:4` | `DEFAULT_STATUS = 'open'` — used by `filter_by_status` when the request carries no `status` |
| `app/javascript/dashboard/store/modules/conversations/index.js:15` | `chatStatusFilter: wootConstants.STATUS_TYPE.OPEN` |
| `app/javascript/dashboard/components/ChatList.vue:73` | `const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN)` |
| `app/javascript/dashboard/components/ChatList.vue` `setFiltersFromUISettings` | `status \|\| wootConstants.STATUS_TYPE.OPEN` — the saved preference wins, `open` is the fallback |
| `app/javascript/dashboard/components/widgets/conversation/ConversationBasicFilter.vue:36` | `chatStatusFilter.value \|\| wootConstants.STATUS_TYPE.OPEN` |

The dashboard always sends an explicit `status`, so the finder's default is reached only by direct API
consumers.

## What was actually wrong

1. **The one control that changes the status was behind a button labelled "Sort conversations."**
   `ConversationBasicFilter` renders a single `i-lucide-arrow-up-down` trigger whose tooltip and
   `aria-label` both read `CHAT_LIST.SORT_TOOLTIP_LABEL`. The panel it opens holds the status filter
   *and* the sort order. An agent looking for "show me resolved conversations" had no reason to open a
   sorting menu, so the status filter was discoverable only by accident.

2. **The chip that named the active status was decoration.** `ChatListHeader` already rendered a
   `WootLabel` reading "Open". It was not focusable, not clickable, and carried no hint that it was a
   filter rather than a heading.

3. **The empty state was a single dead end.** `CHAT_LIST.LIST.404` ("There are no active conversations in
   this group.") rendered identically whether the account had no conversations at all, or 400 resolved
   ones hidden by the default filter, or an advanced filter narrowing the list to nothing. It offered no
   action.

## What changed

- `ConversationBasicFilter` now labels its trigger for what the panel contains:
  `CHAT_LIST.FILTER_AND_SORT_TOOLTIP_LABEL` while the status filter is in it, and the original
  `CHAT_LIST.SORT_TOOLTIP_LABEL` when a folder or advanced filter has taken the status filter out of it.
  It also exposes `openDropdown()`.
- The header's status chip is now a `<button>` with a chevron, a tooltip
  (`CHAT_LIST.STATUS_FILTER.TOOLTIP`), an `aria-label` naming the current value
  (`CHAT_LIST.STATUS_FILTER.ARIA_LABEL`) and a visible focus ring. It opens that same panel, so the
  filter that is hiding conversations is also the way out of it, and there is still one status control
  rather than two.
- The empty state names its cause and carries the matching action
  (`CHAT_LIST.LIST.EMPTY.<key>`, decided by `conversationListEmptyStateKey`):

  | Cause | Title | Action |
  | --- | --- | --- |
  | `FOLDER` | No conversations in this folder | — (a folder is exited by its route) |
  | `FILTERED` | No conversations match these filters | Clear filters → `resetAndFetchData` |
  | `STATUS_FILTERED` | No conversations with this status | Show all conversations → `status=all` |
  | `NO_CONVERSATIONS` | No conversations yet | — |

- Applying a status or sort change, mirroring it into the store and persisting the saved pair now all
  happen in `ChatList.onBasicFilterChange`. Before, `ConversationBasicFilter` did the store dispatch and
  the `conversations_filter_by` write while `ChatList` held `activeStatus`; a second caller of
  `basicFilterChange` would have left the chip, the dropdown's own selection and the saved preference
  disagreeing. The empty state's "Show all conversations" is that second caller.

## What was deliberately not changed

- **`ConversationFinder::DEFAULT_STATUS` stays `'open'`.** The open queue is the agent's working queue.
  Defaulting the Inbox to `all` would bury live conversations under resolved history — worse for the
  primary workflow, not better — and would change the default response of a public API endpoint for every
  existing integration. The problem was that the filter was invisible and inescapable, not that `open` is
  the wrong default.

- **The assignee-tab counts stay scoped to the active status.** `ConversationFinder#perform` runs
  `set_up` (which applies `filter_by_status`) before `set_count_for_all_conversations`, so `all_count`
  means "all, within the current status". Making the counts pre-status would desynchronise them from the
  list they label: `ChatList.conversationListPagination` compares `activeAssigneeTabCount` against the
  rendered, status-filtered list to decide whether to re-request page 1, and `assigned_count` is derived
  as `all_count - unassigned_count`. With the status now named on a visible control directly above the
  tabs, "All: 12" reads unambiguously as "all, within Open".

- **The Arabic translation of the `open` status.** `ar/chatlist.json` renders
  `CHAT_STATUS_FILTER_ITEMS.open.TEXT` as "فتح" (the imperative verb "open!") rather than the state
  "مفتوحة". This is a Crowdin-managed string, so it is reported rather than edited here. The new empty-state
  copy was written so that nothing depends on it reading as an adjective: the status is interpolated as a
  named filter value ("The status filter is set to Open.") rather than inflected into the sentence.

## Still open, and where it belongs

**Conversations containing a failed message cannot be found from the list.** A send failure is visible
only inside the open conversation, via `components-next/message/MessageError.vue`. Nothing on the
conversation card marks it, and the conversation filter engine has no message-level attribute to filter
on: `lib/filters/filter_keys.yml` exposes 15 conversation attributes, all of them columns on
`conversations` or keys in its `additional_attributes`, and none of them reach `messages.status`.
Supporting it means a new attribute type in `Conversations::FilterService` that resolves to an
`EXISTS (SELECT 1 FROM messages WHERE ...)` subquery, plus the matching entry in `filter_keys.yml` and
`advancedFilterItems`. That is a feature, not a filter-visibility fix, and it is carried into the
WhatsApp failure UX work (P7-B) where failed sends are the subject.

## Coverage

- `app/javascript/dashboard/components/widgets/conversation/helpers/specs/emptyStateHelper.spec.js` —
  7 examples over the decision table, including each of the four non-`all` statuses and the two
  precedence cases (a folder outranks the filters it is built from; applied filters outrank the status).
- `app/javascript/dashboard/components/widgets/conversation/specs/ConversationBasicFilter.spec.js` —
  4 examples: the trigger label follows what is in the panel, `openDropdown()` opens it, and the
  component reports the choice without applying it.
- `app/javascript/dashboard/components/specs/ChatListHeader.spec.js` — 4 new examples: the chip names the
  active status, is a real button, calls `openDropdown()` on click, and is absent while a filter or folder
  is scoping the list.
