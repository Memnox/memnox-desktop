import { grantMessage, pairMessage, type DaemonRequest, type DaemonResponse, type VoiceAgentStatus } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Account } from '../src/core/application/account';
import { DaemonAccount, DaemonSignIn } from '../src/core/application/daemon-sign-in';
import { Home, overviewNumbers } from '../src/core/application/home';
import { PhonePairing } from '../src/core/application/pairing';
import type { DaemonLink } from '../src/core/application/ports/daemon-link';
import type { PreferenceStore } from '../src/core/application/ports/preference-store';
import { Preferences } from '../src/core/application/preferences';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { VoicePreferences, VOICE_PREFERENCE } from '../src/core/application/voice-settings';
import { accountState, accountTitle, accountWhole, groupedDigits } from '../src/core/domain/account-whole';
import { AgentCheckText } from '../src/core/domain/agent-check-text';
import { themeFor } from '../src/core/domain/appearance';
import { HomeLines } from '../src/core/domain/home-lines';
import { GuideLines, progressOf, setTitle } from '../src/core/domain/onboarding';
import { deviceCaption, PairingLines } from '../src/core/domain/pairing-lines';
import { permissionSteps } from '../src/core/domain/permission-steps';
import { keyStep, platformOf } from '../src/core/domain/platform';
import { matchingPages, PageHistory, pageNamed, SETTINGS_GROUPS, SETTINGS_PAGES } from '../src/core/domain/settings-pages';
import { agentsDetail, agentsStep, greeting, openStep, overviewSteps, readyCount, serviceStep, voiceStep } from '../src/core/domain/setup-steps';
import { DONE, needs, WAITING } from '../src/core/domain/step-state';
import { PersonKey, registered, ScriptedDaemon } from './doubles';

const noSleep = () => Promise.resolve();

function agent(extra: Partial<VoiceAgentStatus>): VoiceAgentStatus {
  return { kind: 'claude-code', label: 'Claude Code', installed: true, sealed: true, chosen: false, install: 'npm i -g claude', ...extra };
}

class MemoryStore implements PreferenceStore {
  readonly kept = new Map<string, string>();
  load(key: string): string | null {
    return this.kept.get(key) ?? null;
  }
  save(key: string, value: string): void {
    this.kept.set(key, value);
  }
}

describe('the Settings pages', () => {
  it('lists eleven pages in the Mac sidebar order, the overview alone first', () => {
    expect(SETTINGS_PAGES).toEqual(['overview', 'account', 'permissions', 'connection', 'phones', 'appearance', 'tools', 'voice', 'listening', 'dictation', 'help']);
    expect(SETTINGS_GROUPS[0]?.title).toBeUndefined();
    expect(SETTINGS_GROUPS.map((group) => group.title).slice(1)).toEqual(['You', 'This computer', 'Agents and tools', 'Voice', 'Support']);
  });

  it('filters by title or the line under it, and lists all for an empty search', () => {
    expect(matchingPages('')).toHaveLength(11);
    expect(matchingPages('phone')).toEqual(['phones']);
    expect(matchingPages('LISTENS')).toEqual(['listening']);
    expect(matchingPages('nothing like this')).toEqual([]);
  });

  it('reads a page from a link and ignores anything else', () => {
    expect(pageNamed('phones')).toBe('phones');
    expect(pageNamed('admin')).toBeUndefined();
    expect(pageNamed(null)).toBeUndefined();
  });

  it('goes back and forward, and a new visit drops what was ahead', () => {
    const history = new PageHistory();
    history.visit('account');
    history.visit('voice');
    history.back();
    expect(history.current).toBe('account');
    expect(history.canGoForward).toBe(true);
    history.visit('help');
    expect(history.canGoForward).toBe(false);
    history.back();
    history.back();
    expect(history.current).toBe('overview');
    expect(history.canGoBack).toBe(false);
    history.visit('overview');
    expect(history.canGoForward).toBe(true);
  });
});

