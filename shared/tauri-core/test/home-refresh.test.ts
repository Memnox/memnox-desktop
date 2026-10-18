import { describe, expect, it } from 'vitest';
import { Home } from '../src/core/application/home';
import { RequestIds } from '../src/core/application/request-ids';
import { HandTimer, ScriptedDaemon } from './doubles';

describe('the home read again', () => {
  it('reads once after a burst of changes rather than once per change, as the Mac does', async () => {
    const daemon = new ScriptedDaemon({});
    const timer = new HandTimer();
    const home = new Home(daemon, new RequestIds(), async () => undefined, timer.start);
    home.refreshSoon();
    home.refreshSoon();
    home.refreshSoon();
    expect(daemon.requests.filter((request) => request.method === 'home')).toHaveLength(0);
    timer.fireAll();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(daemon.requests.filter((request) => request.method === 'home')).toHaveLength(1);
    home.refreshSoon();
    timer.fireAll();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(daemon.requests.filter((request) => request.method === 'home')).toHaveLength(2);
  });
});
