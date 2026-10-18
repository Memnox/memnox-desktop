import { describe, expect, it } from 'vitest';
import { agentColour } from '../src/core/domain/agent-colour';
import { middleCut } from '../src/core/domain/middle-cut';
import { notchPath, notchRadius } from '../src/core/domain/notch-shape';
import { atRest, cubicBezier, springStep, SPRINGS } from '../src/core/domain/spring';

describe('the notch outline', () => {
  it('draws the flares and quadratic bottom corners of the Mac shape', () => {
    expect(notchPath(172, 24, 14, 14)).toBe('M 0 0 Q 14 0 14 14 L 14 19 Q 14 24 19 24 L 153 24 Q 158 24 158 19 L 158 14 Q 158 0 172 0 Z');
  });

  it('never rounds the bottom past half the room the shape has', () => {
    expect(notchRadius(588, 206, 14, 30)).toBe(30);
    expect(notchRadius(172, 24, 14, 30)).toBe(5);
  });
});

describe('the small rules the island draws with', () => {
  it('gives each agent its colour and any other a stable one of five', () => {
    expect(agentColour('agt_claude-code')).toBe('#D97757');
    expect(agentColour('codex')).toBe('#2DD4BF');
    expect(agentColour('newcomer')).toBe(agentColour('agt_newcomer'));
    // h = ((("a" * 31) + "b") ...) & 0xFFFF for "ab" is 97 * 31 + 98 = 3105, and 3105 % 5 = 0.
    expect(agentColour('ab')).toBe('#F472B6');
  });

  it('cuts a long command in the middle so both its ends stay', () => {
    const fits = (text: string) => text.length <= 11;
    expect(middleCut('git push origin main', fits)).toBe('git p… main');
    expect(middleCut('ls', fits)).toBe('ls');
  });

  it('springs to rest and follows the shrinking curve to its end', () => {
    let now = { value: 0, velocity: 0 };
    for (let frame = 0; frame < 120; frame++) now = springStep(now, 100, SPRINGS.grow, 1 / 60);
    expect(atRest(now, 100)).toBe(true);
    const curve = cubicBezier(0.45, 0, 0.2, 1);
    expect(curve(0)).toBe(0);
    expect(curve(1)).toBe(1);
    expect(curve(0.5)).toBeGreaterThan(0.5);
  });

  it('overshoots when growing, as the Mac springs out past its size and back', () => {
    let now = { value: 0, velocity: 0 };
    let most = 0;
    for (let frame = 0; frame < 60; frame++) {
      now = springStep(now, 100, SPRINGS.grow, 1 / 60);
      most = Math.max(most, now.value);
    }
    expect(most).toBeGreaterThan(100);
  });
});