describe('the home lines', () => {
  it('says today as counts, or a quiet line', () => {
    expect(HomeLines.today({ actions: 41, asked: 6, allowed: 5, refused: 1 })).toBe('41 actions, 6 asked you, 5 allowed, 1 refused');
    expect(HomeLines.today({ actions: 1, asked: 0, allowed: 0, refused: 0 })).toBe('1 action, 0 asked you, 0 allowed, 0 refused');
    expect(HomeLines.today({ actions: 0, asked: 0, allowed: 0, refused: 0 })).toBe('Nothing has run today.');
  });

  it('counts what waits and names the ready agent only when there is one', () => {
    expect(HomeLines.waiting(0)).toBe('Nothing waits on you.');
    expect(HomeLines.waiting(1)).toBe('1 call waits on you.');
    expect(HomeLines.waiting(3)).toBe('3 calls wait on you.');
    expect(HomeLines.ready({ action: 'git push', approvals: 2, targets: [], because: '' })).toBe('You have said yes to git push twice. Let it run on its own?');
    expect(HomeLines.ready({ action: 'git push', approvals: 5, agentName: 'Codex', targets: [], because: '' })).toBe(
      'You have said yes to git push 5 times, for Codex. Let it run on its own?',
    );
  });

  it('says what nothing covers, or that everything is covered', () => {
    expect(HomeLines.notCovered({ unprotected: 0, dormant: 0 })).toEqual(['Every agent here is under Memnox.']);
    expect(HomeLines.notCovered({ unprotected: 2, dormant: 1 })).toEqual([
      '2 agents here run outside Memnox.',
      '1 agent has been quiet for a month and still holds its reach.',
    ]);
  });

  it('says a working session by whatever it has', () => {
    const base = { sessionId: 's', agent: 'codex', agentName: 'Codex' };
    expect(HomeLines.working({ ...base, task: 'Fix tests', repository: 'web' })).toBe('Fix tests in web');
    expect(HomeLines.working({ ...base, repository: 'web' })).toBe('Working in web');
    expect(HomeLines.working(base)).toBe('Working');
  });
});

describe('the agent checks', () => {
  it('words each agent shorter than the daemon and quotes its own reply apart', () => {
    expect(AgentCheckText.status(agent({}), true)).toBe('Asking it one question');
    expect(AgentCheckText.status(agent({ works: true, chosen: true }), false)).toBe('Answers when you talk, kept to reading');
    expect(AgentCheckText.status(agent({ works: false, because: 'needs a login' }), false)).toBe('Needs a login');
    expect(AgentCheckText.status(agent({ works: false, reply: ' Upgrade your plan ' }), false)).toBe('Its own account answered in place of Memnox');
    expect(AgentCheckText.reply(agent({ works: false, reply: ' Upgrade your plan ' }))).toBe('Upgrade your plan');
    expect(AgentCheckText.names(['Codex', 'Cursor', 'Hermes'])).toBe('Codex, Cursor and Hermes');
  });

  it('decides the voice step as the Mac does', () => {
    expect(agentsStep([agent({ installed: false })]).kind).toBe('needs');
    expect(agentsStep([agent({})])).toEqual(WAITING);
    expect(agentsStep([agent({ works: true })])).toEqual(needs('Choose the agent that answers for you'));
    expect(agentsStep([agent({ works: true, chosen: true })])).toEqual(DONE);
    expect(agentsStep([agent({ works: false })])).toEqual(needs('None of your agents answered. Fix one below, then check again'));
    expect(agentsDetail([agent({ chosen: true, sealed: false })], false)).toBe(
      'Claude Code can run shell commands without asking, used because no agent kept to reading answered.',
    );
  });
});

