import type { DaemonResponse } from '@memnox/core/wire';

/** Where this computer's key stands with the daemon. */
export type KeyStatus =
  | { kind: 'registered' }
  /** Somebody else's key is trusted, so nothing can be confirmed from here. */
  | { kind: 'another-key' }
  /** This computer has no key the operating system guards, so every allow stays in the terminal. */
  | { kind: 'no-key' }
  | { kind: 'unreachable' }
  /** The daemon answers but does not know keys: an older Memnox than this app. */
  | { kind: 'too-old' }
  /** The daemon said no in its own words, shown as given. */
  | { kind: 'refused'; why: string };

/** The daemon's words for a key, as `voice-lookups.ts` answers REGISTER_KEY. */
const REGISTERED = 'registered';
const ANOTHER_KEY = 'another key';
/** How a daemon that predates a method refuses it. */
const UNKNOWN_METHOD = 'no method';

/** Read from REGISTER_KEY's reply. Only the word itself counts, since an older daemon answered anything with a bare ok. */
export function keyStatusOf(response: DaemonResponse): KeyStatus {
  if (response.outcome === ANOTHER_KEY) return { kind: 'another-key' };
  if (!response.ok && response.error !== undefined && !response.error.startsWith(UNKNOWN_METHOD))
    return { kind: 'refused', why: response.error };
  return response.ok && response.outcome === REGISTERED ? { kind: 'registered' } : { kind: 'too-old' };
}

/** Said when the daemon trusts another key, so nothing this computer signs can be confirmed until it is cleared. */
export const ANOTHER_KEY_LINE =
  'Memnox trusts another key for confirmations, so nothing can be confirmed from here yet. Run memnox voice forget-key in a terminal, then open Memnox again.';
