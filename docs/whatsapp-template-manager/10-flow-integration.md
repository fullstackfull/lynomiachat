# 10 — Flow integration

What the flow builder already did right, and what this phase therefore did not touch. The selection rule itself is in
`09-campaign-integration.md §1`; it is one implementation shared by both.

---

## 1. What changed for flows: nothing

Nothing. `TemplateEditor.vue` already keyed on `name|language`, already filtered through the shared rule, and
`Flows::TemplateValidator` already refuses to publish a flow whose connected inbox cannot send the chosen template —
which is the "prevent an invalid publish rather than fail at run time" the brief asks for, and it predates this phase.
There is no flow-specific template store, and none was added.

## 2. The existing sender, unchanged

`Flows::Nodes::SendTemplate` and the message it builds are untouched. A flow still sends through
`Whatsapp::SendOnWhatsappService` and the provider service beneath it — the same path the composer and campaigns use.
This phase added nothing between a flow and the provider, and removed nothing from it.

What did change, for flows as for everything else, is that the shared processor now refuses a template WhatsApp has
not approved (`09-campaign-integration.md §1`). A flow that somehow reached a send with an unapproved template used to
send it with no parameters; it now sends nothing.

## 3. Draft preservation

Not applicable, and deliberately so. The flow builder's template node picks from the templates an inbox already has;
it has no "create a template" affordance, so there is no round trip out of an unsaved flow to preserve. Adding one
would mean either a second template builder inside the flow canvas or a navigation away from an unsaved flow — the
first duplicates this phase's builder, the second is the draft loss the brief warns about. The manager is one click
away in Settings, and a flow is unaffected by what happens there.

