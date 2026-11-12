import { describe, expect, it } from 'vitest';
import { RuntimeAwayLines, runtimeStanding, START_GRACE_MS } from '../src/core/domain/runtime-away';

/** A computer that is only being set up never reads as a fault; one whose service stopped does. */
describe('where the service stands', () => {
  it('is starting while a window that never read it is newly open', () => {
    expect(runtimeStanding({ unavailable: true, read: false }, 0)).toBe('starting');
    expect(runtimeStanding({ unavailable: true, read: false }, START_GRACE_MS - 1)).toBe('starting');
  });

  it('is away once the wait has run out, or when it stopped after answering', () => {
    expect(runtimeStanding({ unavailable: true, read: false }, START_GRACE_MS)).toBe('away');
    expect(runtimeStanding({ unavailable: true, read: true }, 0)).toBe('away');
  });

  it('is up once it answered, and only being reached before the first answer', () => {
    expect(runtimeStanding({ unavailable: false, read: true }, 0)).toBe('up');
    expect(runtimeStanding({ unavailable: false, read: false }, 0)).toBe('reaching');
  });

  it('says so with no dash and nothing for the person to do', () => {
    for (const line of [RuntimeAwayLines.starting, RuntimeAwayLines.startingDetail]) expect(line).not.toMatch(/[\u2014\u2013]| - /);
    expect(RuntimeAwayLines.startingDetail).toContain('nothing you need to do');
  });
});
