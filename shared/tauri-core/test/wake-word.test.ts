import { describe, expect, it } from 'vitest';
import { afterWakeWord, nameAlone, withoutLeadingName, withoutTrailingName } from '../src/core/domain/wake-word';

/** Hearing its name, however the recognizer spells it, and what follows it; the Mac's own cases. */
describe('the wake word', () => {
  it('wakes on its name and hands on what followed', () => {
    expect(afterWakeWord('Memnox')).toBe('');
    expect(afterWakeWord("Hey Memnox, what's going on?")).toBe("what's going on?");
    expect(afterWakeWord('mem nox are they done')).toBe('are they done');
    expect(afterWakeWord('Men knocks.')).toBe('');
    expect(afterWakeWord('what are my agents doing')).toBeUndefined();
    expect(afterWakeWord('the memo knocks twice')).toBeUndefined();
    expect(afterWakeWord("Ma'am Knox")).toBe('');
    expect(afterWakeWord("ma'am knox what changed")).toBe('what changed');
  });

  it('wakes on the ways its name was misheard and said their own way', () => {
    expect(afterWakeWord('Emma Knox, can you start a session?')).toBe('can you start a session?');
    expect(afterWakeWord('MM Nox. Can you open up all my sessions?')).toBe('Can you open up all my sessions?');
    expect(afterWakeWord('Minnox')).toBeDefined();
    expect(afterWakeWord('Mennix, what changed?')).toBe('what changed?');
    expect(afterWakeWord('mim nax are they done')).toBe('are they done');
    expect(afterWakeWord('Memnex')).toBe('');
    expect(afterWakeWord('Emma nucks open my sessions')).toBe('open my sessions');
    expect(afterWakeWord('a man nicks the bike')).toBeUndefined();
    expect(afterWakeWord('my mom knocks first')).toBeUndefined();
    expect(afterWakeWord('the next ten minutes')).toBeUndefined();
  });

  it('takes its name said twice as one call, and its cut name only at either end', () => {
    expect(nameAlone('Memnox Manox')).toBe(true);
    expect(withoutLeadingName('Memnox Manox, what changed?')).toBe('what changed?');
    expect(afterWakeWord('Mnox')).toBe('');
    expect(withoutLeadingName('OK Knox can you please close all these panels')).toBe('can you please close all these panels');
    expect(withoutLeadingName("OK ma'am Knox, can you commit?")).toBe('can you commit?');
    expect(withoutLeadingName('Hey Mem nox, which one is working?')).toBe('which one is working?');
    expect(afterWakeWord('the gold sits in Fort Knox these days')).toBeUndefined();
    expect(afterWakeWord('move it to the Knox folder')).toBeUndefined();
  });

  it('takes its name off the end when they called it there', () => {
    expect(withoutTrailingName('OK, so why are you taking longer to reply? memnox memnox')).toBe('OK, so why are you taking longer to reply?');
    expect(withoutTrailingName('Can you Knox? Knox?')).toBe('Can you Knox?');
    expect(withoutTrailingName("commit that, ma'am Knox.")).toBe('commit that');
    expect(withoutTrailingName('are you there memnox memnox')).toBe('are you there');
    expect(withoutTrailingName('start a session in Memnox')).toBe('start a session in Memnox');
    expect(withoutTrailingName('start a session in Memnox. Memnox.')).toBe('start a session in Memnox.');
    expect(withoutTrailingName('Memnox memnox')).toBe('Memnox memnox');
    expect(nameAlone('Do it. Knox.')).toBe(false);
  });

  it('takes the name at the end of a question as part of it, and off the front only', () => {
    expect(nameAlone('Memnox')).toBe(true);
    expect(nameAlone('Hey Memnox.')).toBe(true);
    expect(nameAlone('Can you open Codex and start a new session within Memnox?')).toBe(false);
    expect(withoutLeadingName("Mem Nox. I've closed it.")).toBe("I've closed it.");
    expect(withoutLeadingName('Hey Memnox, which one is working?')).toBe('which one is working?');
    expect(withoutLeadingName('is the Memnox runtime on main')).toBe('is the Memnox runtime on main');
    expect(withoutLeadingName('Memnox')).toBe('Memnox');
  });

  it('does not wake on its own greeting', () => {
    const spoken = 'Hi Maya, I am Memnox. Press Option Space whenever you want me.';
    expect(afterWakeWord('Hi Maya I am Memnox press option space whenever you want me', spoken)).toBeUndefined();
    expect(afterWakeWord('whenever you want me Memnox what changed today', spoken)).toBe('what changed today');
    expect(afterWakeWord('Memnox are they done', '')).toBe('are they done');
  });
});
