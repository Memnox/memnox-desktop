import type { RuntimeSource } from '../../domain/runtime-source';

/** The three things setup may have the runtime do, and nothing else, so no screen can run a command of its choosing. */
export type RuntimeStep = 'setup' | 'start' | 'update';

/** The Memnox runtime on this computer, through Rust, which runs `memnox` the way the person's own shell would. */
export interface Runtime {
  /** Whether `memnox` is installed here. */
  found(): Promise<boolean>;
  /** Installs it from npm; false when it could not, with Node missing the usual reason. */
  install(): Promise<boolean>;
  /** Whether this computer was ever set up, so the first run wires the agents and later ones only start the service. */
  wired(): Promise<boolean>;
  /** `memnox setup --yes --no-probe`, `memnox daemon --install` or `memnox update --yes`; false when it failed. */
  run(step: RuntimeStep): Promise<boolean>;
  /** Where this build gets `memnox`; a runtime that cannot say is npm, as a release is. */
  source?(): Promise<RuntimeSource>;
}
