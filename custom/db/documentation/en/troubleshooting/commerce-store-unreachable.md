---
title: Lynomia cannot reach your store
description: What a timeout or “store unavailable” means, why the panel still shows something, and what to check on your own hosting.
position: 61
tags: [troubleshooting, commerce]
seo_description: "A Lynomia Chat commerce panel showing STORE_UNAVAILABLE or TIMEOUT: what the product tried, what it falls back to, and what to check on your store's hosting."
---
This is a **connection** problem, not an authorization one. The access is fine; the store did not answer in
time, or did not answer at all.

| What you see | The code behind it | What it means precisely |
|---|---|---|
| “Your store did not answer” | `STORE_UNAVAILABLE` | the connection failed, or the store returned a 5xx |
| “Your store took too long to answer” | `TIMEOUT` | the request was sent and no answer arrived inside the limit |

## What the product does about it, without being asked

- **It waits a bounded amount of time.** Three seconds to connect, eight seconds for an answer, and ten seconds
  for the whole body. A slow store costs one timeout, never a hung page.
- **It retries once, and only for a read.** A dropped connection or a 502, 503 or 504 on a read is tried again
  once. A timeout is **not** retried, so a slow store cannot be made slower by us. An order action is **never**
  retried, because sending a refund twice is worse than reporting one failure.
- **It shows you what it already has.** If the panel can serve cached order history it will, labelled with when
  it was last updated. A panel that says “last updated 40 minutes ago” is telling you the truth rather than
  pretending to be live.
- **It does not change the store's status.** A store that cannot be reached stays `active`, because being
  temporarily unreachable is not the same as having lost its authorization.

## What to check, in order

1. **Open the store yourself**, in a browser, from a normal internet connection. If it is slow or down for you,
   it is slow or down for us.
2. **WooCommerce only: check that the store is reachable from the public internet.** A store behind a VPN, on a
   private network, or on a `localhost` address cannot be reached by anything outside it, and the product
   refuses to try — see **The store address was refused**.
3. **Check your hosting for rate limiting or a firewall rule.** A host that blocks or throttles unfamiliar
   traffic will refuse us consistently while a browser works, which is the pattern that looks most like a
   product bug and is not one.
4. **Check whether it is only slow under load.** A store that answers in twelve seconds is working, from its
   own point of view, and will time out here every time. That one needs the hosting fixed, not the connection.

## When it clears up

Nothing needs to be done. The next successful request serves live data again, and the panel stops saying it is
stale. There is no cache to clear by hand.
