import { confirmationMessage, DAEMON_METHOD } from '@memnox/core/wire';
import { ANOTHER_KEY_LINE, keyStatusOf, type KeyStatus } from '../domain/key-status';
import type { ConfirmKey } from './ports/confirm-key';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** Said when this computer has no key the operating system guards, so an allow has to come from elsewhere. */
export const NO_KEY_LINE =
  'This computer has no key to sign a yes with, so allow it from the terminal or your phone.';

/** How asking for a signature ended: signed, refused before the prompt with why, or cancelled at it. */
export type Signing =
  | { kind: 'signed'; signature: string }
  | { kind: 'refused'; why: string }
  | { kind: 'cancelled' };

/**
 * The one place a yes is signed, for a button on the island and a spoken answer alike: the key is
 * registered first, since a signature from a key the daemon does not trust is refused only after the
 * prompt, and then exactly `confirmationMessage(subject, answer)` is signed.
 */
export class Signer {
  constructor(
    private readonly link: DaemonLink,
    private readonly key: ConfirmKey,
    private readonly ids: RequestIds,
    private readonly onStatus: (status: KeyStatus) => void = () => undefined,
  ) {}

  /** Registers this computer's key, which the daemon trusts on first use. */
  async registerKey(): Promise<KeyStatus> {
    const point = await this.key.publicPoint().catch(() => undefined);
    const status = point === undefined ? { kind: 'no-key' as const } : await this.register(point);
    this.onStatus(status);
    return status;
  }

  private async register(point: string): Promise<KeyStatus> {
    const request = { id: this.ids.next(), method: DAEMON_METHOD.REGISTER_KEY, point };
    const response = await requestOnce(this.link, request).catch(() => undefined);
    return response === undefined ? { kind: 'unreachable' } : keyStatusOf(response);
  }

  async sign(subject: string, answer: string, reason: string): Promise<Signing> {
    const status = await this.registerKey();
    if (status.kind === 'another-key') return { kind: 'refused', why: ANOTHER_KEY_LINE };
    if (status.kind === 'no-key') return { kind: 'refused', why: NO_KEY_LINE };
    const signature = await this.key.sign(confirmationMessage(subject, answer), reason).catch(() => undefined);
    return signature === undefined ? { kind: 'cancelled' } : { kind: 'signed', signature };
  }
}
