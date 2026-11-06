import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * Every window draws its controls from src/ui/kit, so a page never carries its own field, button or sheet and the
 * Mac's measures live in one place. This fails on a raw control anywhere else under src/ui.
 */
const ui = fileURLToPath(new URL('../src/ui', import.meta.url));
const kit = join(ui, 'kit');

/** What a page may not draw itself. */
const RAW = [/<input\b/, /<select\b/, /<textarea\b/, /<button\b/, /role="dialog"/, /role="alertdialog"/];

/**
 * The few files that draw one on purpose, each with why, by its path under src/ui. Keep this short: a new entry
 * needs a reason the kit cannot serve.
 */
const ALLOWED: Record<string, string> = {
  // The scan is a full screen takeover the whole of which closes it, not a sheet with a head and a foot.
  'scan/ScanScreen.tsx': 'role="dialog"',
  // The compact menu slides in from the side and the project switcher hangs under its press; neither is a sheet.
  'app/AppShell.tsx': 'role="dialog"',
  // Nothing renders it any more; it waits on the person's word to be deleted rather than being migrated.
  'app/pages/ProjectInspector.tsx': '<button',
};

function tsxUnder(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) return path === kit ? [] : tsxUnder(path);
    return entry.name.endsWith('.tsx') ? [path] : [];
  });
}

describe('the base components', () => {
  it('are the only place a raw control is drawn', () => {
    const found: string[] = [];
    for (const path of tsxUnder(ui)) {
      const name = relative(ui, path);
      const lines = readFileSync(path, 'utf8').split('\n');
      lines.forEach((line, at) => {
        for (const raw of RAW) {
          if (!raw.test(line)) continue;
          if (ALLOWED[name] !== undefined && line.includes(ALLOWED[name])) continue;
          found.push(`${name}:${at + 1} ${line.trim()}`);
        }
      });
    }
    expect(found).toEqual([]);
  });
});
