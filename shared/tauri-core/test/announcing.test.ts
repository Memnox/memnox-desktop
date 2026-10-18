import type { DaemonEvent } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { awaitsAnswer, isSaid, isShownOnly } from '../src/core/domain/announcing';
import { endOfSpeechPause, joinedSpeech, SPEECH_PAUSE } from '../src/core/domain/turn-taking';

const notice = (kind: string, extra: Partial<DaemonEvent> = {}): DaemonEvent => ({ kind: 'notice', notice: kind, subject: 'ntc_1', agent: 'claude-code', summary: 'It happened.', at: 't', ...extra });
const held: DaemonEvent = { kind: 'held', subject: 'apr_1', agent: 'claude-code', summary: 'It wants to push.', at: 't' };

/** Which events are said, and which keep the microphone open; the Mac's own cases. */
describe('announcing', () => {
  it('says what they asked for or what waits on them whatever the setting', () => {
    for (const kind of ['watched', 'question', 'collision']) expect(isSaid(notice(kind), false)).toBe(true);
    for (const kind of ['finished', 'committed', 'pushed', 'would-have', 'ended', 'something-newer']) {
      expect(isSaid(notice(kind), false)).toBe(false);
      expect(isSaid(notice(kind), true)).toBe(true);
    }
    expect(isSaid(held, false)).toBe(true);
  });

  it('keeps listening only for what waits on their answer', () => {
    expect(awaitsAnswer(held)).toBe(true);
    expect(awaitsAnswer(notice('question'))).toBe(true);
    expect(awaitsAnswer(notice('asking'))).toBe(true);
    expect(awaitsAnswer(notice('watched'))).toBe(false);
    expect(awaitsAnswer(notice('finished'))).toBe(false);
  });

  it('says nothing a phone holds or asked for, and only shows a phone turn or the voice moving', () => {
    const fromPhone = { ...held, heardOn: { deviceId: 'dev_1', name: 'iPhone' } };
    expect(isSaid(fromPhone, true)).toBe(false);
    expect(awaitsAnswer(fromPhone)).toBe(false);
    const turn = notice('started', { phoneTurn: { deviceId: 'dev_1', name: 'iPhone', said: 'what changed' } });
    expect(isShownOnly(turn)).toBe(true);
    expect(isSaid(turn, true)).toBe(false);
    expect(awaitsAnswer(turn)).toBe(false);
  });
});

describe('turn taking', () => {
  it('answers a short reply soon and waits longest for somebody still thinking', () => {
    expect(endOfSpeechPause('Yes.')).toBe(SPEECH_PAUSE.shortReply);
    expect(endOfSpeechPause('can you open')).toBe(SPEECH_PAUSE.stillThinking);
    expect(endOfSpeechPause('what changed in the repo and')).toBe(SPEECH_PAUSE.stillThinking);
    expect(endOfSpeechPause('What changed today?')).toBe(SPEECH_PAUSE.finished);
    expect(endOfSpeechPause('show me sessions')).toBe(SPEECH_PAUSE.unmarked);
  });

  it('joins two breaths as one sentence', () => {
    expect(joinedSpeech('so.', 'Is there')).toBe('so. Is there');
    expect(joinedSpeech('sir ?', '?')).toBe('sir?');
  });
});
