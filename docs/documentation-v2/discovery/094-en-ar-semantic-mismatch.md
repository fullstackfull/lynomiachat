---
agent: 094
scope: Refute EN/AR equivalence across the 63-pair documentation corpus — prove where the Arabic says something different from the English
confidence: high
---

## 1. What you attacked

All 63 EN/AR pairs under `custom/db/documentation/{en,ar}/<section>/<key>.md`, compared on seven axes:
front matter fields, heading inventory and level, table rows, bullet and ordered-step counts, link
targets, numeric literals, and quoted UI labels. Quoted Arabic UI labels were then checked against the
product's own Arabic locale (`app/javascript/dashboard/i18n/locale/ar/*.json`), which is the only authority
on what an Arabic user actually sees. Two AR-only product claims were checked against the Ruby.

Three specific prior claims were attacked directly:

- Agent 031: `contacts.md` is 191 AR words against 1144 EN, read as a tokenization artefact.
- Agent 036: `automation-rules.md` is 211 against 1029, read the same way.
- Agent 057: `ar/workspace/roles-and-permissions.md:92` carries an AR-only claim that a custom role
  "cannot be reassigned" after a plan downgrade.

## 2. The extreme word-count question, settled

**Agents 031 and 036 reached the right conclusion from a wrong number, and the number is the one that got
written down.** The ratios are a `wc -w` locale artefact, not tokenization and not truncation:

```
$ LC_ALL=C      wc -w < ar/contacts/contacts.md   ->  191
$ LC_ALL=C.UTF-8 wc -w < ar/contacts/contacts.md   ->  923
$ python3 len(text.split())                        ->  923
```

This container runs `LC_CTYPE="POSIX"`. GNU `wc -w` in the C locale miscounts Arabic UTF-8; every Arabic
figure quoted in reports 031 and 036 — and any other report that used bare `wc -w` — is low by roughly a
factor of five. The giveaway was already in the data and went unremarked: **the Arabic files are *larger*
than the English in bytes** (`ar/contacts/contacts.md` 9138 bytes vs 6572), which is impossible for a file
holding one sixth of the words.

Recomputed over all 63 pairs with correct UTF-8 counting:

| metric | min | median | mean | max |
|---|---|---|---|---|
| AR words / EN words | 0.74 | 0.82 | 0.83 | 0.96 |
| AR chars / EN chars | 0.73 | 0.82 | 0.83 | 0.93 |

A 0.80–0.85 ratio is what a faithful Arabic translation of English prose looks like: Arabic attaches
articles, prepositions and pronouns as clitics, so it needs fewer whitespace-delimited tokens for the same
content. The word and character ratios track each other within 0.02 across the whole corpus, which is the
signature of uniform linguistic compression rather than of dropped content.

**Verdict on the two flagged pairs, as the brief demands, plainly:**

| pair | EN w | AR w | true ratio | verdict |
|---|---|---|---|---|
| `contacts/contacts.md` | 1148 | 923 | 0.80 | **faithful rendering** |
| `automation/automation-rules.md` | 1038 | 902 | 0.87 | **faithful rendering** |

Neither is condensed and neither is materially incomplete. `contacts.md` matches heading for heading (10/10),
table row for table row, and sentence for sentence through the intro, "How a contact comes to exist", "The
three identities" and "Phone numbers are stored in international form" — including the literal
`+96522201234` and `0551112233` examples and the fifteen-digit ceiling. `automation-rules.md` matches 11/11
headings. **The program's premise about Arabic being first-class survives on volume.** It does not survive
intact on accuracy — see §4.

Supporting evidence that the Arabic is genuinely authored rather than machine-padded: all 63 pairs have
**identical link-target multisets** (zero divergence), identical front-matter key sets, identical `position`
values and identical `tags` across all 63 pairs. The most-compressed pair in the corpus,
`troubleshooting/commerce-order-action-did-not-apply.md` at 0.74, is claim-for-claim complete — all nine
outcome rows, all nine machine codes (`ORDER_CHANGED`, `NOT_APPLIED`, `REFUND_DECLINED`, `PROVIDER_REJECTED`,
`ACTION_IN_PROGRESS`, `INVALID_AMOUNT`, `ACTIONS_DISABLED`, `ACTION_UNAVAILABLE`), all three numbered
read-back steps, all four closing bullets and the "four opportunities" count.

## 3. Quantified content parity

Word count was the wrong instrument. Structural and claim-level comparison is the right one:

| classification | pairs | share |
|---|---|---|
| Structure and emphasis counts identical, no substantive divergence found | 41 | 65% |
| Structure identical, emphasis count differs by 1–2 only | 14 | 22% |
| Structural divergence (headings, table rows, bullets, steps) | 8 | 13% |
| **Link targets divergent** | **0** | **0%** |

Collapsing that into a verdict per pair after claim-level review:

| verdict | pairs |
|---|---|
| FAITHFUL — no divergence found | 44 |
| REFORMATTED — content equivalent, presentation differs (prose↔list, section promotion) | 4 |
| DIVERGENT — at least one substantive divergence | 15 |

**Answer to the brief: the Arabic corpus is at parity in content volume and at parity in structure for 48 of
63 pairs, but 15 pairs carry substantive divergences, and the divergences are concentrated in exactly the
places where being wrong costs most — navigation paths in troubleshooting articles, the permissions matrix,
and the corpus's central domain term.** Parity of presence is not parity of meaning, and neither is parity
of length.

