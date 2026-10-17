import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { ProposalCards } from '../src/core/application/proposal-cards';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { ANSWER_WINDOW_MS, Talking } from '../src/core/application/talking';
import { LINES } from '../src/core/domain/spoken';
import { chunks, HandTimer, held, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

type Answers = ConstructorParameters<typeof ScriptedDaemon>[0];

function talkingOver(answers: Answers, key = new PersonKey(), timer = new HandTimer()) {
  const daemon = new ScriptedDaemon({ 'register-key': registered, ...answers });
  const speaker = new RecordingSpeaker();
  const ids = new RequestIds();
  let clock = 1_000_000;
  const talking = new Talking(daemon, speaker, new Signer(daemon, key, ids), ids, {
    now: () => clock,
    timer: timer.start,
  });
  const later = (ms: number) => {
    clock += ms;
  };
  return { daemon, speaker, talking, key, later };
}

const proposal = (subject: string, extra: Partial<DaemonEvent> = {}): DaemonEvent => ({
  ...held(subject),
  kind: 'proposal',
  summary: 'push to main for codex',
  ...extra,
});

const confirmedOk = (request: DaemonRequest): DaemonResponse[] => [{ id: request.id, ok: true }];

describe('asking', () => {
  it('sends what the person said whole and speaks the answer sentence by sentence', async () => {
    const { daemon, speaker, talking } = talkingOver({
      ask: (request) => chunks(request.id, 'Two sessions are working right now. ', 'One waits on you.'),
    });
    await talking.heard('  what is running  ');
    expect(daemon.sent('ask')[0]?.said).toBe('what is running');
    expect(speaker.said).toEqual(['Two sessions are working right now.', 'One waits on you.']);
    expect(talking.state.reply).toBe('Two sessions are working right now. One waits on you.');
  });

  it('answers nothing for noise the recognizer took for words', async () => {
    const { daemon, talking } = talkingOver({});
    await talking.heard(' . ');
    expect(daemon.requests).toEqual([]);
  });

  it('says so when Memnox cannot be reached', async () => {
    const { speaker, talking } = talkingOver({});
    await talking.heard('what is running');
    expect(speaker.said).toEqual([LINES.unreachable]);
    expect(talking.state.failure).toBe('Memnox could not be reached on this computer');
  });

  it('calls a daemon that does not know asking older than the app', async () => {
    const { speaker, talking } = talkingOver({ ask: (request) => [{ id: request.id, ok: false, error: 'no method ask' }] });
    await talking.heard('what is running');
    expect(speaker.said).toEqual([LINES.tooOld]);
  });

  it('hears the brain say the person is done or still talking', async () => {
    const { talking } = talkingOver({
      ask: (request) => [
        { id: request.id, ok: true, chunk: { kind: 'tool', tool: 'mcp__memnox-operator__end_conversation' } },
        { id: request.id, ok: true, chunk: { kind: 'done' } },
      ],
    });
    await talking.heard('thanks, that is all');
    expect(talking.takeEnd()).toBe(true);
    expect(talking.takeEnd()).toBe(false);
  });

  it('stops a turn that goes quiet and asks the brain to stop too', async () => {
    const timer = new HandTimer();
    const { daemon, speaker, talking } = talkingOver({ cancel: (request) => [{ id: request.id, ok: true }] }, new PersonKey(), timer);
    const scripted = daemon.stream.bind(daemon);
    // The ask answers nothing, ever, and the quiet limit runs out while it waits.
    daemon.stream = (request) => {
      if (request.method !== 'ask') return scripted(request);
      daemon.requests.push(request);
      setTimeout(() => timer.fireAll(), 0);
      return { [Symbol.asyncIterator]: () => ({ next: () => new Promise<IteratorResult<DaemonResponse>>(() => undefined) }) };
    };
    await talking.heard('what is running');
    expect(daemon.sent('cancel')).toHaveLength(1);
    expect(speaker.said).toEqual([LINES.stalled]);
  });
});

describe('a held call', () => {
  it('is told by the brain, and asked plainly when the brain cannot', async () => {
    const { speaker, talking } = talkingOver({ brief: (request) => [{ id: request.id, ok: true, chunk: { kind: 'done' } }] });
    await talking.handle(held('hld_1', { place: 'memnox-web', why: 'It reaches past its repository.' }));
    expect(speaker.said).toEqual([
      'codex on this computer in memnox-web wants to push to main. It reaches past its repository. Allow it, or deny?',
    ]);
  });

  it('is left unsaid when a phone asked for it', async () => {
    const { daemon, talking } = talkingOver({});
    await talking.handle(held('hld_1', { origin: { deviceId: 'dev_phone' } }));
    expect(daemon.requests).toEqual([]);
  });

  it('stops being asked once it is answered on the island', async () => {
    const { speaker, talking } = talkingOver({ brief: (request) => chunks(request.id, 'Codex wants to push to main.') });
    await talking.handle(held('hld_1'));
    talking.answeredByHand('hld_1');
    expect(speaker.stops).toBe(1);
  });
});

describe('a proposal', () => {
  const answering = {
    ask: (request: DaemonRequest) => chunks(request.id, 'Allowing the push.'),
    confirm: confirmedOk,
  };

  it('is confirmed with a signature over exactly it, after the person asked', async () => {
    const { daemon, key, talking } = talkingOver(answering);
    await talking.heard('yes, let it push');
    await talking.handle(proposal('prp_1'));
    expect(key.signed[0]?.message).toBe('memnox-confirm:v1:prp_1:confirmed');
    expect(daemon.sent('confirm')[0]).toMatchObject({ subject: 'prp_1', answer: 'confirmed', signature: 'sig(memnox-confirm:v1:prp_1:confirmed)' });
  });

  it('is declined, never signed, when nobody asked for it', async () => {
    const { daemon, key, speaker, talking } = talkingOver({ confirm: confirmedOk });
    await talking.handle(proposal('prp_1'));
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')[0]).toMatchObject({ answer: 'declined' });
    expect(daemon.sent('confirm')[0]?.signature).toBeUndefined();
    expect(speaker.said).toEqual([LINES.unasked]);
  });

  it('is declined once the person spoke too long ago', async () => {
    const { daemon, key, talking, later } = talkingOver(answering);
    await talking.heard('yes, let it push');
    later(ANSWER_WINDOW_MS);
    await talking.handle(proposal('prp_1'));
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')[0]?.answer).toBe('declined');
  });

  it('is declined when the person cancels the prompt', async () => {
    const { daemon, talking } = talkingOver(answering, new PersonKey('BPOINT', false));
    await talking.heard('yes, let it push');
    await talking.handle(proposal('prp_1'));
    expect(daemon.sent('confirm')[0]).toMatchObject({ answer: 'declined' });
  });

  it('is put to the key once, however often it arrives', async () => {
    const { key, talking } = talkingOver(answering);
    await talking.heard('yes, let it push');
    await talking.handle(proposal('prp_1'));
    await talking.handle(proposal('prp_1'));
    expect(key.signed).toHaveLength(1);
  });

  it('is left for the phone that asked for it, neither confirmed nor declined', async () => {
    const { daemon, talking } = talkingOver(answering);
    await talking.handle(proposal('prp_1', { origin: { deviceId: 'dev_phone' } }));
    expect(daemon.sent('confirm')).toEqual([]);
  });

  it('goes on its card when it is a rule, and nothing is signed until a place is picked', async () => {
    const daemon = new ScriptedDaemon({ 'register-key': registered, ask: (request) => chunks(request.id, 'Proposed.') });
    const speaker = new RecordingSpeaker();
    const ids = new RequestIds();
    const key = new PersonKey();
    const signer = new Signer(daemon, key, ids);
    const cards = new ProposalCards(daemon, signer, speaker, ids);
    const talking = new Talking(daemon, speaker, signer, ids, { timer: new HandTimer().start, cards });
    await talking.heard('always deny pushes to main here');
    await talking.handle(proposal('prp_1', { rule: { summary: 'Deny push', effect: 'deny', action: 'git.push', reason: 'asked', scopes: [] } }));
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')).toEqual([]);
    expect(cards.cards.map((card) => card.subject)).toEqual(['prp_1']);
    await talking.handle({ ...proposal('prp_1'), kind: 'settled' });
    expect(cards.cards).toEqual([]);
  });

  it('is left for a screen that has its card when it answers a teammate', async () => {
    const { daemon, key, speaker, talking } = talkingOver(answering);
    await talking.heard('allow it for Ana');
    await talking.handle(proposal('prp_1', { teamAnswer: {} as DaemonEvent['teamAnswer'] }));
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')).toEqual([]);
    expect(speaker.said).toContain(LINES.needsCard);
  });

  it('says the answer that came first when another route got there', async () => {
    const { speaker, talking } = talkingOver({
      ...answering,
      confirm: (request) => [{ id: request.id, ok: true, outcome: 'already declined' }],
    });
    await talking.heard('yes, let it push');
    await talking.handle(proposal('prp_1'));
    expect(speaker.said).toContain('That was already answered elsewhere: it was declined.');
  });
});