describe('the overview checklist', () => {
  const facts = {
    name: DONE,
    hear: DONE,
    type: needs('Wayland lets Memnox type only through uinput'),
    see: DONE,
    service: DONE,
    serviceDetail: 'What your agents already talk to.',
    key: WAITING,
    agents: DONE,
    agentsDetail: '',
    voice: voiceStep({ kind: 'installing', percent: 40 }),
    voiceDetail: '',
  };

  it('lists eight steps, counts the done ones, and offers the first open one with its reason', () => {
    const steps = overviewSteps(facts);
    expect(steps).toHaveLength(8);
    expect(readyCount(steps)).toBe(5);
    expect(openStep(steps)).toMatchObject({ title: 'Let it type for you', page: 'permissions', hint: 'Wayland lets Memnox type only through uinput' });
  });

  it('greets by first name, or says Memnox', () => {
    expect(greeting('  Sam Smith ')).toBe('Hi Sam');
    expect(greeting('')).toBe('Memnox');
  });

  it('reads the service row from setup', () => {
    expect(serviceStep(true, undefined, undefined).state).toEqual(DONE);
    expect(serviceStep(undefined, 'Starting the Memnox service', undefined)).toEqual({ state: WAITING, detail: 'Starting the Memnox service…' });
    expect(serviceStep(false, undefined, 'It would not start').state).toEqual(needs('It would not start'));
  });
});

describe('permissions on Windows and Linux', () => {
  it('asks Windows only for the microphone switch', () => {
    const steps = permissionSteps({ platform: 'windows', session: 'desktop', microphone: 'denied', typing: true });
    expect(steps.map((step) => step.state.kind)).toEqual(['needs', 'done', 'done']);
    expect(steps[0]?.pane).toBe('microphone');
    expect(steps[0]?.guide.length).toBeGreaterThan(0);
  });

  it('needs uinput on Wayland and nothing on X11', () => {
    const wayland = permissionSteps({ platform: 'linux', session: 'wayland', microphone: 'allowed', typing: false });
    expect(wayland.map((step) => step.state.kind)).toEqual(['done', 'needs', 'done']);
    expect(wayland[1]?.guide.join(' ')).toContain('uinput');
    const x11 = permissionSteps({ platform: 'linux', session: 'x11', microphone: 'none', typing: true });
    expect(x11.map((step) => step.state.kind)).toEqual(['needs', 'done', 'done']);
  });

  it('names the key by its system', () => {
    expect(platformOf('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Edg/120')).toBe('windows');
    expect(platformOf('Mozilla/5.0 (X11; Linux x86_64) WebKitGTK')).toBe('linux');
    expect(keyStep({ kind: 'registered' }, 'windows')).toEqual(DONE);
    expect(keyStep({ kind: 'no-key' }, 'windows')).toMatchObject({ why: expect.stringContaining('Windows Hello') });
    expect(keyStep({ kind: 'another-key' }, 'linux')).toMatchObject({ why: expect.stringContaining('forget-key') });
  });
});

