import type { VoiceChoices } from '../../core/application/voice-preferences';
import { PressingLink } from '../../core/application/presses';
import { confirmKey, daemonLink, demoCloud, demoCredentials, demoOn, demoPairer, runtime } from '../adapters/demo';
import { tellIsland } from '../adapters/tauri-presses';
import { tauriCloud, tauriPersonCredential } from '../adapters/tauri-cloud';
import { tauriPairer } from '../adapters/tauri-relay';
import { LocalPreferenceStore, tauriHost } from './host';
import { PREFERENCE } from '../../core/application/preferences';
import { buildParts, type SettingsParts } from './parts';
import { previewHost, previewKey, previewLink, previewKickoff, previewRelay, previewRuntime, previewSeed, PreviewStore } from './preview-world';
import { VOICE_KEY_PREFIX } from '../../core/application/voice-preferences';


/** Whether this page runs inside the app, rather than in a browser for a preview. */
export const inApp = '__TAURI_INTERNALS__' in window;

/** The parts over the real computer inside the app, or over the script in a browser preview. */
export function worldParts(): SettingsParts {
  // The demo world stands in for the daemon and the cloud, in the app or in a browser, and nothing real is reached.
  if (demoOn) {
    const demoRelay = { pairer: demoPairer, cloud: demoCloud, credentials: demoCredentials };
    if (inApp) return buildParts(new PressingLink(daemonLink(), tellIsland, () => crypto.randomUUID()), tauriHost, runtime(), confirmKey(), new LocalPreferenceStore(), demoRelay);
    return buildParts(daemonLink(), previewHost, runtime(), confirmKey(), new PreviewStore({ ...previewSeed(), [PREFERENCE.name]: 'Alex Rivera', [PREFERENCE.setupDone]: 'true' }), demoRelay);
  }
  if (inApp) {
    // Every press here tells the island the proposals it raised, so they are confirmed there as asked for.
    const parts = buildParts(new PressingLink(daemonLink(), tellIsland, () => crypto.randomUUID()), tauriHost, runtime(), confirmKey(), new LocalPreferenceStore(), { pairer: tauriPairer, cloud: tauriCloud, credentials: tauriPersonCredential });
    // The island and the tray switch the voice too, so a change there shows on the Listening page.
    window.addEventListener('storage', (event) => {
      const key = event.key?.startsWith(VOICE_KEY_PREFIX) === true ? (event.key.slice(VOICE_KEY_PREFIX.length) as keyof VoiceChoices) : undefined;
      if (key !== undefined && key in parts.voice.choices && (event.newValue === 'true' || event.newValue === 'false')) parts.voice.set(key, event.newValue === 'true');
    });
    return parts;
  }
  const parts = buildParts(previewLink, previewHost, previewRuntime, previewKey, new PreviewStore(previewSeed()), previewRelay);
  previewKickoff(parts);
  return parts;
}
