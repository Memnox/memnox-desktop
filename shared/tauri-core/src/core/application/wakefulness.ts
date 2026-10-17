import { DAEMON_METHOD } from '@memnox/core/wire';
import { phonePaired, shouldStayAwake } from '../domain/wakefulness';
import type { Power } from './ports/power';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** Keeps the computer awake while a paired phone may need it, asked again on every check. */
export class Wakefulness {
  constructor(
    private readonly link: DaemonLink,
    private readonly power: Power,
    private readonly ids: RequestIds,
  ) {}

  /** One check: the phones the daemon knows and the charger. A daemon that does not answer lets the computer sleep. */
  async check(): Promise<boolean> {
    const request = { id: this.ids.next(), method: DAEMON_METHOD.DEVICES_LIST };
    const response = await requestOnce(this.link, request).catch(() => undefined);
    const paired = response?.ok === true && phonePaired(response.devices ?? []);
    const awake = shouldStayAwake(paired, await this.power.onMains());
    await this.power.keepAwake(awake);
    return awake;
  }
}
