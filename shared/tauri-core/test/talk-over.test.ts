import { describe, expect, it } from 'vitest';
import { echoCeiling, isOverOwnVoice, isTalkingOver, mayCarryOn, mayPauseOnLoudness, ownVoiceGap, TALK_OVER, type HeardLook } from '../src/core/domain/talk-over';

/** Hearing the person start to talk over the voice by loudness, whatever they say; the Mac's own cases. */
describe('talking over the voice', () => {
  const echo = Array.from({ length: 60 }, (_, index) => 0.38 + (0.12 * (index % 5)) / 4);

  it('hears them the moment they are louder than its own voice', () => {
    const ceiling = echoCeiling(echo, undefined);
    expect(ceiling).toBeCloseTo(0.5, 3);
    expect(isTalkingOver([0.45, 0.66, 0.7, 0.64, 0.68], ceiling)).toBe(true);
  });

  it('never takes its own loudest syllable or a click for them', () => {
    const ceiling = echoCeiling(echo, undefined);
    expect(isTalkingOver([0.5, 0.48, 0.5, 0.47, 0.5], ceiling)).toBe(false);
    expect(isTalkingOver([0.4, 0.9, 0.4, 0.42, 0.4], ceiling)).toBe(false);
  });

  it('hears any voice through headphones, and starts from last time until it heard enough', () => {
    expect(isTalkingOver([0.3, 0.35, 0.32, 0.31, 0.3], echoCeiling(Array(40).fill(0.08), undefined))).toBe(true);
    expect(echoCeiling([0.2, 0.3], 0.12)).toBe(0.3);
    expect(echoCeiling([0.2], undefined)).toBe(TALK_OVER.unheardEcho);
  });

  it('hears the person over its own voice by what it is playing', () => {
    const own: HeardLook[] = Array.from({ length: TALK_OVER.enoughLooks }, () => ({ heard: 0.4, playing: 0.5 }));
    const gap = ownVoiceGap(own, undefined) ?? 0;
    expect(gap).toBeCloseTo(-0.1, 3);
    expect(isOverOwnVoice([...own, { heard: 0.6, playing: 0.7 }, { heard: 0.6, playing: 0.7 }], gap, 0.3)).toBe(false);
    expect(isOverOwnVoice([...own, { heard: 0.6, playing: 0.2 }, { heard: 0.6, playing: 0.1 }], gap, 0.3)).toBe(true);
    expect(isOverOwnVoice([...own, { heard: 0.55, playing: 0.6 }, { heard: 0.5, playing: 0 }], gap, 0.3)).toBe(false);
    expect(ownVoiceGap([], undefined)).toBeUndefined();
  });

  it('trusts no loudness just after its voice comes back, and wants it to hold without echo cancellation', () => {
    expect(mayPauseOnLoudness(200, 5, true)).toBe(false);
    expect(mayPauseOnLoudness(1_000, 1, true)).toBe(true);
    expect(mayPauseOnLoudness(2_000, 1, false)).toBe(false);
    expect(mayPauseOnLoudness(2_000, TALK_OVER.loudLooksUncancelled, false)).toBe(true);
  });

  it('never carries on over somebody still talking, and soon once the room is quiet', () => {
    expect(mayCarryOn(2_000, 100)).toBe(false);
    expect(mayCarryOn(2_000, TALK_OVER.quietToCarryOnMs)).toBe(true);
    expect(mayCarryOn(500, 500)).toBe(false);
    expect(mayCarryOn(TALK_OVER.shortestHoldMs, 1_000)).toBe(true);
    expect(mayCarryOn(TALK_OVER.longestHoldMs, 0)).toBe(true);
  });
});