describe('the one sign in', () => {
  it('is signed in only when the person and this computer both are', () => {
    expect(accountWhole({ kind: 'signed-out' }, { kind: 'signed-out' }).kind).toBe('signed-out');
    expect(accountWhole({ kind: 'signed-in', name: 'Sam' }, { kind: 'signed-out' })).toMatchObject({ kind: 'incomplete', name: 'Sam' });
    expect(accountWhole({ kind: 'signed-in', name: 'Sam' }, { kind: 'too-old' }).kind).toBe('too-old');
    const whole = accountWhole({ kind: 'signed-in', name: 'Sam' }, { kind: 'signed-in', name: 'Acme' });
    expect(accountTitle(whole)).toBe('Signed in as Sam, Acme');
    expect(accountState(whole)).toEqual(DONE);
    expect(accountTitle(accountWhole({ kind: 'showing-code', code: 'ABCD' }, { kind: 'unknown' }))).toBe('Approve this computer');
    expect(groupedDigits('482913')).toBe('482 913');
  });

  it('shows the code, opens the console, and connects this computer once approved', async () => {
    let approved = false;
    let machineIn = false;
    const daemon = new ScriptedDaemon({
      'person-sign-in': (request) => [{ id: request.id, ok: true, person: { signedIn: false, code: { userCode: 'WXYZ-1234', page: 'https://console.memnox.com/device', expiresAt: Date.now() + 60_000 } } }],
      person: (request) => {
        const answer = approved
          ? { signedIn: true, name: 'Sam' }
          : { signedIn: false, code: { userCode: 'WXYZ-1234', expiresAt: Date.now() + 60_000 } };
        approved = true;
        return [{ id: request.id, ok: true, person: answer }];
      },
      machine: (request) => {
        const answer = machineIn ? { signedIn: true, name: 'Acme' } : { signedIn: false };
        machineIn = true;
        return [{ id: request.id, ok: true, machine: answer }];
      },
    });
    const ids = new RequestIds();
    const opened: string[] = [];
    const person = new DaemonAccount(new DaemonSignIn(daemon, 'person', ids, noSleep), noSleep, (url) => opened.push(url));
    const machine = new DaemonAccount(new DaemonSignIn(daemon, 'machine', ids, noSleep), noSleep, () => undefined);
    const codes: string[] = [];
    person.observe(() => {
      if (person.step.kind === 'showing-code') codes.push(person.step.code);
    });
    const account = new Account(person, machine, async () => undefined, () => 'Desk');
    await account.start();
    expect(codes).toEqual(['WXYZ-1234']);
    expect(opened).toEqual(['https://console.memnox.com/device']);
    expect(daemon.sent('person-sign-in')[0]?.name).toBe('Desk');
    expect(account.whole).toEqual({ kind: 'signed-in', name: 'Sam', workspace: 'Acme' });
  });

  it('calls a daemon that does not know the question too old, and one that is down unreachable', async () => {
    const old = new ScriptedDaemon({ person: (request) => [{ id: request.id, ok: false, error: 'no method person' }] });
    const account = new DaemonAccount(new DaemonSignIn(old, 'person', new RequestIds(), noSleep), noSleep, () => undefined);
    await account.refresh();
    expect(account.step.kind).toBe('too-old');
    const down = new DaemonAccount(new DaemonSignIn(new ScriptedDaemon(), 'person', new RequestIds(), noSleep), noSleep, () => undefined);
    await down.refresh();
    expect(down.step.kind).toBe('failed');
  });

  it('gives up on a code that ran out', async () => {
    let now = 0;
    const daemon = new ScriptedDaemon({
      person: (request) => [{ id: request.id, ok: true, person: { signedIn: false, code: { userCode: 'A', expiresAt: 10_000 } } }],
    });
    const signIn = new DaemonSignIn(daemon, 'person', new RequestIds(), async (ms) => void (now += ms), () => now);
    expect(await signIn.watch({ userCode: 'A', expiresAt: 10_000 })).toEqual({ kind: 'expired' });
  });
});

