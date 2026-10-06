# 04 — The abandoned-cart starter recipe

## 1. What it creates

| | |
|---|---|
| id | `commerce_abandoned_cart_template` |
| trigger | `commerce_cart_abandoned` |
| condition | the store the user chose (`eventStore`) |
| action | `send_whatsapp_template`, and only that |
| user input | the Zid store |
| created | **disabled** (`active: false`) |
| provider note | shown in the chooser: only Zid reports abandoned carts, and cart ingestion is still PRE_UAT |

## 2. Why the action ships empty, and why that is safe

The recipe creates the action with **no** inbox, template or mapping. The person finishes it in the rule editor,
where `AutomationActionWhatsappTemplateInput` lives.

That is deliberate. The alternative was a template selector inside the recipe wizard — a second configuration
surface for the same thing, which the brief forbids and which would have duplicated the template rules.

It is safe because of a change in `Custom::AutomationRule#template_action_configured`: it validates **only an
active rule**. A disabled rule is a draft; an active one must be complete. So the empty action:

- cannot run, because the rule is disabled;
- cannot be switched on, because activation runs the validation and is refused with the missing keys named;
- is completed in the one place that has the real control.

An incomplete draft therefore never sends and never silently does nothing — the two failure modes this project
keeps closing.

## 3. Zid only, and PRE_UAT

Only Zid reports abandoned carts to Lynomia (`docs/commerce-production/08`), so the recipe names Zid in its
provider note rather than pretending to be provider-neutral.

Even once a person configures and enables the rule, **nothing fires yet**: `Commerce::CartLifecycle#ingestible?`
asks `Commerce::AbandonedCarts.offered?`, and Zid cart ingestion is PRE_UAT, released only by the ENV-only
`COMMERCE_ALLOW_PRE_UAT_PROVIDERS`. The recipe does not touch that gate and cannot.

So the recipe is shippable now and inert now, which is the point: the configuration work can be done and reviewed
before a real Zid store ever exists.

## 4. What the user must choose

| Chosen in | What |
|---|---|
| the recipe wizard | the Zid store |
| the rule editor | the WhatsApp inbox, the approved template, its language (part of the template's identity), the variable mapping |
| the server, deliberately | the PRE_UAT gate, before any of it can fire |

## 5. Terminology

The recipe's copy says *abandoned* and *send a template*. It does not say recovered, recovery rate or recovered
revenue, and the trigger it uses is the only cart trigger that exists — `commerce_cart_recovered` was refused in
P6 because completion does not prove Lynomia caused it.
