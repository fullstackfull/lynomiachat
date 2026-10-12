---
title: The store address was refused
description: Why a store URL can be rejected before anything is sent, including the private-address and redirect rules that exist to protect your workspace.
position: 62
tags: [troubleshooting, commerce]
seo_description: "A Lynomia Chat commerce store showing INVALID_STORE_URL: the private-address, redirect and scheme rules that refuse an address, and what to enter instead."
---
This one is refused **before any request leaves Lynomia**, or as soon as the store answers with a redirect. It
applies to WooCommerce, which is the only platform where you type an address — Salla, Zid and Shopify provide
their own.

| What you see | Why |
|---|---|
| “That address is not a store we can reach” | the host resolves to a private, loopback, link-local or metadata address |
| “That address is not valid” | the address is not a usable `https` URL |
| “That store redirected us somewhere else” | the store answered a request with a 3xx |

## The private-address rule is deliberate, and it protects you

Every request to a store resolves the host first, refuses private, loopback, link-local and cloud-metadata
addresses, and then **pins the connection to the address it checked** — so nothing can answer the check with a
public address and then serve the request from somewhere internal.

This is why `http://localhost`, `http://192.168.x.x`, `http://10.x.x.x` and a `.local` hostname are all
refused. A store on your own machine or office network cannot be connected: it is not reachable from the
internet, and an address that *resolves* to somewhere internal is exactly the shape of request this rule
exists to refuse.

**Use the store's real public address**, the one a customer would type.

## Redirects are never followed

If your store answers on `https://shop.example.com` by redirecting to `https://www.shop.example.com`, the
redirect is refused rather than followed, and you will see the redirect message. **Enter the address the store
actually serves from** — the one you end up on after the redirect — and the problem goes away.

Not following redirects is on purpose: a followed redirect means the next request goes to a host nobody
checked.

## What to enter

- the scheme: `https`. An `http` store can be connected only where an administrator of this installation has
  explicitly listed the host as a development store;
- the host the store serves from, after any redirect;
- **no path**: not `/wp-json`, not `/wp-admin`, not a trailing page. The product adds the API path itself.

## If the address is right and it is still refused

Then it is not the address. A store that answers on the address you entered but refuses the request is a
connection or a permissions problem — see **Lynomia cannot reach your store** and **Your store keys cannot do
that**.
