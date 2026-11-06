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
  // Nothing renders it any more; it waits on the person's word to be deleted rather than being migrated.
  'app/pages/ProjectInspector.tsx': '<button',
};

/**
 * A Tailwind arbitrary value or property holding a length or a colour, such as `h-[30px]`, `text-[#fff]` or
 * `[border-radius:9px]`. A page names a token from styles.css instead, so every measure is one the Mac draws with.
 */
const ARBITRARY = /[\w:/.!-]*\[[^\]\s"'`]*?(?:\d(?:px|rem)(?![a-zA-Z])|#[0-9a-fA-F]{3,8}\b|rgba?\()[^\]\s"'`]*\]/g;

/** A pixel, a rem or a colour written straight into an inline style, rather than read from a named constant. */
const STYLE_LITERAL = /\d(?:px|rem)(?![a-zA-Z])|['"`]#[0-9a-fA-F]{3,8}\b|rgba?\(|\b(?:width|height|left|right|top|bottom|gap|margin\w*|padding\w*|fontSize|borderRadius|minWidth|maxWidth|minHeight|maxHeight|inset):\s*-?(?:[2-9]|\d{2,})/g;

/**
 * Files that may type their own values, each with why. Keep this short: an entry needs a reason no token can
 * serve, such as a value computed while drawing.
 */
const OWN_VALUES: Record<string, string> = {
  // The designer's preview harnesses never ship, so their scaffolding is not the Mac's to match.
  'preview.tsx': 'designer preview',
  'tools/preview.tsx': 'designer preview',
};

function sourcesUnder(folder: string, ends: readonly string[]): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) return path === kit ? [] : sourcesUnder(path, ends);
    return ends.some((end) => entry.name.endsWith(end)) ? [path] : [];
  });
}

/** Each inline style object of a source, `style={{ ... }}`, with the line it starts on. */
function inlineStyles(source: string): { line: number; body: string }[] {
  const found: { line: number; body: string }[] = [];
  for (let at = source.indexOf('style={{'); at >= 0; at = source.indexOf('style={{', at + 1)) {
    let depth = 0;
    let end = at + 'style='.length;
    for (; end < source.length; end += 1) {
      if (source[end] === '{') depth += 1;
      if (source[end] === '}') depth -= 1;
      if (depth === 0) break;
    }
    found.push({ line: source.slice(0, at).split('\n').length, body: source.slice(at, end + 1) });
  }
  return found;
}

describe('the base components', () => {
  it('are the only place a raw control is drawn', () => {
    const found: string[] = [];
    for (const path of sourcesUnder(ui, ['.tsx'])) {
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

  it('hold every length and colour, so no page types its own', () => {
    const found: string[] = [];
    for (const path of sourcesUnder(ui, ['.tsx', '.ts'])) {
      const name = relative(ui, path);
      if (OWN_VALUES[name] !== undefined) continue;
      const source = readFileSync(path, 'utf8');
      source.split('\n').forEach((line, at) => {
        for (const [value] of line.matchAll(ARBITRARY)) found.push(`${name}:${at + 1} ${value}`);
      });
      for (const { line, body } of inlineStyles(source)) {
        for (const [value] of body.matchAll(STYLE_LITERAL)) found.push(`${name}:${line} style ${value}`);
      }
    }
    expect(found).toEqual([]);
  });
});
