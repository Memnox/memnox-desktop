import { describe, expect, it } from 'vitest';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { Talking } from '../src/core/application/talking';
import type { Cue } from '../src/core/domain/chimes';
import { chunks, HandTimer, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

function talkingOver(lookingAt?: () => Promise<{ app?: string; title?: string }>) {
  const daemon = new ScriptedDaemon({ 'register-key': registered, ask: (request) => chunks(request.id, 'Sure.') });
  const speaker = new RecordingSpeaker();
  const ids = new RequestIds();
  const cues: Cue[] = [];
  const talking = new Talking(daemon, speaker, new Signer(daemon, new PersonKey(), ids), ids, {
    timer: new HandTimer().start,
    chimes: { play: (cue) => void cues.push(cue) },
    owner: () => 'sir',
    hour: () => 20,
    lookingAt,
  });
  return { daemon, speaker, talking, cues };
}

describe('asking by voice', () => {
  it('answers its name alone like a person and sends nothing', async () => {
    const { daemon, speaker, talking, cues } = talkingOver();
    await talking.heard('Hey Memnox.');
    expect(daemon.sent('ask')).toEqual([]);
    expect(speaker.said[0]).toMatch(/^Good evening, sir\./);
    expect(cues).toEqual([]);
  });

  it('takes its name off either end, chimes as the words go, and says it greeted them already', async () => {
    const { daemon, talking, cues } = talkingOver();
    talking.answerToCall();
    await talking.heard('Memnox, what changed today? Memnox.');
    const ask = daemon.sent('ask')[0];
    expect(ask?.said).toBe('what changed today?');
    expect(ask?.greeted).toBe(true);
    expect(cues).toEqual(['sent']);
    expect(talking.spokeThisTurn).toBe(true);
  });

  it('carries how they asked and what is in front of them, never decided by a word', async () => {
    const { daemon, talking } = talkingOver(async () => ({ app: 'code', title: 'memnox-runtime' }));
    await talking.heard('never push to main', true, { intent: 'rule' });
    const ask = daemon.sent('ask')[0];
    expect(ask?.intent).toBe('rule');
    expect(ask?.finished).toBe(true);
    expect(ask?.lookingAt).toBe('code');
    expect(ask?.lookingAtWindow).toBe('memnox-runtime');
  });

  it('chimes a failed turn before the apology', async () => {
    const daemon = new ScriptedDaemon({});
    const ids = new RequestIds();
    const cues: Cue[] = [];
    const talking = new Talking(daemon, new RecordingSpeaker(), new Signer(daemon, new PersonKey(), ids), ids, { timer: new HandTimer().start, chimes: { play: (cue) => void cues.push(cue) } });
    await talking.heard('what is running');
    expect(cues).toEqual(['sent', 'failed']);
  });
});
