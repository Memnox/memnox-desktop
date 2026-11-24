import { describe, expect, it } from 'vitest';
import { Home } from '../src/core/application/home';
import { RequestIds } from '../src/core/application/request-ids';
import { EMPTY_STANDING, homeMode, homeSetup, progressLine, restOf, stageOf, type HomeStanding } from '../src/core/domain/home-steps';
import { ScriptedDaemon } from './doubles';

const standing = (change: Partial<HomeStanding>): HomeStanding => ({ ...EMPTY_STANDING, ...change });

describe("Home's getting started steps", () => {
  it('reads the stage off what is true, as the cloud console does', () => {
    expect(stageOf(EMPTY_STANDING)).toBe('ungoverned');
    expect(stageOf(standing({ agents: 2, agentsProtected: 1 }))).toBe('observing');
    expect(stageOf(standing({ agents: 2, agentsProtected: 1, mode: 'enforce' }))).toBe('enforcing');
  });

  it('offers the first step a person can do next, never more than three', () => {
    const setup = homeSetup(standing({ agents: 1, agentsProtected: 1, setupFinished: false }), 'Windows Hello');
    expect(setup.next?.id).toBe('chooseCare');
    expect(setup.next?.how).toContain('Windows Hello');
    expect(setup.waiting).toEqual([]);
    expect(progressLine(setup)).toBe('1 of 3 done');
    expect(restOf(setup, 'computer').map((step) => step.id)).toEqual(['protectAgents', 'answerAway']);
    expect(restOf(setup, 'work')).toHaveLength(0);
  });

  it('counts only what was won, and stops once every step is done', () => {
    const all = standing({ agents: 1, agentsProtected: 1, rulesInForce: 3, actionsRecorded: 4, phonesPaired: 1, mode: 'enforce', skillsShared: 2 });
    const setup = homeSetup(all, 'Windows Hello');
    expect(setup.climbed).toBe(true);
    expect(setup.standing.map((count) => count.label)).not.toContain('Servers shared');
    expect(homeSetup(EMPTY_STANDING, 'Windows Hello').standing).toEqual([]);
  });

  it('starts by connecting the agents, in plain words', () => {
    const setup = homeSetup(standing({ setupFinished: false }), 'Windows Hello');
    expect(setup.next?.id).toBe('protectAgents');
    expect(setup.next?.title).toBe('Connect your agents');
    expect(progressLine(setup)).toBe('0 of 3 done');
  });

  it('knows only the two modes the runtime names', () => {
    expect(homeMode('enforce')).toBe('enforce');
    expect(homeMode('watch')).toBeUndefined();
  });
});

describe('turning on stopping', () => {
  it('asks the runtime with no signature, since it only narrows, and says where the mode went', async () => {
    const daemon = new ScriptedDaemon({
      'mode-enforce': (request) => [{ id: request.id, ok: true, modeSet: { was: 'observe', now: 'enforce' } }],
      home: (request) => [{ id: request.id, ok: false }],
      waiting: (request) => [{ id: request.id, ok: true, waiting: [] }],
      'sessions-list': (request) => [{ id: request.id, ok: true, sessions: [] }],
    });
    const home = new Home(daemon, new RequestIds(), async () => undefined);
    const outcome = await home.enforce();
    expect(outcome.kind).toBe('enforcing');
    expect(daemon.sent('mode-enforce')[0]?.signature).toBeUndefined();
    expect(home.enforceNote).toContain('now stops');
  });

  it('says a runtime older than the method should be told at the terminal', async () => {
    const daemon = new ScriptedDaemon({
      'mode-enforce': (request) => [{ id: request.id, ok: true }],
      home: (request) => [{ id: request.id, ok: false }],
      waiting: (request) => [{ id: request.id, ok: true, waiting: [] }],
      'sessions-list': (request) => [{ id: request.id, ok: true, sessions: [] }],
    });
    const home = new Home(daemon, new RequestIds(), async () => undefined);
    await home.enforce();
    expect(home.enforceNote).toContain('memnox protect --enforce');
  });
});
