import { describe, expect, it } from 'vitest';
import { cutInWords, isBargeIn, isPersonAfterPause, mayBeCuttingIn, sincePause, withoutEcho, withoutEchoRuns } from '../src/core/domain/echo';

/** Telling the person cutting in from the voice hearing its own echo; the Mac's own cases. */
describe('its own echo', () => {
  it('takes the tail of its own sentence off what it heard', () => {
    const spoken = 'My apologies, that was not confirmed: memnox login is not something a voice may run.';
    expect(withoutEchoRuns('Confirmed Memnox login', spoken)).toBe('');
    expect(withoutEchoRuns('Yes, login', spoken)).toBe('Yes, login');
  });

  it('keeps words its sentence only holds out of order', () => {
    const spoken = 'Good morning. What can I do for you?';
    expect(withoutEchoRuns('Can you?', spoken)).toBe('Can you?');
    expect(withoutEchoRuns('do for you show my sessions', spoken)).toBe('show my sessions');
  });

  it('takes off what is left of its echo where the recognizer split a word', () => {
    const spoken = 'Very well. That rule is in force in HireMe.AI.';
    expect(withoutEchoRuns('Very well that rule is enforced in hire me AI', spoken)).toBe('');
    expect(withoutEchoRuns('Very well that rule is in force, now push it', spoken)).toBe('now push it');
    expect(withoutEchoRuns('rule', spoken)).toBe('rule');
    expect(withoutEchoRuns('Very well that rule is enforced in hire me AI so can you', spoken)).toBe('so can you');
  });

  it('tells the person talking over it from its own echo', () => {
    const spoken = 'Claude Code finished checkout, four files changed and the tests pass.';
    expect(isBargeIn('four files changed and the tests', spoken)).toBe(false);
    expect(isBargeIn('the', spoken)).toBe(false);
    expect(isBargeIn('wait, what about codex', spoken)).toBe(true);
    expect(isBargeIn('stop open it', '')).toBe(true);
    expect(isBargeIn('Okay, so can you close all of them?', 'Two are working at the moment.', true)).toBe(true);
  });

  it('does not take its own voice misheard for the person', () => {
    expect(isBargeIn('I missed that we were positive', 'I missed that. Which repository would you like the session on, and what should it check for?', true)).toBe(false);
    expect(isBargeIn('Possession is running', "The session's running but its window isn't tracked", true)).toBe(false);
    expect(isBargeIn('Let me log everything', "Let me look. Everything's quiet.", true)).toBe(false);
    expect(isBargeIn('There is', "There's a card on your screen with the summary.", true)).toBe(false);
    const reply = 'I keep an eye on your agent sessions and tell you what each is doing';
    expect(isBargeIn(`${reply} wait stop which one is working`, reply, true)).toBe(true);
    expect(isBargeIn(reply, reply, true)).toBe(false);
    expect(withoutEcho("Nothing's working now the fingerprint can you tell me what", "Nothing's working now. The fingerprint task was the last one.")).toBe('can you tell me what');
    expect(isBargeIn('stop', 'I can stop the session', true)).toBe(false);
  });

  it('pauses on the first words that are not its own', () => {
    const spoken = 'Claude Code finished setting up the voice picker in memnox macos';
    expect(mayBeCuttingIn('Claude Code finished setting why not', spoken)).toBe(true);
    expect(mayBeCuttingIn('Claude Code finished setting why', spoken)).toBe(false);
    expect(mayBeCuttingIn('Claude Code finished stop', spoken)).toBe(true);
    expect(mayBeCuttingIn('Claude Code finished setting up', spoken)).toBe(false);
    expect(mayBeCuttingIn('', spoken)).toBe(false);
    expect(mayBeCuttingIn('Shall I start cur', 'Shall I start Cursor in memnox runtime to review your changes?')).toBe(false);
    expect(mayBeCuttingIn('Five agents on your Memnox', 'Five agents on your Mac.')).toBe(true);
  });

  it('takes only what came once it went quiet for the person', () => {
    const spoken = 'Moïse, Claude Code in memnox macos wants to delete src. Allow it, or deny?';
    const pausedOn = 'My Claude Code in memnox macos wants to delete and Galo';
    expect(isPersonAfterPause(sincePause(`${pausedOn} Shanaka`, pausedOn), spoken)).toBe(false);
    const heard = `${pausedOn} wait which folder is that`;
    expect(isPersonAfterPause(sincePause(heard, pausedOn), spoken)).toBe(true);
    expect(sincePause(heard, pausedOn)).toBe('and Galo wait which folder is that');
    expect(isPersonAfterPause(sincePause('Claude Code stop', 'Claude Code stop'), spoken)).toBe(true);
  });

  it('keeps what they said while it was quiet', () => {
    const spoken =
      "Codex is open, and your words are on the clipboard, since I could not type them in. Press Command V, then Return, in its chat. The Mac couldn't type into Codex a moment ago, so the message is on your clipboard. Shall I try typing it again?";
    const pausedOn = "On the clipboard since I could not type them in press command V then return and it's chat so I think sometimes you don't understand so I ask you many times to talk";
    const heard = `${pausedOn} you said`;
    expect(cutInWords(heard, pausedOn, spoken, true)).toBe("I think sometimes you don't understand so I ask you many times to talk you said");
    expect(cutInWords(heard, pausedOn, spoken, false)).toBe('to talk you said');
  });
});
