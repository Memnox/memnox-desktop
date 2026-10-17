import { describe, expect, it } from 'vitest';
import { EarlierAnswer } from '../src/core/domain/earlier-answer';

describe('an answer that came first', () => {
  it('reads a held call and a proposal answered before', () => {
    expect(EarlierAnswer.from({ id: 1, ok: true, outcome: 'already answered session' })?.word).toBe('session');
    expect(EarlierAnswer.from({ id: 1, ok: true, outcome: 'already declined' })?.word).toBe('declined');
  });

  it('reads a call already released without claiming which answer it was', () => {
    const earlier = EarlierAnswer.from({ id: 1, ok: false, error: 'hld_1 is no longer held' });
    expect(earlier?.line).toBe('That was settled before your answer arrived, so nothing changed.');
  });

  it('is nothing when this answer was the one that counted', () => {
    expect(EarlierAnswer.from({ id: 1, ok: true, outcome: 'allowed' })).toBeUndefined();
    expect(EarlierAnswer.from(undefined)).toBeUndefined();
  });
});
