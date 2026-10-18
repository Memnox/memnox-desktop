import { defaultDictationKey, type DictationKeyName } from '../domain/voice-keys';
import type { PreferenceStore } from './ports/preference-store';

/** The person's choices about the voice, each a switch, with the Mac's defaults. */
export interface VoiceChoices {
  /** Memnox speaks nothing; the words still show on the island. */
  readonly muted: boolean;
  readonly chimes: boolean;
  /** Listens for "Memnox" while idle, on this computer only. */
  readonly wake: boolean;
  /** Talking over the voice stops it. */
  readonly talkOver: boolean;
  /** The person's words show on the island as they say them. */
  readonly liveWords: boolean;
  /** News is said as well as shown, and not only what waits on them. */
  readonly speakUp: boolean;
  /** Right Alt dictates. */
  readonly dictation: boolean;
  /** Dictation is typed as it is said and revised in place. */
  readonly typesLive: boolean;
  /** Dictation is polished by the person's own Claude Code through the daemon. */
  readonly polish: boolean;
  /** Coming back to a locked screen after ten minutes, their brain says what waits on them. */
  readonly catchUp: boolean;
  /** Words go to an agent without bringing its window forward, where this desktop allows it. */
  readonly stayPut: boolean;
  /** The echo canceller runs on the microphone; off for a headset, where there is no echo to take out. */
  readonly echoCancel: boolean;
}

/** As the Mac registers its defaults in `AppDelegate`. */
export const VOICE_DEFAULTS: VoiceChoices = {
  muted: false,
  chimes: true,
  wake: false,
  talkOver: true,
  liveWords: true,
  speakUp: false,
  dictation: true,
  typesLive: true,
  polish: true,
  catchUp: true,
  stayPut: true,
  echoCancel: true,
};

const PREFIX = 'memnox.voice.';
/** The key picked to dictate with, apart from the switches since it is a name and not a yes or no. */
export const DICTATION_KEY = 'memnox.dictation.key';
/** Whether the keyboard's layout has AltGr, as the island last read it, so Settings shows the same default. */
export const ALTGR_KEY = 'memnox.keyboard.altGr';

/** The switches, kept between launches and observed, so the island, the menu and Settings show one truth. */
export class VoicePreferences {
  private current: VoiceChoices;
  private readonly listeners = new Set<() => void>();

  constructor(private readonly store: PreferenceStore) {
    const loaded: Partial<Record<keyof VoiceChoices, boolean>> = {};
    for (const key of Object.keys(VOICE_DEFAULTS) as (keyof VoiceChoices)[]) {
      const kept = safely(() => store.load(PREFIX + key));
      if (kept === 'true' || kept === 'false') loaded[key] = kept === 'true';
    }
    this.current = { ...VOICE_DEFAULTS, ...loaded };
  }

  get choices(): VoiceChoices {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  set(key: keyof VoiceChoices, on: boolean): void {
    if (this.current[key] === on) return;
    this.current = { ...this.current, [key]: on };
    safely(() => this.store.save(PREFIX + key, String(on)));
    for (const listener of this.listeners) listener();
  }

  toggle(key: keyof VoiceChoices): void {
    this.set(key, !this.current[key]);
  }

  /** The key that dictates: the one picked, else right Alt on a layout without AltGr and right Ctrl on one with it. */
  get dictationKey(): DictationKeyName {
    const picked = safely(() => this.store.load(DICTATION_KEY));
    if (picked === 'rightAlt' || picked === 'rightCtrl') return picked;
    return defaultDictationKey(safely(() => this.store.load(ALTGR_KEY)) === 'true');
  }

  pickDictationKey(key: DictationKeyName): void {
    safely(() => this.store.save(DICTATION_KEY, key));
    for (const listener of this.listeners) listener();
  }

  /** What the island read of the layout, which moves the default when nothing was picked. */
  layoutHasAltGr(has: boolean): void {
    if (safely(() => this.store.load(ALTGR_KEY)) === String(has)) return;
    safely(() => this.store.save(ALTGR_KEY, String(has)));
    for (const listener of this.listeners) listener();
  }
}

/** Storage can be refused, in a private window or a locked profile, and a choice then lasts the session. */
function safely<T>(read: () => T): T | undefined {
  try {
    return read();
  } catch {
    return undefined;
  }
}