describe('pairing a phone', () => {
  const phone = { name: 'iPhone', fingerprint: 'fp', code: '482913' };

  /** The daemon, with pair-pending held open after its lines, as a pairing still waiting stays open. */
  function heldOpen(daemon: ScriptedDaemon): DaemonLink {
    return {
      async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
        yield* daemon.stream(request);
        if (request.method === 'pair-pending') await new Promise<never>(() => undefined);
      },
    };
  }

  function pairingOver(daemon: ScriptedDaemon, key = new PersonKey(), connected: boolean | undefined = true) {
    const ids = new RequestIds();
    const link = heldOpen(daemon);
    return { pairing: new PhonePairing(link, new Signer(link, key, ids), key, ids, async () => connected, () => 'Desk'), key };
  }

  it('shows the QR, then the digits, and pairs once the key signs the pairing', async () => {
    let release: () => void = () => undefined;
    const answered = new Promise<void>((resolve) => (release = resolve));
    const daemon = new ScriptedDaemon({
      'pair-begin': (request) => [{ id: request.id, ok: true, outcome: 'pairing', pairing: { id: 'pr_1', qr: 'memnox://pair?d=abc', state: 'waiting' } }],
      'pair-pending': (request) => [{ id: request.id, ok: true, pairing: { id: 'pr_1', state: 'answered', phone } }],
      'register-key': registered,
      'pair-accept': (request) => {
        release();
        return [{ id: request.id, ok: true, outcome: 'paired', device: { id: 'dev_1', name: 'iPhone', kind: 'phone', fingerprint: 'fp', capabilities: [], pairedAt: '' } }];
      },
      'devices-list': (request) => [{ id: request.id, ok: true, devices: [{ id: 'dev_1', name: 'iPhone', kind: 'phone', fingerprint: 'fp', capabilities: ['see', 'ask'], pairedAt: '' }] }],
    });
    const { pairing, key } = pairingOver(daemon);
    await pairing.pair();
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(pairing.step).toEqual({ kind: 'checking', phone });
    expect(daemon.sent('pair-begin')[0]?.name).toBe('Desk');
    await pairing.approve();
    await answered;
    expect(key.signed[0]?.message).toBe(pairMessage('pr_1', 'fp'));
    expect(pairing.step).toEqual({ kind: 'paired', name: 'iPhone' });
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(pairing.devices.map(deviceCaption)).toEqual(['Can see, ask']);
    expect(PairingLines.paired("Sam's iPhone")).toBe("Sam's iPhone is paired.");
  });

  it('sends a computer with no workspace to the Account page before asking the daemon', async () => {
    const daemon = new ScriptedDaemon();
    const { pairing } = pairingOver(daemon, new PersonKey(), false);
    await pairing.pair();
    expect(pairing.step).toEqual({ kind: 'failed', why: PairingLines.connectFirst });
    expect(daemon.requests).toHaveLength(0);
  });

  it('keeps the digits up when the prompt is cancelled', async () => {
    const daemon = new ScriptedDaemon({
      'pair-begin': (request) => [{ id: request.id, ok: true, outcome: 'pairing', pairing: { id: 'pr_1', qr: 'q' } }],
      'pair-pending': (request) => [{ id: request.id, ok: true, pairing: { id: 'pr_1', state: 'answered', phone } }],
      'register-key': registered,
    });
    const { pairing } = pairingOver(daemon, new PersonKey('BPOINT', false));
    await pairing.pair();
    await new Promise((resolve) => setTimeout(resolve, 0));
    await pairing.approve();
    expect(pairing.step).toEqual({ kind: 'checking', phone });
    expect(daemon.sent('pair-accept')).toHaveLength(0);
  });

  it('signs letting a phone drive, and takes it back unsigned', async () => {
    const device = { id: 'dev_1', name: 'iPhone', kind: 'phone', fingerprint: 'fp', capabilities: [], pairedAt: '' };
    const daemon = new ScriptedDaemon({
      'register-key': registered,
      'device-grant': (request) => [{ id: request.id, ok: true, outcome: 'granted' }],
      'device-ungrant': (request) => [{ id: request.id, ok: true, outcome: 'ungranted' }],
      'devices-list': (request) => [{ id: request.id, ok: true, devices: [] }],
    });
    const { pairing, key } = pairingOver(daemon);
    expect(await pairing.letDrive(device, true)).toEqual({ kind: 'done' });
    expect(key.signed[0]?.message).toBe(grantMessage('dev_1', 'mac'));
    expect(daemon.sent('device-grant')[0]?.signature).toBe(`sig(${grantMessage('dev_1', 'mac')})`);
    expect(await pairing.letDrive(device, false)).toEqual({ kind: 'done' });
    expect(daemon.sent('device-ungrant')[0]?.signature).toBeUndefined();
  });
});

