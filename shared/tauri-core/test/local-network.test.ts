import type { LanStatus } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { LocalNetwork } from '../src/core/application/local-network';
import { RequestIds } from '../src/core/application/request-ids';
import { lanPhonesLine, lanStatusLine, lanSwitchCaption, lanWaitsLine } from '../src/core/domain/local-network-lines';
import { ScriptedDaemon } from './doubles';

const off: LanStatus = { on: false, listening: false, addresses: [], advertised: false, reachable: [] };
const listening: LanStatus = { on: true, listening: true, addresses: ['192.168.1.20'], port: 47_820, advertised: true, instance: 'mx-7f3a', reachable: [{ deviceId: 'dev_1', name: 'Sam’s iPhone' }] };

describe('the wording of the local network', () => {
  it('says off, on with nothing listening, and where it listens', () => {
    expect(lanStatusLine(off)).toBe('Off. Your phones reach this computer through the relay.');
    expect(lanStatusLine({ ...off, on: true })).toBe('On, but this computer has no private network address right now, so nothing is listening.');
    expect(lanStatusLine(listening)).toBe('Listening on 192.168.1.20:47820, announced to phones nearby under a name that says nothing about this computer.');
    expect(lanStatusLine({ ...listening, advertised: false, addresses: ['10.0.0.4', '192.168.1.20'] })).toBe('Listening on 10.0.0.4:47820, 192.168.1.20:47820.');
  });

  it('names the phones connected over it, and asks for the key only to turn it on', () => {
    expect(lanPhonesLine(listening)).toBe('Sam’s iPhone is connected over it now.');
    expect(lanPhonesLine({ on: true, reachable: [{ deviceId: 'a', name: 'One' }, { deviceId: 'b', name: 'Two' }] })).toBe('One and Two are connected over it now.');
    expect(lanPhonesLine({ on: true, reachable: [] })).toBe('No phone is connected over it now.');
    expect(lanSwitchCaption(false, 'Windows Hello')).toBe('Windows Hello to turn on');
    expect(lanSwitchCaption(true, 'Windows Hello')).toBe('Turn off to stop it at once');
    expect(lanWaitsLine('Windows Hello')).toContain('signature with Windows Hello on the island');
  });
});

describe('the local network use case', () => {
  it('reads the status, and turns it off at once', async () => {
    const daemon = new ScriptedDaemon({
      'lan-status': (request) => [{ id: request.id, ok: true, lan: listening }],
      'lan-set': (request) => [{ id: request.id, ok: true, lan: off }],
    });
    const lan = new LocalNetwork(daemon, new RequestIds());
    await lan.refresh();
    expect(lan.status).toEqual(listening);
    expect(await lan.set(false)).toEqual({ kind: 'done' });
    expect(daemon.sent('lan-set')[0]).toMatchObject({ lanOn: false });
    expect(lan.status).toEqual(off);
  });

  it('only proposes turning it on, and passes a refusal on', async () => {
    const daemon = new ScriptedDaemon({ 'lan-set': (request) => [{ id: request.id, ok: true, proposed: 'prp_lan', lan: off }] });
    expect(await new LocalNetwork(daemon, new RequestIds()).set(true)).toEqual({ kind: 'proposed', id: 'prp_lan' });
    const refused = new ScriptedDaemon({ 'lan-set': (request) => [{ id: request.id, ok: false, error: 'Not from a phone.' }] });
    expect(await new LocalNetwork(refused, new RequestIds()).set(true)).toEqual({ kind: 'failed', why: 'Not from a phone.' });
    const gone = new LocalNetwork(new ScriptedDaemon(), new RequestIds());
    await gone.refresh();
    expect(gone.unreadable).toBe(true);
  });
});
