# Contacts phase B — feature parity

Phase B is a correctness fix, so the check is that it changed no control anywhere.

Both captures were taken with the same harness
(`docs/ui-modernization/harness/shoot.sh`), from two trees:

| | |
|---|---|
| before | `968aef48` — the commit immediately before phase B, checked out in a separate worktree |
| after | phase B's HEAD |

The baseline was re-captured rather than reusing `docs/ui-modernization/baseline/`, which dates from
`ad3eecff` — comparing against that one would show the whole UI/UX phase as well, and phase B's own diff
would be invisible in the noise.

## Result

```
before   surfaces: 68  captures: 544  controls: 5678
         unnamed controls: 0  horizontal overflow: 0  wrong direction: 0  page errors: 0
after    surfaces: 68  captures: 544  controls: 5678
         unnamed controls: 0  horizontal overflow: 0  wrong direction: 0  page errors: 0

parity   compared 544 captures
         lost 0   moved-with-reason 0   added 0   newly-named 0   regressions 0
```

Identical, which is what a correctness fix should look like. `parity.mjs` exits non-zero on a lost control, a
newly unnamed one, new overflow, a direction change or a new page error; it exited 0.

The five captured surfaces that render the components phase B changed — `contacts-header`,
`contacts-header-filter`, `audience-list`, `audience-list-adhoc` and `conversation-panel`, across two locales
and four widths — account for **40 captures and 832 controls, identical on both sides, with no capture
differing by even one control**.

## What a static capture cannot reach, and what covers it instead

The create dialog's new duplicate-recovery controls exist only after the server has rejected a create, which
a capture of a page at rest never produces. They are covered by
`components-next/Contacts/ContactsForm/specs/CreateNewContactDialog.spec.js` — both actions, and all three
cases where recovery is deliberately withheld (no contact found, two identity keys collided, a format
rejection rather than a duplicate).

The dialog itself is now exercised in a real browser too: journey **J11**
(`docs/ui-modernization/harness/journeys.mjs`) opens it from the contacts header against the harness's real
store and memory router, which is the only check that would catch a wiring mistake in the rewritten component
rather than a rendering difference. The ten pre-existing journeys cover no Contacts surface.

```
journeys: 44  checks: 264  failed: 0
J11 · 32 checks, 32 passed, in all four contexts (en/ar × desktop/390px)
     the dialog opens from 1 to 15 visible inputs, keeps its save and cancel controls,
     every control announces a name, no page error
```

`journeys.json` and `J11-*.png` in [`../journeys/`](../journeys/) are that run's own output. One thing the
first attempt got wrong, worth knowing before editing J11: this surface renders with the header's
more-actions menu **already open**, so clicking the trigger closes it. The journey clicks the menu item
directly.

## Re-running

```bash
git worktree add /tmp/pre-b 968aef48 && ln -s "$PWD/node_modules" /tmp/pre-b/node_modules
bash /tmp/pre-b/docs/ui-modernization/harness/shoot.sh /tmp/pre-b-captures
bash docs/ui-modernization/harness/shoot.sh /tmp/post-b-captures
node docs/ui-modernization/harness/parity.mjs /tmp/pre-b-captures /tmp/post-b-captures

CHROMIUM_PATH=/opt/pw-browsers/chromium-1194/chrome-linux/chrome \
PLAYWRIGHT_MODULE=/opt/node-tools/node_modules/playwright \
  node docs/ui-modernization/harness/journeys.mjs /tmp/journeys-b
```

`before-capture.log` and `after-capture.log` here are the two runs' own output.
