import type { RuntimeState } from './runtime-state';
import { whyNotReady } from './runtime-state';

/**
 * Where this build of the app gets `memnox`, as the Mac's `RuntimeSource`: a development build pointed at a
 * `memnox-runtime` checkout through `MEMNOX_RUNTIME_DIR` runs that checkout's CLI, and every other build
 * installs the package published to npm.
 */
export type RuntimeSource =
  /** The runtime checkout at this path, for working on both at once. */
  | { kind: 'local'; checkout: string }
  /** The package published to npm, which is what a release installs. */
  | { kind: 'npm' };

/** What Rust reports, read so that anything but a local checkout with a path is npm, as a release is. */
export function runtimeSourceOf(fact: { kind?: unknown; checkout?: unknown } | undefined): RuntimeSource {
  if (fact?.kind === 'local' && typeof fact.checkout === 'string' && fact.checkout !== '') return { kind: 'local', checkout: fact.checkout };
  return { kind: 'npm' };
}

/** Why the daemon is still not there, naming the checkout's own fix where the runtime is built from one. */
export function whyNotReadyFrom(state: RuntimeState, source: RuntimeSource): string | undefined {
  if (state.kind === 'too-old' && source.kind === 'local') {
    return `The runtime in ${source.checkout} is older than this app. Pull it, run pnpm build there, then check again.`;
  }
  return whyNotReady(state);
}
