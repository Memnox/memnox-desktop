import type { ConfirmKey } from '../../core/application/ports/confirm-key';
import type { DaemonLink } from '../../core/application/ports/daemon-link';
import type { Pairer } from '../../core/application/ports/pairer';
import type { Runtime } from '../../core/application/ports/runtime';
import type { HttpTransport, PersonCredentialStore } from '../../core/application/ports/workspace-inbox';
import { DemoLink } from './demo-link';
import { TauriConfirmKey } from './tauri-confirm-key';
import { TauriDaemonLink } from './tauri-daemon-link';
import { TauriRuntime } from './tauri-runtime';

/**
 * Demo mode, for judging the design with every page full: on only when the app was started with MEMNOX_DEMO=1, which
 * Rust says to every window before its script runs, or in a browser preview opened with ?state=demo.
 */
export const demoOn: boolean =
  (typeof window !== 'undefined' && '__MEMNOX_DEMO__' in window) ||
  (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('state') === 'demo');

let demo: Promise<DemoLink> | undefined;

/** The one demo daemon of this window, read only once demo mode asks for it, so a real app never loads the fixture. */
export function demoLink(): Promise<DemoLink> {
  demo ??= import('../../../../demo/power-user.json').then((fixture) => new DemoLink(fixture.default));
  return demo;
}

/** The demo daemon behind the port, waiting for the fixture before the first answer. */
const lazyDemo: DaemonLink = {
  async *stream(request) {
    yield* (await demoLink()).stream(request);
  },
};

/** The daemon each window talks to: the demo world in demo mode, else the real one through Rust. */
export function daemonLink(): DaemonLink {
  return demoOn ? lazyDemo : new TauriDaemonLink();
}

/** A runtime that is always there and never runs a line, so a demo installs, starts and updates nothing. */
const inertRuntime: Runtime = {
  found: async () => true,
  install: async () => true,
  wired: async () => true,
  run: async () => true,
};

export function runtime(): Runtime {
  return demoOn ? inertRuntime : new TauriRuntime();
}

/** A key that signs nothing anybody verifies, so a demo never raises Windows Hello or the Secret Service. */
const demoKey: ConfirmKey = {
  publicPoint: async () => 'demo',
  sign: async (message) => `demo:${message.length}`,
};

export function confirmKey(): ConfirmKey {
  return demoOn ? demoKey : new TauriConfirmKey();
}

const never = new Promise<never>(() => undefined);

/** No server is paired and none is dialed, and Memnox Cloud is never reached, so the demo stays on this computer. */
export const demoPairer: Pairer = {
  pair: () => never,
  servers: async () => [],
  forget: async () => undefined,
};

export const demoCloud: HttpTransport = {
  send: async () => {
    throw new Error((await demoLink()).demoOnly);
  },
};

/** Signed in as the demo's person, with made up ids and no real token. */
export const demoCredentials: PersonCredentialStore = {
  load: async () => ({ token: 'demo', tokenId: 'tok_demo', personId: 'psn_demo', name: (await demoLink()).personName, orgId: 'org_acme', workspaces: ['ws_acme'], deviceId: 'dev_demo' }),
  save: async () => undefined,
  delete: async () => undefined,
};
