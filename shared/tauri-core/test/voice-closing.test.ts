import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Mouth } from '../src/core/application/mouth';
import type { Ear, EarEvent } from '../src/core/application/ports/ear';
import type { Focus, Typist } from '../src/core/application/ports/typist';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { Talking, type Timer } from '../src/core/application/talking';
import { VoicePreferences, type VoiceChoices } from '../src/core/application/voice-preferences';
import { VOICE_TEST, VoiceTurns, type VoiceTurnsParts } from '../src/core/application/voice-turns';
import { correctedWords } from '../src/core/domain/corrections';
import { pronounced } from '../src/core/domain/pronounce';
import { chosenHints } from '../src/core/domain/recognizer-hints';
import { repeats } from '../src/core/domain/repeats';
import { speakable } from '../src/core/domain/speakable';
import { mayGuess } from '../src/core/domain/turn-taking';
import { chunks, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

describe('what a voice says', () => {
  it('reads the names, files, flags and abbreviations of an agent the way a person says them', () => {
    expect(pronounced('Run npm test in Speech.swift with --force')).toBe('Run N P M test in Speech dot swift with dash dash force');
    expect(pronounced('Open https://www.github.com/memnox/app now.')).toBe('Open github dot com now.');
    expect(pronounced('memnox-runtime v1.2.3 on feat/voice-answers')).toBe('memnox runtime 1 point 2 point 3 on feature voice answers');
    expect(pronounced('Two PRs wait on the CI')).toBe("Two P R's wait on the C I");
    expect(pronounced('It took 40ms and fixed #12')).toBe('It took 40 milliseconds and fixed number 12');
  });

  it('drops markdown and puts a pause where a dash stood', () => {
    expect(speakable('**Done** — the `build` is green')).toBe('Done, the build is green');
  });

  it('lets a sentence told again around a tool go', () => {
    expect(repeats('I will tell you when Codex finishes.', ['I will tell you when Codex finishes.'])).toBe(true);
    expect(repeats('I will tell you the moment Codex finishes.', ['I will tell you when Codex finishes.'])).toBe(false);
    expect(repeats('Yes.', ['No.'])).toBe(false);
  });
});

describe('what the person fixed', () => {
  it('learns a word swapped for one that sounds alike, and nothing from a rewrite', () => {
    expect(correctedWords('show the surgeons', 'show the sessions')).toEqual([{ heard: 'surgeons', meant: 'sessions' }]);
    expect(correctedWords('deploy it to right away', 'deploy it to Railway')).toEqual([{ heard: 'right away', meant: 'Railway' }]);
    expect(correctedWords('send the report', 'never mind, I will call')).toEqual([]);
    expect(correctedWords('send the report', 'Send the report.')).toEqual([]);
  });

  it('keeps hints once each and few', () => {
    expect(chosenHints([['Memnox', 'codex'], ['Codex', 'Railway']])).toEqual(['Memnox', 'codex', 'Railway']);
    expect(chosenHints([['a', 'b', 'c']], 2)).toEqual(['a', 'b']);
  });

  it('guesses at a short pause after a whole thought, never while they trail off', () => {
    expect(mayGuess('what is running right now?', 400)).toBe(true);
    expect(mayGuess('what is running and', 400)).toBe(false);
    expect(mayGuess('what is running right now?', 200)).toBe(false);
  });
});

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

class MemoryStore {
  private readonly kept = new Map<string, string>();
  load(key: string) {
    return this.kept.get(key) ?? null;
  }
  save(key: string, value: string) {
    this.kept.set(key, value);
  }
}

const timer: Timer = (ms, fire) => {
  const handle = setTimeout(fire, ms);
  return () => clearTimeout(handle);
};

function voiceOver(
  scripts: (EarEvent | { wait: number })[][],
  answers: Partial<Record<string, (request: DaemonRequest) => DaemonResponse[]>> = {},
  choices: Partial<VoiceChoices> = {},
  extra: Partial<VoiceTurnsParts> = {},
) {
  const daemon = new ScriptedDaemon({ 'register-key': registered, cancel: (request) => [{ id: request.id, ok: true }], ...answers });
  const speaker = new RecordingSpeaker();
  const preferences = new VoicePreferences(new MemoryStore());
  for (const [key, on] of Object.entries({ talkOver: false, ...choices })) preferences.set(key as keyof VoiceChoices, on as boolean);
  const mouth = new Mouth(speaker, preferences);
  const ids = new RequestIds();
  const talking = new Talking(daemon, mouth, new Signer(daemon, new PersonKey(), ids), ids, { timer, hour: () => 9 });
  const turns = new VoiceTurns({ talking, mouth, ear: new ScriptedEar(scripts), preferences, timer, ...extra });
  return { daemon, speaker, turns, talking, preferences };
}

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('the turns the voice takes', () => {
  it('sends the words so far as a guess at a pause, then the same words whole, and warms the brain first', async () => {
    const { daemon, turns } = voiceOver([[{ kind: 'speech' }, { kind: 'words', text: 'is the build green?', final: true }, { wait: 60_000 }]], {
      ask: (request) => chunks(request.id, 'It is.'),
      warm: (request) => [{ id: request.id, ok: true }],
    });
    turns.talk();
    await vi.advanceTimersByTimeAsync(3_000);
    const asks = daemon.sent('ask');
    expect(asks[0]).toMatchObject({ said: 'is the build green?', speculative: true });
    expect(asks[1]?.said).toBe('is the build green?');
    expect(asks[1]?.speculative).toBeUndefined();
    expect(daemon.sent('warm')).toHaveLength(1);
  });

  it('learns the names of this machine for the recognizer at each listen', async () => {
    const hinted: (readonly string[])[] = [];
    const { turns } = voiceOver([[]], { vocabulary: (request) => [{ id: request.id, ok: true, words: ['Hermes', 'memnox', 'Kubernetes'] }] }, {}, { hints: (names) => hinted.push(names) });
    turns.talk();
    await vi.advanceTimersByTimeAsync(100);
    expect(hinted[0]).toContain('Kubernetes');
    expect(hinted[0]?.filter((name) => name.toLowerCase() === 'memnox')).toHaveLength(1);
  });

  it('tests the voice through the mouth, so the mute holds and the orb says what it is doing', async () => {
    const { speaker, turns, preferences } = voiceOver([]);
    let caption: string | undefined;
    turns.observe(() => (caption ??= turns.state.caption));
    turns.saySomething();
    await vi.advanceTimersByTimeAsync(10);
    expect(speaker.said).toEqual([VOICE_TEST]);
    expect(caption).toBe('Testing my voice');
    preferences.set('muted', true);
    turns.saySomething();
    await vi.advanceTimersByTimeAsync(10);
    expect(speaker.said).toHaveLength(1);
  });

  it('catches the person up after ten minutes behind a locked screen, and not after two', async () => {
    let now = 0;
    const { daemon, turns } = voiceOver([[]], { brief: (request) => chunks(request.id, 'Codex finished.') }, {}, { now: () => now });
    turns.locked();
    now = 2 * 60_000;
    turns.unlocked();
    await vi.advanceTimersByTimeAsync(100);
    expect(daemon.sent('brief')).toHaveLength(0);
    turns.locked();
    now += 11 * 60_000;
    turns.unlocked();
    await vi.advanceTimersByTimeAsync(100);
    expect(daemon.sent('brief')[0]).toMatchObject({ briefing: 'back', since: new Date(2 * 60_000).toISOString() });
  });

  it('never opens the answer window for a question asked again after a sign in', async () => {
    const { daemon, talking } = voiceOver([], { ask: (request) => chunks(request.id, 'Done.'), confirm: (request) => [{ id: request.id, ok: true }] });
    await talking.heard('send the mail', true, { intent: 'resume' });
    await talking.handle({ kind: 'proposal', subject: 'prp_1', agent: 'memnox', summary: 'send the mail', what: 'send', at: '2026-10-18T10:00:00.000Z' });
    expect(daemon.sent('confirm')[0]?.answer).toBe('declined');
  });
});

class FieldTypist implements Typist {
  readonly typed: string[] = [];
  constructor(public front: Focus) {}
  focus = async () => this.front;
  type = async (text: string) => {
    this.typed.push(text);
  };
  revise = async () => undefined;
  copy = async () => undefined;
}

describe('dictation', () => {
  const press = (turns: VoiceTurns, rightAlt: boolean) => turns.keys({ kind: 'modifiers', ctrl: false, leftAlt: false, rightAlt, shift: false, meta: false });

  it('uses the dictionary, fits the words to the cursor, keeps the history and learns a fix made after', async () => {
    const typist = new FieldTypist({ app: 'slack', secure: false, value: 'Hello Sam.', caret: 10, before: 'Hello Sam.', after: '' });
    const kept: { written: string; app: string | undefined }[] = [];
    const learnt: string[] = [];
    const { turns, daemon } = voiceOver(
      [[{ kind: 'speech' }, { kind: 'words', text: 'my email is ready for the surgeons', final: true }, { wait: 60_000 }]],
      { 'learn-words': (request) => [{ id: request.id, ok: true, words: [] }] },
      { typesLive: false, polish: false },
      {
        typist,
        dictionary: () => ({ spellings: [], replacements: [{ said: 'my email', written: 'sam@memnox.com' }] }),
        dictated: (entry) => kept.push(entry),
        corrected: (corrections) => learnt.push(...corrections.map((each) => `${each.heard}>${each.meant}`)),
      },
    );
    press(turns, true);
    await vi.advanceTimersByTimeAsync(800);
    press(turns, false);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(typist.typed).toEqual([' Sam@memnox.com is ready for the surgeons']);
    expect(kept).toEqual([{ heard: 'my email is ready for the surgeons', written: ' Sam@memnox.com is ready for the surgeons', app: 'slack' }]);
    typist.front = { app: 'slack', secure: false, value: 'Hello Sam. Sam@memnox.com is ready for the sessions' };
    await vi.advanceTimersByTimeAsync(21_000);
    expect(learnt).toEqual(['surgeons>sessions']);
    expect(daemon.sent('learn-words')[0]?.learned).toEqual([{ heard: 'surgeons', meant: 'sessions' }]);
  });
});

describe('the keys the desktop allows', () => {
  const ctrlReport = (rightCtrl: boolean) => ({ kind: 'modifiers' as const, ctrl: rightCtrl, leftCtrl: false, rightCtrl, leftAlt: false, rightAlt: false, shift: false, meta: false });

  it('dictates with right Ctrl on a layout with AltGr, and with right Alt where nothing was picked on one without', async () => {
    const typist = new FieldTypist({ app: 'slack', secure: false });
    const { turns, preferences } = voiceOver([[{ kind: 'speech' }, { kind: 'words', text: 'on my way', final: true }, { wait: 60_000 }]], {}, { typesLive: false, polish: false }, { typist });
    expect(preferences.dictationKey).toBe('rightAlt');
    turns.layout(true);
    expect(preferences.dictationKey).toBe('rightCtrl');
    turns.keys(ctrlReport(true));
    await vi.advanceTimersByTimeAsync(800);
    turns.keys(ctrlReport(false));
    await vi.advanceTimersByTimeAsync(2_000);
    expect(typist.typed).toEqual(['On my way']);
    preferences.pickDictationKey('rightAlt');
    expect(preferences.dictationKey).toBe('rightAlt');
  });

  it('holds a rule and dictation from shortcuts bound through the portal', async () => {
    const typist = new FieldTypist({ app: 'slack', secure: false });
    const { turns } = voiceOver([[{ kind: 'speech' }, { kind: 'words', text: 'on my way', final: true }, { wait: 60_000 }]], {}, { typesLive: false, polish: false }, { typist });
    turns.keys({ kind: 'dictate', down: true });
    await vi.advanceTimersByTimeAsync(800);
    turns.keys({ kind: 'dictate', down: false });
    await vi.advanceTimersByTimeAsync(2_000);
    expect(typist.typed).toEqual(['On my way']);
    turns.keys({ kind: 'rule', down: true });
    await vi.advanceTimersByTimeAsync(400);
    expect(turns.holdKeys.holding).toBe(true);
    turns.keys({ kind: 'rule', down: false });
    expect(turns.holdKeys.holding).toBe(false);
  });
});

describe('the microphone', () => {
  it('says why it cannot hear before listening when the privacy switch keeps the microphone away', async () => {
    const { speaker, turns } = voiceOver([[]], {}, {}, { microphone: async () => 'denied' });
    turns.talk();
    await vi.advanceTimersByTimeAsync(100);
    expect(speaker.said[0]).toContain('Let desktop apps use the microphone');
    expect(turns.state.active).toBe(false);
    expect(turns.state.problem).toBe('Memnox may not use the microphone');
  });
});
