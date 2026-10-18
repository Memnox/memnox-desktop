import { ASK_ENDS, DAEMON_METHOD, REMOTE_METHOD, SPEECH_METHOD, type DaemonResponse } from '@memnox/core/wire';

/**
 * Whether a line is the last the daemon sends for a request. Over the socket a closed connection said so; in
 * the relay every request shares one session, so the method decides. Ported from the Mac's `isLastLine`.
 */
export function isLastLine(response: DaemonResponse, method: string): boolean {
  switch (method) {
    // Events stream until the caller stops listening.
    case DAEMON_METHOD.SUBSCRIBE:
    case REMOTE_METHOD.PAIR_PENDING:
      return false;
    // A turn ends on its last chunk; an answer with no chunk is a refusal or an error, which ends it too.
    case DAEMON_METHOD.ASK:
    case DAEMON_METHOD.BRIEF:
      return response.chunk === undefined || ASK_ENDS.includes(response.chunk.kind);
    // A sentence's audio comes in pieces until the one marked last; an answer with no audio is a refusal.
    case SPEECH_METHOD.SPEAK:
      return response.audio === undefined || response.audio.last === true;
    default:
      return true;
  }
}
