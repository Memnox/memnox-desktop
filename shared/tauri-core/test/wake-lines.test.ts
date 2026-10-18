import { describe, expect, it } from 'vitest';
import { WakeLines, WakeRest, WAKE_REST } from '../src/core/domain/wake-lines';

const first = (choices: readonly string[]) => choices[0];

describe('what it says when called', () => {
  it('greets the first call in a while for the hour and never repeats a line', () => {
    const lines = new WakeLines();
    expect(lines.line({ address: 'sir', hour: 20, sinceLastCallMs: undefined, pick: first })).toBe('Good evening, sir. Systems online. Memnox is ready.');
    expect(lines.line({ hour: 8, sinceLastCallMs: 5 * 3_600_000, pick: first })).toBe('Good morning. Systems online. Memnox is ready.');
    expect(lines.line({ address: 'sir', hour: 20, sinceLastCallMs: 30_000, pick: first })).toBe("I'm here, sir.");
    expect(lines.line({ address: 'sir', hour: 20, sinceLastCallMs: 30_000, pick: first })).toBe('Sir?');
    expect(lines.line({ address: '  ', hour: 20, sinceLastCallMs: 30_000 })).not.toContain('sir');
    for (let round = 0; round < 20; round += 1) expect(lines.line({ address: 'sir', hour: 20, sinceLastCallMs: 30_000 }).startsWith('Yes')).toBe(false);
  });

  it('greets by name, then says the title until the name has rested', () => {
    const lines = new WakeLines();
    const start = 1_000_000_000;
    expect(lines.line({ address: 'sir', name: 'Moiz', hour: 8, sinceLastCallMs: undefined, at: start, pick: first })).toBe('Good morning, Moiz. Systems online. Memnox is ready.');
    expect(lines.line({ address: 'sir', name: 'Moiz', hour: 8, sinceLastCallMs: 60_000, at: start + 60_000, pick: first })).toBe("I'm here, sir.");
    expect(lines.line({ address: 'sir', name: 'Moiz', hour: 9, sinceLastCallMs: 60_000, at: start + 31 * 60_000, pick: first })).toBe("I'm here, Moiz.");
    expect(new WakeLines().line({ name: 'Moiz', hour: 8, sinceLastCallMs: 60_000, pick: first })).toBe("I'm here.");
  });

  it('backs off a failing ear, and listens again quickly after a round that worked', () => {
    const rest = new WakeRest();
    expect(rest.after(true)).toBe(WAKE_REST.afterFirstFailureMs);
    expect(rest.after(true)).toBe(2_000);
    for (let round = 0; round < 10; round += 1) rest.after(true);
    expect(rest.after(true)).toBe(WAKE_REST.longestMs);
    expect(rest.after(false)).toBe(WAKE_REST.afterWorkingMs);
    expect(rest.after(true)).toBe(WAKE_REST.afterFirstFailureMs);
  });
});
