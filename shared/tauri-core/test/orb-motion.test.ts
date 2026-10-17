import { describe, expect, it } from 'vitest';
import { orbFit, OrbMotion } from '../src/core/domain/orb-motion';

/** Frames at sixty a second from `from`, returning the last. */
function run(motion: OrbMotion, from: number, seconds: number, ...rest: Parameters<OrbMotion['frame']> extends [number, ...infer R] ? R : never) {
  let last = motion.frame(from, ...rest);
  for (let frame = 1; frame <= seconds * 60; frame += 1) last = motion.frame(from + frame / 60, ...rest);
  return last;
}

describe('the orb', () => {
  it('eases toward each state rather than snapping', () => {
    const motion = new OrbMotion(0);
    const first = motion.frame(0, 'thinking', 0, false);
    expect(first.swirl).toBeGreaterThan(0);
    expect(first.swirl).toBeLessThan(0.1);
    expect(run(motion, 0, 3, 'thinking', 0, false).knot).toBeGreaterThan(0.9);
  });

  it('pulls in and bounces while a call waits on the person', () => {
    const settled = run(new OrbMotion(0), 0, 3, 'needs-you', 0, true);
    expect(settled.hold).toBeGreaterThan(0.9);
    expect(settled.bounce).toBeGreaterThan(0.9);
  });

  it('sends a ring up the sphere for each syllable it speaks, four at most', () => {
    const motion = new OrbMotion(0);
    let uniforms = motion.frame(0, 'speaking', 0, false);
    for (let syllable = 0; syllable < 6; syllable += 1) {
      const at = 0.2 * (syllable + 1);
      motion.frame(at, 'speaking', 0, false);
      uniforms = motion.frame(at + 1 / 60, 'speaking', 1, false);
      motion.frame(at + 0.1, 'speaking', 0, false);
    }
    expect(uniforms.ringFades.filter((fade) => fade > 0)).toHaveLength(4);
  });

  it('rings out on an allow and is still again once the gesture is over', () => {
    const motion = new OrbMotion(0);
    motion.react('allowed', 0);
    expect(motion.frame(0.1, 'idle', 0, false).glow).toBeGreaterThan(0.5);
    expect(motion.frame(1, 'idle', 0, false).glow).toBe(0);
  });

  it('thins its points on a small orb', () => {
    expect(orbFit(240)).toEqual({ points: 6000, dot: 1 });
    expect(orbFit(24)).toEqual({ points: 300, dot: 0.35 });
  });
});
