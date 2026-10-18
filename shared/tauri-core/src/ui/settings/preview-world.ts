import type { DaemonRequest, DaemonResponse, DeviceWire, HomeView, VoiceAgentStatus } from '@memnox/core/wire';
import type { ConfirmKey } from '../../core/application/ports/confirm-key';
import type { DaemonLink } from '../../core/application/ports/daemon-link';
import type { PreferenceStore } from '../../core/application/ports/preference-store';
import type { Runtime } from '../../core/application/ports/runtime';
import { PREFERENCE } from '../../core/application/preferences';
import type { Platform } from '../../core/domain/platform';
import type { SettingsHost } from './host';

/**
 * A computer and a daemon made of script, so every Settings page and first run step draws in a plain
 * browser: `pnpm dev`, then /settings.html?page=phones&state=digits&theme=dark. Nothing here reaches Tauri.
 */
const asked = new URLSearchParams(window.location.search);
/** Which variant of a page to draw, such as signed-in on Account or qr on Phones. */
export const previewState = asked.get('state') ?? '';
const platform: Platform = asked.get('platform') === 'linux' ? 'linux' : 'windows';

const agents: VoiceAgentStatus[] = [
  { kind: 'claude-code', label: 'Claude Code', installed: true, sealed: true, works: true, chosen: true, install: '' },
  { kind: 'codex', label: 'Codex', installed: true, sealed: true, works: true, chosen: false, install: '' },
  { kind: 'cursor', label: 'Cursor', installed: true, sealed: false, works: false, because: 'its plan ran out', reply: 'You have reached your usage limit.', chosen: false, install: '' },
  { kind: 'hermes', label: 'Hermes', installed: false, sealed: true, chosen: false, install: 'pip install hermes' },
];

const home: HomeView = {
  machine: 'desk',
  mode: 'enforce',
  waiting: 2,
  working: [
    { sessionId: 's1', agent: 'claude-code', agentName: 'Claude Code', task: 'Port the Settings window', repository: 'memnox-desktop' },
    { sessionId: 's2', agent: 'codex', agentName: 'Codex', task: 'Fix the flaky relay test', repository: 'memnox-runtime' },
  ],
  today: { actions: 41, asked: 6, allowed: 5, refused: 1 },
  ready: { action: 'git push', approvals: 5, agentName: 'Codex', targets: ['origin feature/*'], because: 'Every push this week went to a feature branch and you allowed each one.' },
  notCovered: { unprotected: 1, dormant: 0 },
  needsYou: ['Approve the Memnox hooks in Codex, so its commands are checked.'],
};

const phones: DeviceWire[] = [{ id: 'dev_1', name: 'Sam’s iPhone', kind: 'phone', fingerprint: 'fp', capabilities: ['see', 'ask', 'answer', 'mac'], pairedAt: '2026-10-01T10:00:00Z' }];

const qr =
  'memnox://pair?d=eyJ2IjoxLCJtYWNoaW5lSWQiOiJtX2Rlc2siLCJtYWNoaW5lIjoiRGVzayIsInJlbGF5VXJsIjoid3NzOi8vcmVsYXkubWVtbm94LmNvbSIsIm1haWxib3giOiJhYmNkZWYiLCJwYWlyaW5nVG9rZW4iOiJybHBfMTIzIn0';

/** Every method a page asks, answered from the scene. */
function answer(request: DaemonRequest): DaemonResponse[] {
  const ok = { id: request.id, ok: true };
  switch (request.method) {
    case 'ping':
      return [{ ...ok, version: '0.20.0' }];
    case 'register-key':
      return [{ ...ok, outcome: previewState === 'key-missing' ? 'another key' : 'registered' }];
    case 'voice-agents':
    case 'choose-voice-agent':
      return [{ ...ok, voiceAgents: agents }];
    case 'home':
      return previewState === 'no-home' ? [{ id: request.id, ok: false, error: 'no method home' }] : [{ ...ok, home }];
    case 'waiting':
      return [{ ...ok, waiting: [] }];
    case 'sessions-list':
      return [{ ...ok, sessions: [] }];
    case 'person':
      return [{ ...ok, person: previewState === 'signed-in' ? { signedIn: true, name: 'Sam Rivera' } : { signedIn: false, ...(previewState === 'code' ? { code: { userCode: 'WDJB-MJHT', expiresAt: Date.now() + 600_000 } } : {}) } }];
    case 'machine':
      return [{ ...ok, machine: previewState === 'code' || previewState === 'signed-out' ? { signedIn: false } : { signedIn: true, name: 'Acme' } }];
    case 'person-sign-in':
      return [{ ...ok, person: { signedIn: false, code: { userCode: 'WDJB-MJHT', expiresAt: Date.now() + 600_000 } } }];
    case 'connections-list':
      return [{ ...ok, connections: [{ toolkit: 'github', connected: true }, { toolkit: 'slack', connected: true }, { toolkit: 'gmail', connected: false }] }];
    case 'devices-list':
      return [{ ...ok, devices: previewState === 'none' ? [] : phones }];
    case 'pair-begin':
      return [{ ...ok, outcome: 'pairing', pairing: { id: 'pr_1', qr, state: 'waiting' } }];
    case 'pair-pending':
      return previewState === 'digits' ? [{ ...ok, pairing: { id: 'pr_1', state: 'answered', phone: { name: 'iPhone', fingerprint: 'fp', code: '482913' } } }] : [];
    default:
      return [ok];
  }
}

