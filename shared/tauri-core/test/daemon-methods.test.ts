import * as wire from '@memnox/core/wire';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { DESTINATIONS, NOT_YET_SERVED } from '../src/core/domain/destinations';

/**
 * Every press and every tab names a daemon method the runtime's own wire declares, so no button on any page sends a
 * request the daemon would refuse as unknown and no tab waits on a method that does not exist.
 */
const src = fileURLToPath(new URL('../src', import.meta.url));

/** Every method the wire names, across the daemon's own list and each feature's. */
const KNOWN = new Set(
  Object.entries(wire)
    .filter(([name, value]) => name.endsWith('_METHOD') && typeof value === 'object' && value !== null)
    .flatMap(([, value]) => Object.values(value as Record<string, unknown>))
    .filter((value): value is string => typeof value === 'string'),
);

function sources(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) return sources(path);
    return /\.(ts|tsx)$/.test(entry.name) ? [path] : [];
  });
}

/** The method names written out as words: a request's method, a probe, and what a tab needs. */
const NAMED = [/method: '([a-z][a-z-]*)'/g, /supports\('([a-z][a-z-]*)'\)/g, /needs: '([a-z][a-z-]*)'/g];

describe('the daemon methods the window sends', () => {
  it('reads the wire’s methods, the new job methods among them', () => {
    for (const method of ['profiles', 'profile-bind', 'profile-unbind', 'templates', 'profile-from-template', 'agent-work', 'work-start', 'handoff-answer', 'subscribe']) expect(KNOWN.has(method)).toBe(true);
  });

  it('names only methods the runtime declares, in every source and on every tab', () => {
    const unknown: string[] = [];
    for (const file of sources(src)) {
      const text = readFileSync(file, 'utf8');
      for (const pattern of NAMED) {
        for (const match of text.matchAll(pattern)) {
          const method = match[1] ?? '';
          if (!KNOWN.has(method) && !NOT_YET_SERVED.includes(method)) unknown.push(`${relative(src, file)}: ${method}`);
        }
      }
    }
    for (const destination of DESTINATIONS) {
      for (const tab of destination.tabs) if (tab.needs !== undefined && !KNOWN.has(tab.needs) && !NOT_YET_SERVED.includes(tab.needs)) unknown.push(`${destination.id}/${tab.id}: ${tab.needs}`);
    }
    expect(unknown).toEqual([]);
  });

  it('keeps a method waiting for the runtime only while the runtime still does not declare it', () => {
    expect(NOT_YET_SERVED.filter((method) => KNOWN.has(method))).toEqual([]);
  });
});
