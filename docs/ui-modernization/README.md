# UI/UX Visual Modernization — Phase 1

Everything this phase produced, and how to re-run every check it is measured by.

## Read this first

| | |
|---|---|
| [`FINAL-CHECKPOINT.md`](FINAL-CHECKPOINT.md) | the 42-item close: branch, commits, every result, every limitation, the three confirmations |

## What the phase decided before it changed anything

| | |
|---|---|
| [`00-existing-design-system.md`](00-existing-design-system.md) | what the product already had: tokens, ramps, typography utilities, the two component layers |
| [`01-product-visual-audit.md`](01-product-visual-audit.md) | the product-wide visual audit across 22 surfaces |
| [`02-design-principles.md`](02-design-principles.md) | the principles this phase works to, including what Phase 3 deliberately does **not** do |
| [`03-token-normalization.md`](03-token-normalization.md) | the spacing, radius, elevation, control-height and z-index scales added |
| [`04-status-vocabulary.md`](04-status-vocabulary.md) | one tone per meaning, replacing hand-written chips |

## Per-surface manifests

`audit/` holds a read-only inventory **per surface, written before that surface was touched** — every
control, action, menu item, filter, tab, status, shortcut, bulk action, permission-gated action, mobile
affordance, cross-module link and empty/loading/error state, each with `file:line`. Eleven surface files
and nine system files. A redesign is checked against these.

## What changed, and how it was proved

| | |
|---|---|
| [`parity/conversation-workspace.md`](parity/conversation-workspace.md) | 124 manifest features, 124 preserved |
| [`parity/settings.md`](parity/settings.md) | the ten settings surfaces that had never been captured, and what their first capture found |
| [`parity/sweeps.md`](parity/sweeps.md) | the responsive, RTL and accessibility sweeps — what each looked for, found, fixed and left |

## Evidence

| | |
|---|---|
| `baseline/` | 272 screenshots + a 544-capture control inventory from the pre-phase commit `ad3eecff` |
| `after/` | the same 544 captures from the phase's final tree, under the same filenames, plus the gate's output |
| `journeys/` | ten named browser journeys, run in two locales at two sizes — results and screenshots |

## What was found and not done

| | |
|---|---|
| [`findings/deferred.md`](findings/deferred.md) | 19 entries: visual work left, capability gaps found but not implemented, and five correctness defects found while reading |
| [`findings/unnamed-controls-remaining.md`](findings/unnamed-controls-remaining.md) | the controls still named only by a tooltip, and why naming them has to wait for a capture |
| [`findings/command-failures.md`](findings/command-failures.md) | every command in the session that did not exit 0, classified |

## Re-running the checks

```bash
# capture the current tree and diff it against the pre-phase baseline
bash docs/ui-modernization/harness/shoot.sh docs/ui-modernization/after
node docs/ui-modernization/harness/parity.mjs \
  docs/ui-modernization/baseline docs/ui-modernization/after

# the ten browser journeys, English and Arabic, desktop and 390px
CHROMIUM_PATH=/opt/pw-browsers/chromium-1194/chrome-linux/chrome \
PLAYWRIGHT_MODULE=/opt/node-tools/node_modules/playwright \
  node docs/ui-modernization/harness/journeys.mjs docs/ui-modernization/journeys

# the rest
pnpm test
pnpm eslint
pnpm vite build
```

The gate exits non-zero on a lost control, a newly unnamed one, new overflow, a direction change or a new
page error. A control that genuinely moved is declared in `harness/parity-exceptions.json` with where it
went and why — moving a feature is allowed, losing one is not, and the difference has to be written down.

`harness/README.md` explains how the harness mounts the real components without a Rails server, and the
two things worth knowing before changing it.