export const previewLink: DaemonLink = {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    yield* answer(request);
    // A pairing still waiting stays open, as the daemon keeps it.
    if (request.method === 'pair-pending') await new Promise<never>(() => undefined);
  },
};

export const previewRuntime: Runtime = {
  found: async () => true,
  install: async () => true,
  wired: async () => true,
  run: async () => true,
};

export const previewKey: ConfirmKey = {
  publicPoint: async () => 'BPOINT',
  sign: async (message) => `sig(${message})`,
};

/** A store in memory, seeded so the overview shows a person part way through setup. */
export class PreviewStore implements PreferenceStore {
  private readonly kept = new Map<string, string>();

  constructor(seed: Record<string, string>) {
    for (const [key, value] of Object.entries(seed)) this.kept.set(key, value);
  }

  load(key: string): string | null {
    return this.kept.get(key) ?? null;
  }

  save(key: string, value: string): void {
    if (value === '') this.kept.delete(key);
    else this.kept.set(key, value);
    window.dispatchEvent(new CustomEvent('memnox-preference', { detail: key }));
  }
}

export function previewSeed(): Record<string, string> {
  const look = asked.get('theme');
  const seed: Record<string, string> = { [PREFERENCE.name]: 'Sam Rivera', [PREFERENCE.firstRun]: 'mac' };
  if (look === 'light' || look === 'dark') seed[PREFERENCE.appearance] = look;
  if (previewState === 'firstrun') {
    delete seed[PREFERENCE.firstRun];
    delete seed[PREFERENCE.name];
  }
  if (previewState === 'home') seed[PREFERENCE.setupDone] = 'true';
  if (previewState === 'dictation') {
    seed['memnox.dictation.words'] = JSON.stringify([{ said: 'orb', written: 'ORB' }, { written: 'Memnox' }]);
    seed['memnox.dictation.history'] = JSON.stringify([
      { written: 'Can you rerun the relay tests and tell me which one flakes?', app: 'Slack', at: Date.parse('2026-10-18T09:41:00') },
      { written: 'Ship it once the build is green.', at: Date.parse('2026-10-18T09:12:00') },
    ]);
  }
  return seed;
}

export const previewHost: SettingsHost = {
  platform,
  computerName: () => 'Desk',
  permissionFacts: async () => {
    // An editor here, and the extension landed except in the state that shows what still needs doing.
    const editors = { present: true, withExtension: previewState === 'needs' ? [] : ['.vscode/extensions'] };
    return platform === 'linux'
      ? { platform, session: 'wayland', microphone: 'allowed', typing: previewState !== 'needs', editors, polkitAgent: previewState !== 'needs', seeing: { portal: true, accessibility: true } }
      : { platform, session: 'desktop', microphone: previewState === 'needs' ? 'denied' : 'allowed', typing: true, editors };
  },
  openPrivacy: async () => true,
  startsAtSignIn: async () => previewState !== 'needs',
  setStartsAtSignIn: async (on) => on,
  restart: () => undefined,
  openPage: () => undefined,
  openSettings: () => undefined,
  openOnboarding: () => undefined,
  close: () => undefined,
  applyLook: () => undefined,
  talk: () => undefined,
  copy: async () => undefined,
  onShowPage: () => () => undefined,
  voices: {
    choice: async () => ({ voices: ['af_sky', 'af_heart', 'af_bella', 'af_nicole', 'af_sarah', 'am_adam', 'am_michael', 'bf_emma', 'bf_isabella', 'bm_george', 'bm_lewis'], chosen: 'af_heart' }),
    choose: async () => undefined,
    installed: async () => previewState !== 'installing',
    install: () => new Promise<void>(() => undefined),
    say: async () => undefined,
    test: async () => undefined,
  },
};
