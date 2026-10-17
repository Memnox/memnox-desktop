import type { DeviceWire } from '@memnox/core/wire';

/** The runtime's `DEVICE_KIND.PHONE`, which `test/protocol-vectors.test.ts` checks against the vectors. */
export const PHONE_KIND = 'phone';

/** Whether a phone that still holds its pairing could need this computer while the person is away. */
export function phonePaired(devices: readonly DeviceWire[]): boolean {
  return devices.some((device) => device.kind === PHONE_KIND && device.revokedAt === undefined);
}

/**
 * Awake only with a phone paired and on the charger: a phone is the only reason to keep a computer
 * up while nobody sits at it, and a laptop on battery sleeps as it always has.
 */
export function shouldStayAwake(paired: boolean, onMains: boolean): boolean {
  return paired && onMains;
}
