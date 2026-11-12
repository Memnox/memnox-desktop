import type { LanStatus } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { LocalNetwork } from '../src/core/application/local-network';
import { RequestIds } from '../src/core/application/request-ids';
import { ScriptedDaemon } from './doubles';

const listening: LanStatus = { on: true, listening: true, addresses: ['192.168.1.20'], port: 47_820, advertised: true, instance: 'mx-7f3a', reachable: [] };

describe('the local network use case', () => {
  it('reads the status, and says when the runtime is away', async () => {
    const daemon = new ScriptedDaemon({ 'lan-status': (request) => [{ id: request.id, ok: true, lan: listening }] });
    const lan = new LocalNetwork(daemon, new RequestIds());
    await lan.refresh();
    expect(lan.status).toEqual(listening);
    const gone = new LocalNetwork(new ScriptedDaemon(), new RequestIds());
    await gone.refresh();
    expect(gone.unreadable).toBe(true);
  });
});
