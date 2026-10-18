import { describe, expect, it } from 'vitest';
import { DictationKey, HoldKeys, VOICE_KEY_TIMING, type KeyReport } from '../src/core/domain/voice-keys';

/** A timer the test runs by hand, with a clock the test moves. */
function clock() {
  let now = 0;
  let pending: { at: number; fire: () => void }[] = [];
  return {
    now: () => now,
    timer: (ms: number, fire: () => void) => {
      const entry = { at: now + ms, fire };
      pending.push(entry);
      return () => {
        pending = pending.filter((each) => each !== entry);
      };
    },
    pass(ms: number) {
      now += ms;
      const due = pending.filter((each) => each.at <= now);
      pending = pending.filter((each) => each.at > now);
      for (const each of due) each.fire();
    },
  };
}

const mods = (on: Partial<Record<'ctrl' | 'leftAlt' | 'rightAlt' | 'shift' | 'meta', boolean>>): KeyReport => ({
  kind: 'modifiers',
  ctrl: false,
  leftAlt: false,
  rightAlt: false,
  shift: false,
  meta: false,
  ...on,
});

describe('the dictation key', () => {
  it('starts once right Alt has been held a moment, and ends when it is let go', () => {
    const time = clock();
    const key = new DictationKey(time.timer, time.now);
    const seen: string[] = [];
    key.began = () => seen.push('began');
    key.ended = () => seen.push('ended');
    key.saw(mods({ rightAlt: true }));
    time.pass(VOICE_KEY_TIMING.dictationMeantAfterMs - 1);
    expect(seen).toEqual([]);
    time.pass(1);
    expect(seen).toEqual(['began']);
    key.saw(mods({}));
    expect(seen).toEqual(['began', 'ended']);
  });

  it('never starts for AltGr typing a character, or with another modifier', () => {
    const time = clock();
    const key = new DictationKey(time.timer, time.now);
    let began = 0;
    key.began = () => (began += 1);
    key.saw(mods({ rightAlt: true }));
    key.saw({ kind: 'key' });
    time.pass(1_000);
    key.saw(mods({}));
    key.saw(mods({ rightAlt: true, shift: true }));
    time.pass(1_000);
    expect(began).toBe(0);
  });

  it('runs hands free on a double tap until it is pressed again', () => {
    const time = clock();
    const key = new DictationKey(time.timer, time.now);
    const seen: string[] = [];
    key.began = () => seen.push('began');
    key.ended = () => seen.push('ended');
    key.saw(mods({ rightAlt: true }));
    time.pass(80);
    key.saw(mods({}));
    time.pass(100);
    key.saw(mods({ rightAlt: true }));
    expect(seen).toEqual(['began']);
    expect(key.isHandsFree).toBe(true);
    key.saw(mods({}));
    expect(key.active).toBe(true);
    key.saw(mods({ rightAlt: true }));
    expect(seen).toEqual(['began', 'ended']);
  });

  it('stays quiet when the person turned dictation off', () => {
    const time = clock();
    const key = new DictationKey(time.timer, time.now);
    key.enabled = false;
    let began = 0;
    key.began = () => (began += 1);
    key.saw(mods({ rightAlt: true }));
    time.pass(1_000);
    expect(began).toBe(0);
  });
});

describe('the rule keys', () => {
  it('begin after Control and left Alt are held a moment, and end when either is let go', () => {
    const time = clock();
    const keys = new HoldKeys(time.timer);
    const seen: string[] = [];
    keys.began = () => seen.push('began');
    keys.ended = () => seen.push('ended');
    keys.saw(mods({ ctrl: true, leftAlt: true }));
    time.pass(VOICE_KEY_TIMING.ruleMeantAfterMs);
    expect(keys.holding).toBe(true);
    keys.saw(mods({ ctrl: true }));
    expect(seen).toEqual(['began', 'ended']);
  });

  it('are called off by a letter pressed with them, and never by AltGr', () => {
    const time = clock();
    const keys = new HoldKeys(time.timer);
    let began = 0;
    keys.began = () => (began += 1);
    keys.saw(mods({ ctrl: true, leftAlt: true }));
    keys.saw({ kind: 'key' });
    time.pass(1_000);
    keys.saw(mods({ ctrl: true, rightAlt: true }));
    time.pass(1_000);
    expect(began).toBe(0);
  });
});
