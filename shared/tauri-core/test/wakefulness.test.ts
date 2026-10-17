import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { DeviceWire } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Wakefulness } from '../src/core/application/wakefulness';
import { RequestIds } from '../src/core/application/request-ids';
import type { Power } from '../src/core/application/ports/power';
import { PHONE_KIND } from '../src/core/domain/wakefulness';
import { ScriptedDaemon } from './doubles';

class Charger implements Power {
  held: boolean[] = [];
  constructor(private readonly mains: boolean) {}
  onMains(): Promise<boolean> {
    return Promise.resolve(this.mains);
  }
  keepAwake(on: boolean): Promise<void> {
    this.held.push(on);
    return Promise.resolve();
  }
}

const phone = (extra: Partial<DeviceWire> = {}): DeviceWire => ({
  id: 'dev_1',
  name: 'Ana phone',
  kind: PHONE_KIND,
  fingerprint: 'f',
  capabilities: [],
  pairedAt: '2026-10-01T00:00:00.000Z',
  ...extra,
});

function daemonWith(devices: DeviceWire[]): ScriptedDaemon {
  return new ScriptedDaemon({ 'devices-list': (request) => [{ id: request.id, ok: true, devices }] });
}

describe('keeping the computer awake', () => {
  it('holds sleep off with a phone paired and the charger in', async () => {
    const power = new Charger(true);
    expect(await new Wakefulness(daemonWith([phone()]), power, new RequestIds()).check()).toBe(true);
    expect(power.held).toEqual([true]);
  });

  it('lets a laptop on battery sleep as it always has', async () => {
    expect(await new Wakefulness(daemonWith([phone()]), new Charger(false), new RequestIds()).check()).toBe(false);
  });

  it('lets it sleep once the phone is unpaired, or when the daemon does not answer', async () => {
    expect(await new Wakefulness(daemonWith([phone({ revokedAt: '2026-10-02' })]), new Charger(true), new RequestIds()).check()).toBe(false);
    expect(await new Wakefulness(new ScriptedDaemon(), new Charger(true), new RequestIds()).check()).toBe(false);
  });

  it('names a phone the way the runtime does', () => {
    const vectors = JSON.parse(readFileSync(fileURLToPath(new URL('../../vectors/protocol.json', import.meta.url)), 'utf8')) as {
      values: Record<string, string[]>;
    };
    expect(vectors.values['deviceKinds']).toContain(PHONE_KIND);
  });
});
