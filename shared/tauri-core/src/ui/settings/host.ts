import { invoke, Channel } from '@tauri-apps/api/core';
import { emit, listen } from '@tauri-apps/api/event';
import type { PreferenceStore } from '../../core/application/ports/preference-store';
import type { Look } from '../../core/domain/appearance';
import type { PermissionFacts, PrivacyPane } from '../../core/domain/permission-steps';
import { platformOf, type Platform } from '../../core/domain/platform';
import { SAY_EVENT } from '../voice/tauri-voice';

/** One step of the natural voice installing, as Rust reports it. */
export interface InstallProgress {
  part: string;
  done: number;
  total: number | null;
}

/**
 * What the Settings window and the first run need from the computer beyond the daemon: the facts about
 * permissions, the other windows, the browser, the clipboard and the voice. The app hands in Tauri; the
 * preview hands in a script, so every page draws in a plain browser.
 */
export interface SettingsHost {
  readonly platform: Platform;
  /** What the console lists this computer as, when the system says. */
  computerName(): string | undefined;
  permissionFacts(): Promise<PermissionFacts>;
  openPrivacy(pane: PrivacyPane): Promise<boolean>;
  startsAtSignIn(): Promise<boolean>;
  setStartsAtSignIn(on: boolean): Promise<boolean>;
  restart(): void;
  openPage(url: string): void;
  openSettings(page?: string): void;
  openOnboarding(): void;
  /** The first run's window over the whole screen for the opening, or the steps window after it; nothing in a preview. */
  onboardingVeil?(on: boolean): void;
  close(): void;
  /** Paints the frame of every window but the island in the look; the pages repaint from the store. */
  applyLook(look: Look): void;
  /** Starts a talk on the island, as the talk key does; `rule` asks for one in rule mode. */
  talk(intent?: 'rule'): void;
  copy(text: string): Promise<void>;
  /** Has the island copy its diary of steps with these lines after it, as the Mac's Copy what happened; without it, only these lines are copied. */
  copyWhatHappened?(more: string): Promise<void>;
  /** Told when the island or the tray asks this window for one page. */
  onShowPage(listener: (page: string) => void): () => void;
  readonly voices: {
    choice(): Promise<{ voices: string[]; chosen: string | null }>;
    choose(id: string): Promise<void>;
    installed(): Promise<boolean>;
    install(onStep: (step: InstallProgress) => void): Promise<void>;
    /** Said by the island in its turn, so the mute holds and the island's echo memory hears it. */
    say(sentence: string): Promise<void>;
    /** Say something: the island tests the voice on its own, with "Testing my voice" on the orb. */
    test(): Promise<void>;
    /** Stops what the voice is saying and drops what waits, so a new line is not queued behind an old one. */
    stop?(): Promise<void>;
  };
}

/** The real computer, through the commands `settings_windows.rs`, `permissions.rs` and `voice.rs` give. */
export const tauriHost: SettingsHost = {
  platform: platformOf(navigator.userAgent),
  computerName: () => undefined,
  permissionFacts: () => invoke<PermissionFacts>('permission_facts'),
  openPrivacy: (pane) => invoke<boolean>('open_privacy', { pane }),
  startsAtSignIn: () => invoke<boolean>('start_at_sign_in'),
  setStartsAtSignIn: (on) => invoke<boolean>('set_start_at_sign_in', { on }),
  restart: () => void invoke('restart_memnox'),
  openPage: (url) => void invoke('open_page', { url }).catch(() => undefined),
  openSettings: (page) => void invoke('open_settings', { page: page ?? null }),
  openOnboarding: () => void invoke('open_onboarding'),
  onboardingVeil: (on) => void invoke('onboarding_veil', { on }).catch(() => undefined),
  close: () => void invoke('close_window'),
  applyLook: (look) => void invoke('apply_appearance', { look }).catch(() => undefined),
  talk: (intent) => void emit('talk', intent === undefined ? null : { intent }),
  copy: (text) => navigator.clipboard.writeText(text),
  // The island keeps the diary, so it is the one that copies; the name matches `COPY_WHAT_HAPPENED_EVENT`.
  copyWhatHappened: (more) => emit('copy-what-happened', more),
  onShowPage: (listener) => {
    const stop = listen<string>('settings-page', (event) => listener(event.payload));
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },
  voices: {
    choice: () => invoke<{ voices: string[]; chosen: string | null }>('voice_choice'),
    choose: (id) => invoke<void>('choose_voice', { id }),
    installed: () => invoke<boolean>('voice_installed'),
    install: (onStep) => {
      const steps = new Channel<InstallProgress>();
      steps.onmessage = onStep;
      return invoke('voice_install', { steps });
    },
    say: (sentence) => emit(SAY_EVENT, { line: sentence }),
    test: () => emit(SAY_EVENT, { line: null }),
    stop: () => invoke<void>('speak_stop'),
  },
};

/**
 * The webview's own storage, which every window of the app shares: Settings writes a switch and the island
 * reads it. A storage event tells the other windows, so a page redraws without being reopened.
 */
export class LocalPreferenceStore implements PreferenceStore {
  load(key: string): string | null {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  save(key: string, value: string): void {
    try {
      if (value === '') window.localStorage.removeItem(key);
      else window.localStorage.setItem(key, value);
      window.dispatchEvent(new CustomEvent(CHANGED, { detail: key }));
    } catch {
      // A store that will not write keeps the choice for this window only, which is still better than failing.
    }
  }
}

/** Told inside one window when it wrote a key, since the storage event reaches only the others. */
const CHANGED = 'memnox-preference';

/** Calls back for a change from this window or any other. */
export function onPreferenceChange(listener: (key: string) => void): () => void {
  const fromHere = (event: Event) => listener(String((event as CustomEvent).detail));
  const fromOthers = (event: StorageEvent) => listener(event.key ?? '');
  window.addEventListener(CHANGED, fromHere);
  window.addEventListener('storage', fromOthers);
  return () => {
    window.removeEventListener(CHANGED, fromHere);
    window.removeEventListener('storage', fromOthers);
  };
}
