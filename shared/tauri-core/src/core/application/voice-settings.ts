import { DAEMON_METHOD, type DaemonRequest, type VoiceAgentStatus } from '@memnox/core/wire';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { PreferenceStore } from './ports/preference-store';
import type { RequestIds } from './request-ids';

/**
 * The switches on the Listening and Dictation pages, by the key each is kept under in the shared store, so
 * the voice reads exactly what Settings wrote. Each is "true" or "false"; a key never written takes its default.
 */
export const VOICE_PREFERENCE = {
  /** Wake when I say "Memnox". */
  wakeWord: 'memnox.voice.wakeWord',
  /** Talk over it: cut in just by speaking. */
  talkOver: 'memnox.voice.talkOver',
  /** Live words: see what you say in the island. */
  liveWords: 'memnox.voice.liveWords',
  /** Stay where I am: agents get the words without taking the window. */
  stayWhereIAm: 'memnox.voice.stayWhereIAm',
  /** Mute the voice: answers still show in the island. */
  muted: 'memnox.voice.muted',
  /** Speak up on its own when work finishes or ships. */
  speakUp: 'memnox.voice.speakUp',
  /** A chime when something happens. */
  sounds: 'memnox.voice.sounds',
  /** Catch me up on what the agents did while the person was away. */
  catchUp: 'memnox.voice.catchUp',
  /** Dictate anywhere with the dictation key. */
  dictateAnywhere: 'memnox.dictation.enabled',
  /** Type as I speak: words appear at the cursor while the person talks. */
  typeAsISpeak: 'memnox.dictation.live',
  /** Polish with the person's own agent, rather than tidying alone. */
  polish: 'memnox.dictation.polish',
} as const;

export type VoicePreference = keyof typeof VOICE_PREFERENCE;

/** The Mac's defaults: everything that helps on, waking by name off until asked, since it listens all the time. */
export const VOICE_PREFERENCE_DEFAULTS: Record<VoicePreference, boolean> = {
  wakeWord: false,
  talkOver: true,
  liveWords: true,
  stayWhereIAm: false,
  muted: false,
  speakUp: true,
  sounds: true,
  catchUp: true,
  dictateAnywhere: true,
  typeAsISpeak: true,
  polish: true,
};

/** The person's own spellings, kept as JSON under this key: what they say and how it is written. */
export const DICTIONARY_KEY = 'memnox.dictation.words';
/** What was dictated lately, newest first, kept as JSON under this key so one that went nowhere can be copied. */
export const DICTATION_HISTORY_KEY = 'memnox.dictation.history';

/** A word the person wants spelled their way; `said` is absent when it is only a spelling to keep. */
export interface DictionaryWord {
  readonly said?: string;
  readonly written: string;
}

/** One dictation as it was typed, where, and when, in epoch milliseconds. */
export interface DictationEntry {
  readonly written: string;
  readonly app?: string;
  readonly at: number;
}

/** How many dictations are kept, enough to find the one that went nowhere. */
const HISTORY_KEPT = 50;

/** The switches, the dictionary and the history, read and written through the store every window shares. */
export class VoicePreferences {
  constructor(private readonly store: PreferenceStore) {}

  isOn(name: VoicePreference): boolean {
    const stored = this.store.load(VOICE_PREFERENCE[name]);
    return stored === 'true' ? true : stored === 'false' ? false : VOICE_PREFERENCE_DEFAULTS[name];
  }

  set(name: VoicePreference, on: boolean): void {
    this.store.save(VOICE_PREFERENCE[name], on ? 'true' : 'false');
  }

  words(): readonly DictionaryWord[] {
    return listOf<DictionaryWord>(this.store.load(DICTIONARY_KEY)).filter((word) => typeof word.written === 'string' && word.written.trim() !== '');
  }

  /** Adds a spelling, replacing one for the same words said, so a fix overrides the word it fixes. */
  addWord(said: string, written: string): void {
    const kept = written.trim();
    if (kept === '') return;
    const heard = said.trim();
    const word: DictionaryWord = heard === '' ? { written: kept } : { said: heard, written: kept };
    const others = this.words().filter((each) => (heard === '' ? each.written !== kept : each.said !== heard));
    this.store.save(DICTIONARY_KEY, JSON.stringify([...others, word]));
  }

  removeWord(word: DictionaryWord): void {
    this.store.save(DICTIONARY_KEY, JSON.stringify(this.words().filter((each) => each.said !== word.said || each.written !== word.written)));
  }

  history(): readonly DictationEntry[] {
    return listOf<DictationEntry>(this.store.load(DICTATION_HISTORY_KEY))
      .filter((entry) => typeof entry.written === 'string' && typeof entry.at === 'number')
      .sort((a, b) => b.at - a.at);
  }

  /** Keeps one dictation, newest first, dropping the oldest past what is kept. */
  remember(entry: DictationEntry): void {
    this.store.save(DICTATION_HISTORY_KEY, JSON.stringify([entry, ...this.history()].slice(0, HISTORY_KEPT)));
  }

  clearHistory(): void {
    this.store.save(DICTATION_HISTORY_KEY, '[]');
  }
}

/** A JSON list from the store, or none when it is missing or not a list. */
function listOf<T>(text: string | null): T[] {
  if (text === null || text === '') return [];
  try {
    const parsed: unknown = JSON.parse(text);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

/** The agents the voice can think with, preferred first, or why the daemon could not say. */
export type VoiceAgents = { kind: 'listed'; agents: readonly VoiceAgentStatus[] } | { kind: 'failed'; why: string };

/** Which of the person's own agents the voice thinks with, chosen in settings and kept by the daemon. */
export class VoiceSettings {
  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {}

  /** Every agent the voice knows; `recheck` asks each installed agent again rather than answering from the last check. */
  agents(recheck = false): Promise<VoiceAgents> {
    const request: DaemonRequest = { id: this.ids.next(), method: DAEMON_METHOD.VOICE_AGENTS };
    if (recheck) request.recheck = true;
    return this.answer(request);
  }

  choose(kind: string): Promise<VoiceAgents> {
    return this.answer({ id: this.ids.next(), method: DAEMON_METHOD.CHOOSE_VOICE_AGENT, voiceAgent: kind });
  }

  /** Tells the daemon the natural voice picked, so a paired phone speaks with it too. */
  async tellVoice(voice: string): Promise<void> {
    await requestOnce(this.link, { id: this.ids.next(), method: DAEMON_METHOD.VOICE_CHOICE, voice }).catch(() => undefined);
  }

  private async answer(request: DaemonRequest): Promise<VoiceAgents> {
    const response = await requestOnce(this.link, request).catch(() => undefined);
    if (response === undefined) return { kind: 'failed', why: 'Memnox did not answer' };
    if (!response.ok || response.voiceAgents === undefined) return { kind: 'failed', why: response.error ?? 'Memnox did not say' };
    return { kind: 'listed', agents: response.voiceAgents };
  }
}
