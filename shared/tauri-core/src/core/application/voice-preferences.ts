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
}

/** Storage can be refused, in a private window or a locked profile, and a choice then lasts the session. */
function safely<T>(read: () => T): T | undefined {
  try {
    return read();
  } catch {
    return undefined;
  }
}
