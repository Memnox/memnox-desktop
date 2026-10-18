/**
 * What the person reads about signing in to their workspace and answering its calls, in words they can act on.
 * Ported from the Mac's `WorkspaceLines`, with "this Mac" said as "this computer".
 */
export const WorkspaceLines = {
  noKey: 'This computer has no key to sign a yes with, so it cannot answer what your workspace routes to you.',
  unreachable: 'Memnox Cloud did not answer. Check the connection and try again.',
  expired: 'The code ran out before it was approved. Start again for a new one.',
  cancelled: 'Signing in was stopped.',
  noWorkspace: 'Your account reaches no workspace yet, so there is nothing to answer.',
  notKept: 'Signed in, but the credential could not be kept in the credential store, so this computer was removed again.',
  signedOut: 'Your workspace signed this computer out. Sign in again to answer its calls.',
  notReached: "Memnox Cloud would not take that answer: the call has not reached you, or this computer's signature was not accepted.",
  gone: 'That call is no longer waiting on you.',
  answeredByVoice: 'Very well. Your team has your answer.',

  /** The console's refusal of the code, said plainly where it is one the contract names. */
  refused(word: string): string {
    switch (word) {
      case 'access_denied':
        return 'The sign in was declined in the console.';
      case 'expired_token':
        return WorkspaceLines.expired;
      case 'invalid_grant':
        return 'That code was already used. Start again for a new one.';
      default:
        return `Memnox Cloud refused the sign in: ${word}.`;
    }
  },

  /** The code to type, said once the console page is open. */
  enterCode(code: string): string {
    return `Approve this computer in the console with the code ${code}.`;
  },
};
