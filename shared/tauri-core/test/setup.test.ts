import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import type { Runtime, RuntimeStep } from '../src/core/application/ports/runtime';
import { RequestIds } from '../src/core/application/request-ids';
import { Setup } from '../src/core/application/setup';
import { VoiceSettings } from '../src/core/application/voice-settings';
import { runtimeSourceOf, whyNotReadyFrom } from '../src/core/domain/runtime-source';
import { isAtLeast } from '../src/core/domain/runtime-state';
import { ScriptedDaemon } from './doubles';

/** A runtime that writes down what it was asked to do, and brings the daemon up when told to. */
class Machine implements Runtime {
  source?: Runtime['source'];
  readonly steps: (RuntimeStep | 'install')[] = [];
  constructor(
    private installed: boolean,
    private readonly wasWired: boolean,
    private readonly onStep: (step: RuntimeStep) => void = () => undefined,
    private readonly installs = true,
  ) {}
  found = async () => this.installed;
  wired = async () => this.wasWired;
  install = async () => {
    this.steps.push('install');
    this.installed = this.installs;
    return this.installs;
  };
  run = async (step: RuntimeStep) => {
    this.steps.push(step);
    this.onStep(step);
    return true;
  };
}

/** A daemon that answers ping with whatever version it is at now, or not at all while it is down. */
function daemonAt(version: { now: string | undefined }) {
  return new ScriptedDaemon({
    ping: (request: DaemonRequest): DaemonResponse[] => {
      if (version.now === undefined) throw new Error('down');
      return [{ id: request.id, ok: true, version: version.now }];
    },
  });
}

const noWait = () => Promise.resolve();

describe('setting Memnox up', () => {
  it('does nothing when the daemon is ready', async () => {
    const machine = new Machine(true, true);
    const setup = new Setup(daemonAt({ now: '0.14.0' }), machine, new RequestIds(), noWait);
    expect(await setup.ensure()).toEqual({ kind: 'ready' });
    expect(machine.steps).toEqual([]);
  });

  it('installs memnox and wires the computer the first time', async () => {
    const version = { now: undefined as string | undefined };
    const machine = new Machine(false, false, (step) => {
      if (step === 'setup') version.now = '0.14.0';
    });
    const setup = new Setup(daemonAt(version), machine, new RequestIds(), noWait);
    expect(await setup.ensure()).toEqual({ kind: 'ready' });
    expect(machine.steps).toEqual(['install', 'setup']);
    expect(setup.state.failed).toBeUndefined();
  });

  it('only starts the service on a computer set up before', async () => {
    const version = { now: undefined as string | undefined };
    const machine = new Machine(true, true, (step) => {
      if (step === 'start') version.now = '0.14.0';
    });
    await new Setup(daemonAt(version), machine, new RequestIds(), noWait).ensure();
    expect(machine.steps).toEqual(['start']);
  });

  it('updates a daemon older than the app', async () => {
    const version = { now: '0.12.0' as string | undefined };
    const machine = new Machine(true, true, (step) => {
      if (step === 'update') version.now = '0.14.0';
    });
    expect(await new Setup(daemonAt(version), machine, new RequestIds(), noWait).ensure()).toEqual({ kind: 'ready' });
    expect(machine.steps).toEqual(['update']);
  });

  it('says why when memnox cannot be installed', async () => {
    const setup = new Setup(daemonAt({ now: undefined }), new Machine(false, false, () => undefined, false), new RequestIds(), noWait);
    await setup.ensure();
    expect(setup.state.failed).toContain('Node.js');
  });

  it('runs once for every caller at the same time', async () => {
    const machine = new Machine(true, true);
    const setup = new Setup(daemonAt({ now: undefined }), machine, new RequestIds(), noWait);
    await Promise.all([setup.ensure(), setup.ensure()]);
    expect(machine.steps).toEqual(['start']);
  });
});

describe('a daemon whose version does not show what it lacks', () => {
  it('updates one that answers no method for something the app needs', async () => {
    const updated = { done: false };
    const daemon = new ScriptedDaemon({
      ping: (request) => [{ id: request.id, ok: true, version: '0.14.0' }],
      machine: (request) => [updated.done ? { id: request.id, ok: true } : { id: request.id, ok: false, error: 'no method machine' }],
    });
    const machine = new Machine(true, true, (step) => {
      if (step === 'update') updated.done = true;
    });
    expect(await new Setup(daemon, machine, new RequestIds(), noWait).ensure()).toEqual({ kind: 'ready' });
    expect(machine.steps).toEqual(['update']);
  });

  it('restarts a local checkout rather than updating it from npm', async () => {
    const updated = { done: false };
    const daemon = new ScriptedDaemon({
      ping: (request) => [{ id: request.id, ok: true, version: '0.14.0' }],
      machine: (request) => [updated.done ? { id: request.id, ok: true } : { id: request.id, ok: false, error: 'no method machine' }],
    });
    const machine = new Machine(true, true, (step) => {
      if (step === 'start') updated.done = true;
    });
    machine.source = async () => ({ kind: 'local', checkout: '/src/memnox-runtime' });
    await new Setup(daemon, machine, new RequestIds(), noWait).ensure();
    expect(machine.steps).toEqual(['start']);
  });
});

describe('where memnox comes from', () => {
  it('reads anything but a local checkout with a path as npm', () => {
    expect(runtimeSourceOf({ kind: 'local', checkout: '/src/memnox-runtime' })).toEqual({ kind: 'local', checkout: '/src/memnox-runtime' });
    expect(runtimeSourceOf({ kind: 'local', checkout: '' })).toEqual({ kind: 'npm' });
    expect(runtimeSourceOf(undefined)).toEqual({ kind: 'npm' });
  });

  it('names the checkout when it is too old', () => {
    expect(whyNotReadyFrom({ kind: 'too-old' }, { kind: 'local', checkout: '/r' })).toContain('pnpm build');
    expect(whyNotReadyFrom({ kind: 'too-old' }, { kind: 'npm' })).toContain('older than the app');
  });
});

describe('versions', () => {
  it('compares by number, part by part', () => {
    expect(isAtLeast('0.13.14', '0.13.14')).toBe(true);
    expect(isAtLeast('0.13.9', '0.13.14')).toBe(false);
    expect(isAtLeast('1.0.0-beta', '0.13.14')).toBe(true);
    expect(isAtLeast(undefined, '0.13.14')).toBe(false);
  });
});

describe('the agent the voice thinks with', () => {
  it('lists the agents and keeps the one chosen', async () => {
    const daemon = new ScriptedDaemon({
      'voice-agents': (request) => [{ id: request.id, ok: true, voiceAgents: [] }],
      'choose-voice-agent': (request) => [{ id: request.id, ok: true, voiceAgents: [] }],
    });
    const settings = new VoiceSettings(daemon, new RequestIds());
    expect((await settings.agents(true)).kind).toBe('listed');
    await settings.choose('codex');
    expect(daemon.sent('voice-agents')[0]?.recheck).toBe(true);
    expect(daemon.sent('choose-voice-agent')[0]?.voiceAgent).toBe('codex');
  });
});
