import type { VoiceChoices } from '../../core/application/voice-preferences';
import { TauriConfirmKey } from '../adapters/tauri-confirm-key';
import { TauriDaemonLink } from '../adapters/tauri-daemon-link';
import { TauriRuntime } from '../adapters/tauri-runtime';
import { LocalPreferenceStore, tauriHost } from './host';
import { buildParts, type SettingsParts } from './parts';
import { previewHost, previewKey, previewLink, previewRuntime, previewSeed, PreviewStore } from './preview-world';

/** The prefix `VoicePreferences` keeps each switch under. */
const VOICE_PREFIX = 'memnox.voice.';

/** Whether this page runs inside the app, rather than in a browser for a preview. */
export const inApp = '__TAURI_INTERNALS__' in window;

/** The parts over the real computer inside the app, or over the script in a browser preview. */
export function worldParts(): SettingsParts {
  if (inApp) {
    const parts = buildParts(new TauriDaemonLink(), tauriHost, new TauriRuntime(), new TauriConfirmKey(), new LocalPreferenceStore());
    // The island and the tray switch the voice too, so a change there shows on the Listening page.
    window.addEventListener('storage', (event) => {
      const key = event.key?.startsWith(VOICE_PREFIX) === true ? (event.key.slice(VOICE_PREFIX.length) as keyof VoiceChoices) : undefined;
      if (key !== undefined && key in parts.voice.choices && (event.newValue === 'true' || event.newValue === 'false')) parts.voice.set(key, event.newValue === 'true');
    });
    return parts;
  }
  return buildParts(previewLink, previewHost, previewRuntime, previewKey, new PreviewStore(previewSeed()));
}
