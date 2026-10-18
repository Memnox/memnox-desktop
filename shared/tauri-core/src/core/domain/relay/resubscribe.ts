/** The words Rust ends a relay stream with when the session closed for its hourly fresh handshake. */
export const SESSION_RENEWED = 'renewed';

/** Why a subscription to a server ended, which decides how soon it is opened again. Ported from the Mac's `Resubscribe`. */
export type SubscriptionEnd = 'renewed' | 'lost';

export function subscriptionEnd(error: unknown): SubscriptionEnd {
  return error instanceof Error && error.message === SESSION_RENEWED ? 'renewed' : 'lost';
}

export const RESUBSCRIBE_MS: Record<SubscriptionEnd, number> = {
  /** After the hourly renewal, since nothing is wrong and the new session is one handshake away. */
  renewed: 0,
  /** After a loss, so a computer off the network does not spin on a relay it cannot reach. */
  lost: 5_000,
};
