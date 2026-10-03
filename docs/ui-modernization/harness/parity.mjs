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

// A control's identity, most stable first. `data-test-id` is explicit and survives restyling; an
// accessible name survives a change of element; an icon is the last resort for the unnamed controls
// that are themselves a finding.
const identify = control => {
  if (control.testId) return `testId:${control.testId}`;
  if (control.name) return `name:${control.tag}:${control.name.toLowerCase()}`;
  if (control.icon) return `icon:${control.tag}:${control.icon}`;
  return `anon:${control.tag}:${control.role}:${control.type}`;
};

// Same control, counted: two identical delete buttons in two rows are two features, not one.
const census = controls => {
  const counts = new Map();
  for (const control of controls) {
    const key = identify(control);
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return counts;
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
const report = { lost: [], hidden: [], moved: [], added: [], regressions: [], surfaces: {} };

for (const [key, beforeCapture] of Object.entries(before)) {
  const afterCapture = after[key];
  if (!afterCapture) {
    failures.push(`${key}: the capture is missing from the after run — a whole surface disappeared`);
    report.lost.push({ capture: key, control: '(entire surface)' });
    continue;
  }

  const beforeVisible = census(beforeCapture.controls);
  const afterVisible = census(afterCapture.controls);

  for (const [control, count] of beforeVisible) {
    const afterCount = afterVisible.get(control) || 0;
    if (afterCount >= count) continue;
    const excuse = excused.get(`${beforeCapture.surface}|${control}`);
    const entry = { capture: key, control, before: count, after: afterCount };
    if (excuse) {
      report.moved.push({ ...entry, to: excuse.to, reason: excuse.reason });
      notes.push(`${key}: ${control} ×${count - afterCount} → ${excuse.to} (${excuse.reason})`);
    } else {
      report.lost.push(entry);
      failures.push(`${key}: lost ${control} (${count} before, ${afterCount} after)`);
    }
  }

  for (const [control, count] of afterVisible) {
    const beforeCount = beforeVisible.get(control) || 0;
    if (count > beforeCount) report.added.push({ capture: key, control, before: beforeCount, after: count });
  }

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
console.log(`  lost ${report.lost.length}   moved-with-reason ${report.moved.length}   added ${report.added.length}   regressions ${report.regressions.length}`);
for (const note of notes) console.log(`  note  ${note}`);
for (const failure of failures) console.log(`  FAIL  ${failure}`);

process.exit(failures.length ? 1 : 0);
