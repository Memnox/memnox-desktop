import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { WIDTH } from '../src/core/domain/destinations';

const styles = readFileSync(new URL('../src/ui/styles.css', import.meta.url), 'utf8');

function token(name: string): number {
  const found = new RegExp(`--${name}:\\s*(\\d+)px;`).exec(styles);
  if (found === null) throw new Error(`styles.css has no --${name}`);
  return Number(found[1]);
}

describe('the layout tokens', () => {
  it('break the page where the shell changes its layout', () => {
    expect(token('breakpoint-narrow')).toBe(WIDTH.NARROW);
    expect(token('breakpoint-medium')).toBe(WIDTH.MEDIUM);
    expect(token('breakpoint-wide')).toBe(WIDTH.WIDE);
  });
});
