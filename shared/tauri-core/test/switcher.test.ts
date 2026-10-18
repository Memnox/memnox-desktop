import { describe, expect, it } from 'vitest';
import { shelfPlace, shelfStart, turnMs } from '../src/core/domain/switcher';

describe('the switcher shelf', () => {
  it('faces the front card to the person and turns the rest away', () => {
    expect(shelfPlace(0, false)).toMatchObject({ rotateY: -0, scale: 1, x: 0, front: true });
    expect(shelfPlace(1, false)).toMatchObject({ rotateY: -52, scale: 0.9, x: 220, front: false });
    expect(shelfPlace(-2, false)).toMatchObject({ rotateY: 52, x: -370 });
  });

  it('lifts and grows the chosen card, and hides cards past the end of the shelf', () => {
    expect(shelfPlace(0.2, true)).toMatchObject({ scale: 1.18, y: -20, brightness: 0.06 });
    expect(shelfPlace(3.5, false).hidden).toBe(true);
    expect(shelfPlace(5, false).scale).toBeCloseTo(0.7);
  });

  it('starts across the row from the target and takes a beat per card', () => {
    expect(shelfStart(1, 6)).toBe(5);
    expect(shelfStart(4, 6)).toBe(0);
    expect(turnMs(0, 4)).toBe(990);
  });
});