describe('the home', () => {
  it('reads the five blocks, and falls back to counts when the daemon has none', async () => {
    const daemon = new ScriptedDaemon({
      home: (request: DaemonRequest): DaemonResponse[] => [{ id: request.id, ok: false, error: 'no method home' }],
      waiting: (request) => [{ id: request.id, ok: true, waiting: [] }],
      'sessions-list': (request) => [
        {
          id: request.id,
          ok: true,
          sessions: [
            { sessionId: 'a', agent: 'codex', agentName: 'Codex', state: 'working', thinking: false, repository: 'web' },
            { sessionId: 'b', agent: 'codex', agentName: 'Codex', state: 'idle', thinking: false, repository: 'api' },
          ],
        },
      ],
    });
    const home = new Home(daemon, new RequestIds(), async () => undefined);
    await home.refresh();
    expect(home.unavailable).toBe(true);
    expect(home.numbers).toEqual({ needYou: 0, working: 1, agents: 1, repositories: 2 });
    expect(overviewNumbers(3, []).needYou).toBe(3);
  });

  it('hands the ready action over as a proposal', async () => {
    const view = { machine: 'm', mode: 'enforce', waiting: 0, working: [], today: { actions: 0, asked: 0, allowed: 0, refused: 0 }, notCovered: { unprotected: 0, dormant: 0 } };
    const daemon = new ScriptedDaemon({
      home: (request) => [{ id: request.id, ok: true, home: view }],
      'hand-over': (request) => [{ id: request.id, ok: true, proposed: 'prp_1' }],
    });
    const home = new Home(daemon, new RequestIds(), async () => undefined);
    await home.handOver({ action: 'git push', approvals: 3, targets: [], because: '' }, 'Windows Hello');
    expect(daemon.sent('hand-over')[0]?.action).toBe('git push');
    expect(home.handOverNote).toBe('Pick where it holds on the island, then confirm with Windows Hello.');
    expect(home.home).toEqual(view);
  });
});

describe('what the person chose', () => {
  it('keeps the switches with the Mac defaults and the dictionary and history as lists', () => {
    const store = new MemoryStore();
    const voice = new VoicePreferences(store);
    expect(voice.isOn('wakeWord')).toBe(false);
    expect(voice.isOn('sounds')).toBe(true);
    voice.set('sounds', false);
    expect(store.load(VOICE_PREFERENCE.sounds)).toBe('false');
    expect(voice.isOn('sounds')).toBe(false);
    voice.addWord('orb', 'ORB');
    voice.addWord('orb', 'Orb');
    voice.addWord('', 'Memnox');
    expect(voice.words()).toEqual([{ said: 'orb', written: 'Orb' }, { written: 'Memnox' }]);
    voice.removeWord({ written: 'Memnox' });
    expect(voice.words()).toHaveLength(1);
    voice.remember({ written: 'first', at: 1 });
    voice.remember({ written: 'second', at: 2, app: 'Slack' });
    expect(voice.history().map((entry) => entry.written)).toEqual(['second', 'first']);
    voice.clearHistory();
    expect(voice.history()).toEqual([]);
    store.save('memnox.dictation.words', 'not json');
    expect(voice.words()).toEqual([]);
  });

  it('keeps the name trimmed, the look, and the first run', () => {
    const preferences = new Preferences(new MemoryStore());
    expect(preferences.look).toBe('system');
    preferences.name = '  Sam ';
    preferences.look = 'dark';
    expect(preferences.name).toBe('Sam');
    expect(preferences.look).toBe('dark');
    preferences.name = '   ';
    expect(preferences.name).toBe('');
    expect(preferences.setupDone).toBe(false);
    preferences.finishSetup();
    expect(preferences.setupDone).toBe(true);
    expect(themeFor('system', true)).toBe('dark');
    expect(themeFor('light', true)).toBe('light');
  });
});

describe('the first run', () => {
  it('fills a third a step and says the name when it has one', () => {
    expect(progressOf(0)).toBeCloseTo(1 / 3);
    expect(progressOf(2)).toBe(1);
    expect(setTitle('Sam')).toBe('You’re set, Sam.');
    expect(setTitle(undefined)).toBe('You’re set.');
    expect(GuideLines.ready(undefined, 'Ctrl Alt Space')).toContain('Ctrl Alt Space');
  });
});
