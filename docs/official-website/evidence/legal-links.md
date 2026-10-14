# Legal link verification

Checked 2026-10-14 16:52 UTC from the session container against the live hosts.
Each of the four URLs the marketing footer links is fetched, followed through redirects, and measured.

| URL | HTTP | Bytes | Words | <title> |
|---|---|---|---|---|
| `https://lynomia.com/about_us` | 200 | 7570 | 461 | (none) |
| `https://lynomia.com/privacy` | 200 | 16886 | 1346 | Privacy Policy — Lynomia |
| `https://lynomia.com/terms` | 200 | 18266 | 1473 | Terms of Service — Lynomia |
| `https://lynomia.com/user-data-deletion` | 200 | 10703 | 744 | User Data Deletion — Lynomia |

**Verdict: all four are real, published documents on the operator's own domain**, not placeholders and not
text invented inside this application. The privacy policy, terms of service and data-deletion pages each
carry a matching `<title>` and over seven hundred words of substantive content.

`about_us` returns no `<title>` element. That is a defect on lynomia.com, not on this site, and it does not
affect the link: the page returns 200 with 461 words of real content. It is recorded here because a missing
title is worth the operator's attention.

**What this does NOT establish.** Whether those documents' text adequately covers the Lynomia Chat product
specifically -- data processing, sub-processors, retention, the jurisdictions it operates in -- is a legal
judgement for the operator and their counsel, not something a fetch can answer. This application links the
documents; it does not author, summarise or restate them, and the earlier version of the marketing page that
carried policy text inside a JavaScript string has been removed
(docs/official-website/hotfix/build.py, `remove_legal_modal`).
