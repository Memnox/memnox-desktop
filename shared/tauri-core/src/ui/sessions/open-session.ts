import { invoke } from '@tauri-apps/api/core';
import { DELIVERY, wentIn, type DisplayHost } from '@memnox/core/wire';
import { SessionFocus, type Shown } from '../../core';
import { TauriTerminals } from './tauri-terminals';

/** Told to the island by the switcher once it has turned to the session, which the island then opens. */
export const SESSION_TURNED_EVENT = 'session-turned';

/** The terminals and editors, reached only through each one's own documented controls. */
export const terminals = new TauriTerminals();
const focus = new SessionFocus(terminals);

/** Brings the session's own app forward without opening anything of Memnox's when that fails. */
export function bringForward(host: DisplayHost | undefined): Promise<Shown> {
  return focus.focus(host);
}

/**
 * "Open in {app}": the session's own tab or editor brought forward through its tool's own controls, and
 * its live window, as before, when that could not be done, with why, so the voice never claims it was.
 */
export async function openSession(sessionId: string, host: DisplayHost | undefined): Promise<Shown> {
  const shown = await focus.focus(host);
  if (wentIn(shown.answer)) return shown;
  await invoke('open_live_session', { sessionId }).catch(() => undefined);
  return { answer: DELIVERY.FAILED, reason: `${shown.reason ?? 'its app would not come forward'}, so its live window is open instead` };
}
