---
title: Documentation and support
description: You will know where this documentation comes from, why your workspace does not publish a help centre of its own, and where to get help when you need it.
position: 40
tags: [workspace, documentation, support]
seo_description: Lynomia Chat publishes and maintains its own documentation and changelog. Workspaces do not author a help centre; here is where to find help instead.
---
This documentation belongs to **Lynomia Chat**. The platform writes it, keeps it current and publishes it for every
workspace at once, in English and Arabic. Your account reads it; it does not write it.

That is deliberate. One documentation set means one answer to every question, the same answer for everyone, updated
the day the product changes.

## Your workspace does not publish a help centre

Lynomia Chat does **not** give a workspace its own public help centre to author. There is no Help Center section in
the sidebar, no portal to create, no categories or articles of your own, and no public site under your own domain.
The same is true through the API: the portal, category and article endpoints refuse a workspace request.

If your workspace published one before this change, nothing of yours was deleted and the pages your customers
already have links to are still online. What you can no longer do is edit them, add to them or take them down from
here. Ask whoever administers your installation if you need a page changed or removed.

## What to do instead

| You want to | Do this |
|---|---|
| Answer the same question again and again | Write a [canned response](canned-responses) and insert it in one keystroke |
| Hand a customer something to read | Link to a page on your own website, or paste the answer |
| Tell your own team how you work | Use a [macro](macros) for the steps, and your own internal wiki for the prose |
| Automate the answer entirely | Build an [automation rule](automation-rules) or a [flow](flow-builder) |

A canned response is the closest thing to a help centre article for day-to-day work: it is written once, searched
from the reply box with `/`, and it carries variables so the customer's name and order number fill themselves in.

## Where to find help

| | Where |
|---|---|
| **Documentation** | the pages you are reading. **Help & Support → Documentation** in the sidebar, or `/docs` |
| **Changelog** | what changed in each release, at `/changelog` |
| **Support** | **Help & Support → Contact Support** in the sidebar |

Both open in a new tab, and both are configured by whoever runs your installation, so a self-hosted install points
at its own addresses.

## A note on roles

A custom role no longer offers a **Manage knowledge base** permission, because there is no workspace knowledge base
to manage. A role created before this change keeps the permission on its record, where it now grants nothing — you
can leave it or edit the role to drop it, and either way it changes nothing about what that person can do. See
[Roles and permissions](roles-and-permissions).

## Related

- [Canned responses](canned-responses)
- [Macros](macros)
- [Roles and permissions](roles-and-permissions)

## If it does not work

**The Documentation or Contact support link is missing.** The installation has not configured an address for it.
Ask whoever administers your installation.

**I want to edit an article my workspace published before.** You cannot, from here. The page itself is still
online for your customers, but editing, adding and removing are administrator work on the installation now.
