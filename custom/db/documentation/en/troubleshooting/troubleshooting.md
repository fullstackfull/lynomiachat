---
title: When something is not working
description: You will be able to place almost any problem into one of four causes within a minute, and know which article explains the rest.
position: 10
tags: [troubleshooting]
seo_description: "Find the cause of a Lynomia Chat problem fast: role, plan, Meta, or configuration — with the first thing to check for each symptom."
---
Most reports fall into four causes. Working out which one you are looking at is faster than reading about the
feature, and it is usually enough.

| Cause | What it looks like |
|---|---|
| **A role** | the page or button is missing entirely, for you but not for a colleague |
| **A plan or an installation switch** | the page is missing for everyone, including administrators |
| **Meta** | WhatsApp refused something, and the product is reporting that refusal |
| **Configuration** | the feature is there, you used it, and the result was not what you expected |

## Start with who you are

More "it is broken" reports are a role than anything else. An agent sees only the inboxes they are a collaborator
on, and no settings at all. A custom role sees only what it was granted, and the permission list is shorter than
people assume — it has no entry for inboxes, channels, campaigns, WhatsApp templates, flows, automation rules or
audiences. [Roles and permissions](roles-and-permissions) has the exact list.

If a colleague who is an administrator also cannot see it, stop looking at roles. It is a plan or an
installation-level switch, and nothing in your account changes those.

## Then find your symptom

| Symptom | First thing to check | Where it is explained |
|---|---|---|
| No WhatsApp messages are arriving | the inbox's **Account Health** tab | [when WhatsApp does not work](whatsapp-troubleshooting) |
| I cannot type a reply, only send a template | when the customer last wrote | [the 24-hour window](the-whatsapp-24-hour-window) |
| A template was rejected or paused | the rejection reason on the template | [the template lifecycle](whatsapp-template-lifecycle) |
| A campaign says Completed but nobody got it | whether the template is still APPROVED | [WhatsApp campaigns](whatsapp-campaigns) |
| My template is missing from the campaign dropdown | its status, category and components | [WhatsApp templates](whatsapp-templates) |
| A conversation is not in my list | the status filter, then your inbox membership | [work in the inbox](work-in-the-inbox) |
| An agent cannot see an inbox's conversations | the inbox's Collaborators tab | [set up an inbox](set-up-an-inbox) |
| An automation rule did nothing | that the rule is switched on | [automation rules](automation-rules) |
| A flow never started | that it is published, on a WhatsApp Cloud inbox | [flow builder](flow-builder) |
| An import skipped every row | labels that do not exist, or missing country | [import contacts](import-contacts) |
| An audience matches nobody | whether your labels are on contacts or conversations | [labels or shared audiences?](labels-or-shared-audiences) |
| Orders are not showing beside a conversation | whether the contact matched a store customer | [Customer 360](customer-360) |
| An order action I need is not offered | the per-platform table | [what each platform supports](commerce-provider-support) |
| My endpoint is not receiving events | that the URL is publicly reachable | [webhooks](webhooks) |
| I cannot find out who changed a setting | whether that action is audited at all | [audit logs](audit-logs) |

## What leaves a trail, and what does not

Before you spend an hour looking for a log, this is what exists.

| Area | What you can inspect afterwards |
|---|---|
| Campaigns | per-recipient outcomes, with a reason, where your installation has campaign analytics |
| Flows | **Sessions** on the flow: where each run ended and why |
| WhatsApp | the inbox's Account Health, and each failed message's own reason |
| Configuration changes | [audit logs](audit-logs), for the fourteen event types it covers |
| Automation rules | **nothing.** There is no run history and no per-rule log in the product |
| Webhooks | **nothing.** No delivery log, no retry, no replay |
| Imports | the import's own result counts |

Where the answer is "nothing", the practical approach is to reproduce the trigger deliberately and watch what
happens, rather than to search for a record of the first time.

## Four things no amount of configuration fixes

- **Meta owns template verdicts, quality ratings, messaging limits and display-name decisions.** The product
  reports them. It cannot appeal or override them.
- **Messages sent to a WhatsApp number while its webhook was missing are gone.** There is no backfill.
- **Out-of-hours behaviour cannot be built with automation.** There is no business-hours, time-of-day or
  working-hours condition. An inbox's own business hours and unavailable message are the tool for that — see
  [set up an inbox](set-up-an-inbox).
- **Refunds and cancellations cannot be delegated** to a custom role, on any platform.

## Who can do this

Agents can see most symptoms but almost none of the causes: Account Health, inbox configuration, templates,
campaigns, automation and audit logs are administrator-only. If you are an agent, your useful contribution is a
precise symptom — which conversation, which number, what time — and then escalating.

## Related

- [When WhatsApp does not work](whatsapp-troubleshooting)
- [Roles and permissions](roles-and-permissions) · [Set up an inbox](set-up-an-inbox)
- [Audit logs](audit-logs) · [Webhooks](webhooks)
- [WhatsApp campaigns](whatsapp-campaigns) · [Automation rules](automation-rules) ·
  [Flow builder](flow-builder)
- [What each platform supports](commerce-provider-support)
