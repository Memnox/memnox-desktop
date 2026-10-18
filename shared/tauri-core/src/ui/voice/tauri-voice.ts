import { Channel, invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { Ear, EarEvent, Focus, KeyReport, PreferenceStore, Typist } from '../../core';
import type { Chimes } from '../../core/application/ports/chimes';
import type { Cue } from '../../core/domain/chimes';

/** The open ear in Rust: Silero and Parakeet on this computer, its events down one channel per opening. */
export class TauriEar implements Ear {
  async open(onEvent: (event: EarEvent) => void, options: { partials: boolean }): Promise<void> {
    const events = new Channel<EarEvent>();
    events.onmessage = onEvent;
    await invoke('ear_open', { events, partials: options.partials });
  }

  async close(): Promise<void> {
    await invoke('ear_close');
  }
}

/** What `focus_read` answers: the app, the field, and its text around the cursor when the platform can read it. */
interface FocusRead {
  app: string | null;
  title: string | null;
  secure: boolean;
  selection: string | null;
  value?: string | null;
  caret?: number | null;
  selectionEnd?: number | null;
}

/** The text before and after the cursor, and the whole field, when the platform read it; nothing otherwise. */
function fieldOf(read: FocusRead): Pick<Focus, 'before' | 'after' | 'value' | 'caret' | 'selectionEnd'> {
  const value = read.value ?? undefined;
  const caret = read.caret ?? undefined;
  if (value === undefined || caret === undefined || caret < 0 || caret > value.length) return {};
  const end = Math.min(Math.max(read.selectionEnd ?? caret, caret), value.length);
  return { value, caret, selectionEnd: end, before: value.slice(0, caret), after: value.slice(end) };
}

/** The platform layer in Rust that types into the app in front: SendInput on Windows, wtype, ydotool or xdotool on Linux. */
export class TauriTypist implements Typist {
  async focus(): Promise<Focus> {
    const read = await invoke<FocusRead>('focus_read');
    return {
      app: read.app ?? undefined,
      title: read.title ?? undefined,
      secure: read.secure,
      selection: read.selection ?? undefined,
      ...fieldOf(read),
    };
  }

  async type(text: string): Promise<void> {
    await invoke('type_text', { text });
  }

  async revise(remove: number, add: string): Promise<void> {
    await invoke('type_revise', { remove, add });
  }

  async copy(text: string): Promise<void> {
    await invoke('clipboard_set', { text });
  }
}

/** The nine cues, drawn in Rust at the Mac's quiet volume, on an output of their own. */
export class TauriChimes implements Chimes {
  play(cue: Cue): void {
    void invoke('chime', { cue }).catch(() => undefined);
  }
}

/** The webview's own storage, which lasts between launches of the app. */
export const localPreferences: PreferenceStore = {
  load: (key) => window.localStorage.getItem(key),
  save: (key, value) => window.localStorage.setItem(key, value),
};

/** The keyboard as Rust's watcher reports it, for the dictation and rule keys. */
export function onKeys(seen: (report: KeyReport) => void): () => void {
  const stop = listen<KeyReport>('keys', (event) => seen(event.payload));
  return () => void stop.then((unlisten) => unlisten(), () => undefined);
}

/** How loud Kokoro is playing, about thirty times a second while it speaks, for the orb's syllable rings. */
export function onVoiceLevel(heard: (level: number) => void): () => void {
  const stop = listen<number>('voice-level', (event) => heard(event.payload));
  return () => void stop.then((unlisten) => unlisten(), () => undefined);
}

/** Where Settings and the first run send a line to be said by the island: one line, or none for the voice test. */
export const SAY_EVENT = 'say';

/** A line to say from another window, or undefined for Say something's voice test. */
export function onSay(say: (line: string | undefined) => void): () => void {
  const stop = listen<{ line?: string | null } | null>(SAY_EVENT, (event) => say(event.payload?.line ?? undefined));
  return () => void stop.then((unlisten) => unlisten(), () => undefined);
}

/** The screen locking and unlocking, as Rust watches the session, for Catch me up. */
export function onPresence(seen: (now: 'locked' | 'unlocked') => void): () => void {
  const stop = listen<'locked' | 'unlocked'>('presence', (event) => seen(event.payload));
  return () => void stop.then((unlisten) => unlisten(), () => undefined);
}

/** The names the recognizer should listen for, handed to Parakeet's hotwords. */
export function hintNames(names: readonly string[]): void {
  void invoke('ear_hints', { names }).catch(() => undefined);
}

/** Whether the keys can be seen at all: not on a Wayland session without XWayland, which forbids it. */
export async function keysWatching(): Promise<{ watching: boolean; why: string | undefined }> {
  const answer = await invoke<{ watching: boolean; why: string | null }>('keys_watching').catch(() => ({ watching: false, why: null }));
  return { watching: answer.watching, why: answer.why ?? undefined };
}
