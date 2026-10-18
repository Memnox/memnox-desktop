import { DAEMON_METHOD, HOME_METHOD, REMOTE_METHOD, SPEECH_METHOD, type DaemonRequest } from '@memnox/core/wire';

/**
 * What this computer may ask of a server it reaches over the relay, mirrored from the runtime's remote
 * allowlist in packages/core/src/gate/capabilities.ts. Anything else stays on this computer's own daemon,
 * since a server refuses it anyway and asking only spends a round trip to hear no. Ported from the Mac's `RemoteReach`.
 */
export const REMOTE_REACH: ReadonlySet<string> = new Set<string>([
  DAEMON_METHOD.PING,
  DAEMON_METHOD.SESSIONS_LIST,
  DAEMON_METHOD.SESSION_VIEW,
  DAEMON_METHOD.WAITING,
  DAEMON_METHOD.SUBSCRIBE,
  DAEMON_METHOD.TRACE,
  DAEMON_METHOD.VOICE_AGENTS,
  REMOTE_METHOD.VOICE_CHOICE,
  DAEMON_METHOD.FILES_LIST,
  HOME_METHOD.HOME,
  DAEMON_METHOD.CONNECTIONS_LIST,
  DAEMON_METHOD.ASK,
  DAEMON_METHOD.CANCEL,
  DAEMON_METHOD.WARM,
  DAEMON_METHOD.BRIEF,
  SPEECH_METHOD.SPEAK,
  HOME_METHOD.HAND_OVER,
  REMOTE_METHOD.DRIVE,
  DAEMON_METHOD.CONFIRM,
]);

/** Whether a request may go to another machine: on the list, and a voice choice only when it asks rather than sets. */
export function remoteAllows(request: DaemonRequest): boolean {
  if (!REMOTE_REACH.has(request.method)) return false;
  // Setting the voice is the machine's own; from afar it may only be asked which one is set.
  if (request.method === REMOTE_METHOD.VOICE_CHOICE) return request.voice === undefined;
  return true;
}
