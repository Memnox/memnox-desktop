import { useEffect, useReducer } from 'react';
import { Account } from '../../core/application/account';
import { DaemonAccount, DaemonSignIn } from '../../core/application/daemon-sign-in';
import { Home } from '../../core/application/home';
import { PhonePairing } from '../../core/application/pairing';
import type { ConfirmKey } from '../../core/application/ports/confirm-key';
import type { DaemonLink } from '../../core/application/ports/daemon-link';
import type { PreferenceStore } from '../../core/application/ports/preference-store';
import type { Runtime } from '../../core/application/ports/runtime';
import { Preferences } from '../../core/application/preferences';
import { RequestIds } from '../../core/application/request-ids';
import { Setup } from '../../core/application/setup';
import { Signer } from '../../core/application/signer';
import { Tools } from '../../core/application/tools';
import { VoicePreferences } from '../../core/application/voice-preferences';
import { DictationWords, VoiceSettings } from '../../core/application/voice-settings';
import { themeFor, type Look } from '../../core/domain/appearance';
import { platformWords, type PlatformWords } from '../../core/domain/platform';
import { onPreferenceChange, type SettingsHost } from './host';
import { SetupModel } from './setup-model';

/** Everything a Settings page or a first run step draws from, built once per window. */
export interface SettingsParts {
  readonly host: SettingsHost;
  readonly words: PlatformWords;
  readonly setup: Setup;
  readonly signer: Signer;
  readonly voiceSettings: VoiceSettings;
  /** The voice's own switches, the same class and keys the island reads. */
  readonly voice: VoicePreferences;
  readonly dictation: DictationWords;
  readonly preferences: Preferences;
  readonly account: Account;
  readonly pairing: PhonePairing;
  readonly home: Home;
  readonly tools: Tools;
  /** Where every setup step stands, shared by the overview, the setup pages and the first run. */
  readonly steps: SetupModel;
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** The composition root of the Settings window and the first run: the one place adapters meet the core. */
export function buildParts(link: DaemonLink, host: SettingsHost, runtime: Runtime, key: ConfirmKey, store: PreferenceStore): SettingsParts {
  const ids = new RequestIds();
  const setup = new Setup(link, runtime, ids, sleep);
  const signer = new Signer(link, key, ids);
  const voiceSettings = new VoiceSettings(link, ids);
  const person = new DaemonAccount(new DaemonSignIn(link, 'person', ids, sleep), sleep, (url) => host.openPage(url));
  const machine = new DaemonAccount(new DaemonSignIn(link, 'machine', ids, sleep), sleep, (url) => host.openPage(url));
  const account = new Account(
    person,
    machine,
    async () => void (await setup.bringUpToDate()),
    () => host.computerName(),
  );
  const connected = async (): Promise<boolean | undefined> => {
    await machine.refresh();
    if (machine.step.kind === 'signed-in') return true;
    return machine.step.kind === 'signed-out' ? false : undefined;
  };
  const parts: Omit<SettingsParts, 'steps'> = {
    host,
    words: platformWords(host.platform),
    setup,
    signer,
    voiceSettings,
    voice: new VoicePreferences(store),
    dictation: new DictationWords(store),
    preferences: new Preferences(store),
    account,
    pairing: new PhonePairing(link, signer, key, ids, connected, () => host.computerName()),
    home: new Home(link, ids, () => setup.protectAgents(), (ms, fire) => {
      const handle = setTimeout(fire, ms);
      return () => clearTimeout(handle);
    }),
    tools: new Tools(link, ids),
  };
  const whole = parts as SettingsParts;
  (whole as { steps: SetupModel }).steps = new SetupModel(whole);
  return whole;
}

/** Redraws whenever a use case says it changed. */
export function useObserved(...observed: { observe(listener: () => void): () => void }[]): void {
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  useEffect(() => {
    const stops = observed.map((each) => each.observe(redraw));
    return () => {
      for (const stop of stops) stop();
    };
    // The use cases are built once per window, so their identity never changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

/** Redraws whenever any window changes a choice, so a switch flipped elsewhere shows here. */
export function usePreferences(): void {
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  useEffect(() => onPreferenceChange(redraw), []);
}

/**
 * Paints this window in the look: Light and Dark set the theme outright, System leaves it to the media
 * query in styles.css. Called whenever the look changes, here or in another window.
 */
export function paintLook(look: Look): void {
  const root = document.documentElement;
  if (look === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', look);
  root.style.colorScheme = look === 'system' ? '' : themeFor(look, false);
}

/** Keeps this window in the person's look, from their choice and from the computer's for System. */
export function useLook(preferences: Preferences): void {
  usePreferences();
  const look = preferences.look;
  useEffect(() => paintLook(look), [look]);
}
