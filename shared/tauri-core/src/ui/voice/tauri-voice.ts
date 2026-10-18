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

/** The platform layer in Rust that types into the app in front: SendInput on Windows, wtype, ydotool or xdotool on Linux. */
export class TauriTypist implements Typist {
  async focus(): Promise<Focus> {
    const read = await invoke<{ app: string | null; title: string | null; secure: boolean; selection: string | null }>('focus_read');
    return { app: read.app ?? undefined, title: read.title ?? undefined, secure: read.secure, selection: read.selection ?? undefined };
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

/** Whether the keys can be seen at all: not on a Wayland session without XWayland, which forbids it. */
export async function keysWatching(): Promise<{ watching: boolean; why: string | undefined }> {
  const answer = await invoke<{ watching: boolean; why: string | null }>('keys_watching').catch(() => ({ watching: false, why: null }));
  return { watching: answer.watching, why: answer.why ?? undefined };
}
