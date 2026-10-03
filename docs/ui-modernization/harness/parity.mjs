// Feature-parity diff between two harness captures.
//
//   node docs/ui-modernization/harness/parity.mjs <before-dir> <after-dir> [--json <out>]
//
// This is the mechanism behind "no capability may disappear". It compares the control inventories
// captured at four widths in two locales and fails on anything lost, newly hidden, newly unnamed, or
// newly broken. A control that genuinely moved is declared in `parity-exceptions.json` with a reason —
// moving a feature is allowed, losing one is not, and the difference has to be written down.
import { readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const [beforeDir, afterDir] = process.argv.slice(2).filter(arg => !arg.startsWith('--'));
if (!beforeDir || !afterDir) {
  console.error('usage: parity.mjs <before-dir> <after-dir> [--json <out>]');
  process.exit(2);
}
const jsonFlag = process.argv.indexOf('--json');
const jsonOut = jsonFlag === -1 ? null : process.argv[jsonFlag + 1];

const read = async dir => JSON.parse(await readFile(join(dir, 'inventory.json'), 'utf8'));

// Matching a before-control to an after-control. Four passes, strongest signal first, each pass
// consuming what it matches. One key alone is not enough: an unnamed icon button that *gains* an
// accessible name — the single most common improvement in this phase — would look like a loss and an
// unrelated addition if identity were a single string. Matching on the icon in a later pass keeps it
// recognisably the same control.
const KEYS = [
  control => (control.testId ? `testId:${control.testId}` : null),
  control => (control.name ? `name:${control.tag}:${control.name.toLowerCase()}` : null),
  control => (control.icon ? `icon:${control.tag}:${control.icon}` : null),
  control => `anon:${control.tag}:${control.role}:${control.type}`,
];

// The label a human reads in the report: whatever identifies the control most clearly.
const describe = control =>
  KEYS.map(key => key(control)).find(Boolean) || `anon:${control.tag}`;

// Returns { lost, added, renamed } for one capture. `renamed` is a control matched on a weaker key
// than its name — which is how a control that just gained an accessible name shows up.
const diffControls = (beforeControls, afterControls) => {
  const beforeTaken = new Array(beforeControls.length).fill(false);
  const afterTaken = new Array(afterControls.length).fill(false);
  const renamed = [];

  KEYS.forEach((keyOf, pass) => {
    const afterBuckets = new Map();
    afterControls.forEach((control, index) => {
      if (afterTaken[index]) return;
      const key = keyOf(control);
      if (!key) return;
      if (!afterBuckets.has(key)) afterBuckets.set(key, []);
      afterBuckets.get(key).push(index);
    });

    beforeControls.forEach((control, index) => {
      if (beforeTaken[index]) return;
      const key = keyOf(control);
      if (!key) return;
      const candidates = afterBuckets.get(key);
      if (!candidates || !candidates.length) return;
      const match = candidates.shift();
      beforeTaken[index] = true;
      afterTaken[match] = true;
      if (pass > 1 && !control.name && afterControls[match].name) {
        renamed.push({ control: describe(control), name: afterControls[match].name });
      }
    });
  });

  return {
    lost: beforeControls.filter((_, index) => !beforeTaken[index]),
    added: afterControls.filter((_, index) => !afterTaken[index]),
    renamed,
  };
};

const EXCEPTIONS_PATH = join(import.meta.dirname, 'parity-exceptions.json');
const exceptions = existsSync(EXCEPTIONS_PATH)
  ? JSON.parse(await readFile(EXCEPTIONS_PATH, 'utf8'))
  : { moved: [] };
const excused = new Map(
  (exceptions.moved || []).map(entry => [`${entry.surface}|${entry.control}`, entry])
);

const before = await read(beforeDir);
const after = await read(afterDir);

const failures = [];
const notes = [];
const report = { lost: [], moved: [], added: [], renamed: [], regressions: [], surfaces: {} };

for (const [key, beforeCapture] of Object.entries(before)) {
  const afterCapture = after[key];
  if (!afterCapture) {
    failures.push(`${key}: the capture is missing from the after run — a whole surface disappeared`);
    report.lost.push({ capture: key, control: '(entire surface)' });
    continue;
  }

  const { lost, added, renamed } = diffControls(beforeCapture.controls, afterCapture.controls);

  for (const control of lost) {
    const label = describe(control);
    const excuse = excused.get(`${beforeCapture.surface}|${label}`);
    const entry = { capture: key, control: label };
    if (excuse) {
      report.moved.push({ ...entry, to: excuse.to, reason: excuse.reason });
      notes.push(`${key}: ${label} → ${excuse.to} (${excuse.reason})`);
    } else {
      report.lost.push(entry);
      failures.push(`${key}: lost ${label}`);
    }
  }
  for (const control of added) report.added.push({ capture: key, control: describe(control) });
  for (const entry of renamed) report.renamed.push({ capture: key, ...entry });

  // Quality gates: a redesign may not make any of these worse.
  const unnamedBefore = beforeCapture.controls.filter(c => c.unnamed).length;
  const unnamedAfter = afterCapture.controls.filter(c => c.unnamed).length;
  if (unnamedAfter > unnamedBefore) {
    failures.push(`${key}: unnamed controls rose from ${unnamedBefore} to ${unnamedAfter}`);
    report.regressions.push({ capture: key, kind: 'unnamed', before: unnamedBefore, after: unnamedAfter });
  }
  if (afterCapture.overflow > Math.max(beforeCapture.overflow, 0)) {
    failures.push(`${key}: horizontal overflow rose from ${beforeCapture.overflow}px to ${afterCapture.overflow}px`);
    report.regressions.push({ capture: key, kind: 'overflow', before: beforeCapture.overflow, after: afterCapture.overflow });
  }
  if (afterCapture.direction !== beforeCapture.direction) {
    failures.push(`${key}: direction changed from ${beforeCapture.direction} to ${afterCapture.direction}`);
    report.regressions.push({ capture: key, kind: 'direction', before: beforeCapture.direction, after: afterCapture.direction });
  }
  if (afterCapture.errors.length > beforeCapture.errors.length) {
    failures.push(`${key}: ${afterCapture.errors.length - beforeCapture.errors.length} new page error(s): ${afterCapture.errors[0]}`);
    report.regressions.push({ capture: key, kind: 'errors', before: beforeCapture.errors.length, after: afterCapture.errors.length });
  }

  report.surfaces[key] = {
    before: beforeCapture.controls.length,
    after: afterCapture.controls.length,
    unnamedBefore,
    unnamedAfter,
  };
}

for (const key of Object.keys(after)) {
  if (!before[key]) notes.push(`${key}: new capture, no baseline to compare against`);
}

if (jsonOut) await writeFile(jsonOut, JSON.stringify(report, null, 2));

const total = Object.keys(before).length;
console.log(`compared ${total} captures`);
console.log(
  `  lost ${report.lost.length}   moved-with-reason ${report.moved.length}   added ${report.added.length}   newly-named ${report.renamed.length}   regressions ${report.regressions.length}`
);
for (const note of notes) console.log(`  note  ${note}`);
for (const failure of failures) console.log(`  FAIL  ${failure}`);

process.exit(failures.length ? 1 : 0);
