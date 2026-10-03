# Flow templates

Six templates. Each builds the graph of a normal flow bot — `AgentBot(bot_type: :flow)` with one draft
`FlowVersion` — and nothing else. Architecture in [10](10-recipe-architecture.md); why these six and not the brief's
seven in [09a](09a-recipe-opportunity-study.md) §4.1 and §7.

## 1. What they are allowed to contain

Fixed by the backend, not by this catalogue:

- the 21 node types of `Flows::NodeTypes::TYPES`, their outputs, which outputs **must** be connected, and each
  node's allowed `data` keys;
- `Flows::ChannelCapabilities::WHATSAPP`: text ≤ 4096, interactive body ≤ 1024, **buttons ≤ 3 with titles ≤ 20
  characters**, list ≤ 10 rows;
- `Flows::NodeValidator`: every team, label, audience and attribute must be this account's, every variable on
  `Flows::Variables`' allow-list, timeouts 1–1440 minutes;
- `Flows::GraphValidator`: one Start with nothing leading into it, one edge per output, every required output
  connected, every node reachable, and no cycle that runs without a node that waits.

An **optional** output left unconnected hands the conversation to humans when the runner takes it. That is a safe
default, so the templates leave `other` unconnected on purpose: an unrecognised reply re-sends the menu twice
(`Flows::Nodes::Choice::MAX_REPEATS`) and then goes to a person.

## 2. The six

### 2.1 `commerce_order_tracking` — Order tracking bot

Needs Flow Builder, Commerce, a team. Asks for: team, language. **12 nodes, 19 edges.**

```text
Start → Buttons "Track my order" / "Talk to the team"
          ├─ track  → Commerce Lookup (latest order)
          │             ├─ found       → "Your most recent order is #… and its status is …"
          │             │                 → Buttons "That's all" / "Talk to the team"
          │             │                     ├─ done       → goodbye → End (resolved)
          │             │                     ├─ more_help  → Handoff
          │             │                     └─ timeout    → goodbye → End (resolved)
          │             ├─ not_found   → Question "Send us the order number"
          │             │                 ├─ reply   → Commerce Lookup (that number)
          │             │                 │             ├─ found       → "Order #… is …" → the same Buttons
          │             │                 │             ├─ not_found   → "We could not find that" → Handoff
          │             │                 │             └─ unavailable → Handoff
          │             │                 └─ timeout → Handoff
          │             └─ unavailable → Handoff
          ├─ agent   → Handoff
          └─ timeout → Handoff
```

The second lookup takes the number from `{{flow.order_number}}`, the value the Question stored in the run's context —
not from free text, and the allow-list is what permits it. Both lookups are `Flows::Nodes::CommerceLookup`, which
reads the **contact's own** orders through `Commerce::Customer360`: a guessed number belonging to someone else is
simply not found.

### 2.2 `commerce_after_sales` — Order issue intake

Needs Flow Builder, Commerce, a team. Asks for: team, labels (optional), language. **10 nodes, 12 edges.**

```text
Start → Question "Send us the number of the order you need help with"
          ├─ reply   → Commerce Lookup (that number)
          │             ├─ found       → "We found order #…" → Buttons "Wrong item" / "Damaged" / "Late delivery"
          │             │                   → a Handoff per answer, each with its own private note for the agents
          │             ├─ not_found   → "We could not find that, and we will help anyway" → Handoff
          │             └─ unavailable → Handoff
          └─ timeout → Handoff
```

The issue the customer chose reaches the agents as the handoff's **private note**, which is what
`Flows::Nodes::Handoff` does with `reason`. Chosen labels go on every issue handoff; no label chosen adds no label.

### 2.3 `support_department_routing` — Department routing bot

Needs Flow Builder, a team. Asks for: three teams, language. **8 nodes, 8 edges.**

```text
Start → Buttons "Orders" / "Products" / "Something else"
          → an acknowledgement per branch → a Handoff per branch, each to the team mapped to it
```

### 2.4 `vip_priority_routing` — VIP priority routing

Needs Flow Builder, a shared audience, a team. Asks for: audience, VIP team, standard team, language.
**6 nodes, 5 edges.**

```text
Start → Audience Condition (is in <audience>)
          ├─ true  → "We are connecting you to our dedicated team" → Handoff to the VIP team
          └─ false → "Someone will reply shortly"                  → Handoff to the standard team
```

The condition is a `contact_audience` condition, which `Flows::NodeValidator` restricts to **shared** audiences of
this account. A personal filter cannot be used, by the engine's own rule.

### 2.5 `bilingual_welcome` — Arabic or English welcome

Needs Flow Builder, a team. Asks for: Arabic team, English team. **6 nodes, 6 edges.**

```text
Start → Buttons "العربية" / "English"
          ├─ arabic  → an Arabic acknowledgement  → Handoff to the Arabic team
          ├─ english → an English acknowledgement → Handoff to the English team
          └─ timeout → Handoff to the Arabic team
```

A deterministic choice. **No language detection, and no AI.** The team the customer lands in is what carries the
language onward.

### 2.6 `whatsapp_welcome_menu` — Welcome and collect the request

Needs Flow Builder, a team. Asks for: team, language. **4 nodes, 4 edges.** The starter for an account with no
Commerce.

```text
Start → Question "Tell us briefly what you need"
          ├─ reply   → "Someone will reply here shortly" → Handoff
          └─ timeout → Handoff
```

The customer's own message is the message above the handoff note, so the agent opens a conversation that already
says what it is about.

## 3. Arabic and English

`starterCopy.js` holds every string in both languages, written by hand. **Nothing is machine-translated.**

- **Message bodies**: Arabic only, English only, or "both", which sends the Arabic line and the English line in one
  message.
- **Option titles**: WhatsApp allows 20 characters on a button, so "both" uses its own short wording
  (`تتبع الطلب / Track`, `الطلبات / Orders`) rather than two titles joined. Every title at every language is
  asserted against the limit in the specs.

One honest limitation: `{{flow.order.status}}` renders Commerce's **normalized** status value (`shipped`,
`delivered`), which is a machine identifier, not a localized word. An Arabic message therefore carries an English
status until the merchant edits the wording — which they can, before publishing. Localising those values is a
Commerce concern, not a template one, and is recorded in [08](08-deferred-ui-visual-improvements.md).

## 4. How they are checked

`recipes/specs/flowTemplates.spec.js` transcribes the backend's contracts and runs **every template at every
language** against them: shape and key sets, one Start with nothing leading into it, one edge per output, every
required output connected, every node reachable, no cycle without a wait, every text and option title inside the
channel's limits, every variable on the allow-list, reply types, lookup modes, timeouts, priorities, condition
counts and query operators — and that no id appears that the wizard was not given.

A template that the server would refuse at publish fails there first. 37 assertions across the three languages.
