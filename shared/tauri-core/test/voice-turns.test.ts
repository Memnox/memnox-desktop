import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Mouth } from '../src/core/application/mouth';
import type { Ear, EarEvent } from '../src/core/application/ports/ear';
import type { Focus, Typist } from '../src/core/application/ports/typist';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { Talking, type Timer } from '../src/core/application/talking';
import { TalkOverWatch } from '../src/core/application/talk-over-watch';
import { VoicePreferences, type VoiceChoices } from '../src/core/application/voice-preferences';
import { CANNOT_HEAR, VoiceTurns } from '../src/core/application/voice-turns';
import type { Cue } from '../src/core/domain/chimes';
import { chunks, held, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

/** An ear that plays one script per opening, a little after it opens, and closes when asked. */
class ScriptedEar implements Ear {
  readonly opened: { partials: boolean }[] = [];
  private emit: ((event: EarEvent) => void) | undefined;

  constructor(private readonly scripts: (EarEvent | { wait: number })[][]) {}

  async open(onEvent: (event: EarEvent) => void, options: { partials: boolean }): Promise<void> {
    this.opened.push(options);
    this.emit = onEvent;
    const script = this.scripts.shift() ?? [];
    void (async () => {
      for (const step of script) {
        await new Promise((resolve) => setTimeout(resolve, 'wait' in step ? step.wait : 10));
        if (this.emit !== onEvent) return;
        if (!('wait' in step)) onEvent(step);
      }
    })();
  }

  async close(): Promise<void> {
    const emit = this.emit;
    this.emit = undefined;
    emit?.({ kind: 'closed' });
  }
}

const said = (text: string): EarEvent[] => [{ kind: 'speech' }, { kind: 'words', text, final: false }, { kind: 'words', text, final: true }];

class MemoryStore {
  private readonly kept = new Map<string, string>();
  load(key: string) {
    return this.kept.get(key) ?? null;
  }
  save(key: string, value: string) {
    this.kept.set(key, value);
  }
}

class RecordingTypist implements Typist {
  readonly typed: string[] = [];
  readonly copied: string[] = [];
  constructor(private readonly front: Focus) {}
  focus = async () => this.front;
  type = async (text: string) => void this.typed.push(text);
  revise = async (remove: number, add: string) => void this.typed.push(`-${remove}+${add}`);
  copy = async (text: string) => void this.copied.push(text);
}

const timer: Timer = (ms, fire) => {
  const handle = setTimeout(fire, ms);
  return () => clearTimeout(handle);
};

function turnsOver(scripts: (EarEvent | { wait: number })[][], answers: ConstructorParameters<typeof ScriptedDaemon>[0] = {}, choices: Partial<VoiceChoices> = {}, typist?: Typist) {
  const daemon = new ScriptedDaemon({ 'register-key': registered, cancel: (request) => [{ id: request.id, ok: true }], ...answers });
  const speaker = new RecordingSpeaker();
  const preferences = new VoicePreferences(new MemoryStore());
  for (const [key, on] of Object.entries({ talkOver: false, ...choices })) preferences.set(key as keyof VoiceChoices, on as boolean);
  const mouth = new Mouth(speaker, preferences);
  const cues: Cue[] = [];
  const chimes = { play: (cue: Cue) => void cues.push(cue) };
  const ids = new RequestIds();
  const talking = new Talking(daemon, mouth, new Signer(daemon, new PersonKey(), ids), ids, { timer, chimes, hour: () => 9 });
  const ear = new ScriptedEar(scripts);
  const turns = new VoiceTurns({ talking, mouth, ear, preferences, timer, chimes, typist });
  return { daemon, speaker, turns, ear, cues, preferences };
}

const ended = (request: DaemonRequest): DaemonResponse[] => [
  { id: request.id, ok: true, chunk: { kind: 'text', text: 'Two sessions are working. ' } },
  { id: request.id, ok: true, chunk: { kind: 'tool', tool: 'mcp__memnox-operator__end_conversation' } },
  { id: request.id, ok: true, chunk: { kind: 'done' } },
];

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('a turn of the person', () => {
  it('listens, sends what was said whole, answers, and closes when the brain says they are done', async () => {
    const { daemon, speaker, turns, cues } = turnsOver([said('what is running right now?')], { ask: ended });
    turns.talk();
    await vi.advanceTimersByTimeAsync(3_000);
    expect(daemon.sent('ask')[0]?.said).toBe('what is running right now?');
    expect(speaker.said).toEqual(['Two sessions are working.']);
    expect(cues).toEqual(['listening', 'sent', 'closed']);
    expect(turns.state.active).toBe(false);
  });

  it('listens again for a follow up, and puts the orb away once nothing more is said', async () => {
    const { daemon, turns, ear } = turnsOver([said('what changed today?'), []], { ask: (request) => chunks(request.id, 'Nothing yet.') });
    turns.talk();
    await vi.advanceTimersByTimeAsync(3_000);
    expect(ear.opened).toHaveLength(2);
    expect(turns.state.active).toBe(true);
    await vi.advanceTimersByTimeAsync(16_000);
    expect(daemon.sent('ask').filter((request) => request.speculative !== true)).toHaveLength(1);
    expect(turns.state.active).toBe(false);
  });

  it('shows the words as they are said while live words are on', async () => {
    const { turns } = turnsOver([[{ kind: 'speech' }, { kind: 'words', text: 'open the', final: false }, { wait: 5_000 }]]);
    turns.talk();
    await vi.advanceTimersByTimeAsync(100);
    expect(turns.state.live).toBe('open the');
    expect(turns.state.listening).toBe(true);
  });

  it('says so out loud when the microphone cannot be opened', async () => {
    const { speaker, turns, cues } = turnsOver([]);
    (turns as unknown as { parts: { ear: Ear } }).parts.ear.open = () => Promise.reject(new Error('this computer has no microphone'));
    turns.talk();
    await vi.advanceTimersByTimeAsync(100);
    expect(speaker.said).toEqual([CANNOT_HEAR]);
    expect(turns.state.problem).toBe('this computer has no microphone');
    expect(cues).toContain('failed');
  });
});

describe('its name', () => {
  it('answers being called by name alone like a person, then listens for the question', async () => {
    const { daemon, speaker, turns } = turnsOver([said('Memnox'), said('what changed?')], { ask: ended }, { wake: true });
    turns.listenForName();
    await vi.advanceTimersByTimeAsync(3_000);
    expect(speaker.said[0]).toMatch(/^Good morning\./);
    expect(daemon.sent('ask')[0]?.said).toBe('what changed?');
  });

  it('hands what followed its name whole to ask', async () => {
    const { daemon, turns } = turnsOver([said('Hey Memnox, is the build green?')], { ask: ended }, { wake: true });
    turns.listenForName();
    await vi.advanceTimersByTimeAsync(3_000);
    expect(daemon.sent('ask')[0]?.said).toBe('is the build green?');
  });
});

describe('saying a rule', () => {
  it('listens while Control and Alt are held and asks with the rule intent', async () => {
    const { daemon, turns } = turnsOver([[{ kind: 'speech' }, { kind: 'words', text: 'never push to main', final: true }, { wait: 60_000 }]], { ask: ended });
    turns.keys({ kind: 'modifiers', ctrl: true, leftAlt: true, rightAlt: false, shift: false, meta: false });
    await vi.advanceTimersByTimeAsync(400);
    expect(turns.state.ruling).toBe(true);
    await vi.advanceTimersByTimeAsync(500);
    turns.keys({ kind: 'modifiers', ctrl: false, leftAlt: false, rightAlt: false, shift: false, meta: false });
    await vi.advanceTimersByTimeAsync(3_000);
    const ask = daemon.sent('ask')[0];
    expect(ask?.said).toBe('never push to main');
    expect(ask?.intent).toBe('rule');
    expect(ask?.finished).toBe(true);
  });
});

describe('dictation', () => {
  const press = (turns: VoiceTurns, rightAlt: boolean) => turns.keys({ kind: 'modifiers', ctrl: false, leftAlt: false, rightAlt, shift: false, meta: false });

  it('writes what was said where the cursor is, cleaned for the app in front', async () => {
    const typist = new RecordingTypist({ app: 'slack', secure: false });
    const { turns, daemon } = turnsOver([[{ kind: 'speech' }, { kind: 'words', text: 'um on my way', final: true }, { wait: 60_000 }]], {}, { typesLive: false, polish: false }, typist);
    press(turns, true);
    await vi.advanceTimersByTimeAsync(300);
    expect(turns.state.dictating).toBe('Speak, and it types where your cursor is');
    await vi.advanceTimersByTimeAsync(500);
    press(turns, false);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(typist.typed).toEqual(['On my way']);
    expect(daemon.sent('ask')).toEqual([]);
    expect(turns.state.dictating).toBeUndefined();
  });

  it('types live as it is said and revises the end in place', async () => {
    const typist = new RecordingTypist({ app: 'code', secure: false });
    const { turns } = turnsOver(
      [[{ kind: 'speech' }, { kind: 'words', text: 'send the repo ', final: false }, { kind: 'words', text: 'send the report to Sam', final: true }, { wait: 60_000 }]],
      {},
      { polish: false },
      typist,
    );
    press(turns, true);
    await vi.advanceTimersByTimeAsync(800);
    press(turns, false);
    await vi.advanceTimersByTimeAsync(2_000);
    // The word still being said waits, and every change after only types what differs.
    expect(typist.typed[0]).toBe('-0+Send the');
    const field = typist.typed.reduce((text, change) => {
      const [, remove, add] = /^-(\d+)\+(.*)$/s.exec(change) ?? [];
      return text.slice(0, text.length - Number(remove)) + (add ?? '');
    }, '');
    expect(field).toBe('Send the report to Sam');
  });

  it('never writes into a password field', async () => {
    const typist = new RecordingTypist({ app: 'chrome', secure: true });
    const { turns, cues, ear } = turnsOver([said('my password')], {}, {}, typist);
    press(turns, true);
    await vi.advanceTimersByTimeAsync(800);
    press(turns, false);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(typist.typed).toEqual([]);
    expect(ear.opened).toEqual([]);
    expect(cues).toEqual(['failed']);
  });

  it('leaves the words on the clipboard when the app left the front', async () => {
    let front: Focus = { app: 'slack', secure: false };
    const typist = new RecordingTypist(front);
    typist.focus = async () => front;
    const { turns } = turnsOver([[{ kind: 'speech' }, { kind: 'words', text: 'on my way', final: true }, { wait: 60_000 }]], {}, { typesLive: false, polish: false }, typist);
    press(turns, true);
    await vi.advanceTimersByTimeAsync(800);
    front = { app: 'explorer', secure: false };
    press(turns, false);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(typist.typed).toEqual([]);
    expect(typist.copied).toEqual(['On my way']);
  });
});

describe('what waits on the person', () => {
  it('says a held call and keeps the microphone open for the spoken answer', async () => {
    const { turns, ear, daemon } = turnsOver([[]], { brief: (request) => chunks(request.id, 'Codex wants to push to main. Allow it, or deny?') });
    turns.arrived(held('hld_1'));
    await vi.advanceTimersByTimeAsync(500);
    expect(daemon.sent('brief')).toHaveLength(1);
    expect(ear.opened).toHaveLength(1);
    expect(turns.state.active).toBe(true);
  });

  it('says news only when Speak up is on', async () => {
    const news = { ...held('ntc_1'), kind: 'notice' as const, notice: 'finished' };
    const quiet = turnsOver([], { brief: (request) => chunks(request.id, 'Done.') });
    quiet.turns.arrived(news);
    await vi.advanceTimersByTimeAsync(500);
    expect(quiet.daemon.sent('brief')).toHaveLength(0);
    const loud = turnsOver([], { brief: (request) => chunks(request.id, 'Done.') }, { speakUp: true });
    loud.turns.arrived(news);
    await vi.advanceTimersByTimeAsync(500);
    expect(loud.daemon.sent('brief')).toHaveLength(1);
    expect(loud.turns.state.active).toBe(false);
  });
});

describe('the mute', () => {
  it('drops every sentence and stops the one playing, while the words still show', async () => {
    const { speaker, turns, preferences } = turnsOver([said('what changed?')], { ask: ended }, { muted: true });
    turns.talk();
    await vi.advanceTimersByTimeAsync(3_000);
    expect(speaker.said).toEqual([]);
    preferences.set('muted', false);
    preferences.set('muted', true);
    expect(speaker.stops).toBeGreaterThan(0);
  });
});

describe('talking over the voice', () => {
  function watching() {
    let now = 0;
    let speaking = true;
    const happened: string[] = [];
    const watch = new TalkOverWatch({
      spoken: () => 'Claude Code finished setting up the voice picker in memnox macos',
      speaking: () => speaking,
      hush: () => happened.push('hush'),
      carryOn: () => happened.push('carry on'),
      cutIn: () => happened.push('cut in'),
      now: () => now,
    });
    return { watch, happened, later: (ms: number) => (now += ms), quiet: () => (speaking = false) };
  }

  it('pauses on their first words, stops once more come, and hands over only their sentence', () => {
    const { watch, happened, later } = watching();
    watch.heard('Claude Code finished setting why not', false);
    later(120);
    expect(watch.look()).toBeUndefined();
    expect(happened).toEqual(['hush']);
    watch.heard('Claude Code finished setting why not open the billing session', true);
    later(120);
    // The two words it paused on were already theirs, so they open what is handed over.
    expect(watch.look()).toBe('why not open the billing session');
    expect(happened).toEqual(['hush', 'cut in']);
  });

  it('carries on when it paused on its own words and the room went quiet', () => {
    const { watch, happened, later } = watching();
    watch.heard('Claude Code finished setting why not', false);
    later(120);
    watch.look();
    later(1_200);
    watch.level(0.05, 0);
    expect(watch.look()).toBeUndefined();
    expect(happened).toEqual(['hush', 'carry on']);
  });

  it('never cuts in on its own words heard back', () => {
    const { watch, happened, later } = watching();
    watch.heard('Claude Code finished setting up the voice', true);
    later(120);
    expect(watch.look()).toBeUndefined();
    expect(happened).toEqual([]);
  });
});

describe("a phone's turn", () => {
  it('is put together from its notices, shown without a sound, and put away a moment after it ends', async () => {
    const { turns, speaker, daemon } = turnsOver([]);
    const phone = { deviceId: 'dev_1', name: "Ana's iPhone" };
    const notice = (turn: object) => turns.arrived({ kind: 'notice', subject: 'ask_1', agent: 'memnox', summary: 's', at: 't', phoneTurn: { ...phone, ...turn } });
    notice({ said: 'what changed?' });
    notice({ answer: 'Two files. ' });
    notice({ answer: 'Both pass.', ended: true });
    expect(turns.state.phone?.label).toBe("From Ana's iPhone");
    expect(turns.state.phone?.exchange).toMatchObject({ question: 'what changed?', answer: 'Two files. Both pass.' });
    expect(turns.state.phone?.exchange.answeredAt).toBeDefined();
    expect(speaker.said).toEqual([]);
    expect(daemon.requests).toEqual([]);
    await vi.advanceTimersByTimeAsync(8_000);
    expect(turns.state.phone).toBeUndefined();
  });
});
