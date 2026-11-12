import { invoke } from '@tauri-apps/api/core';
import type { ReleaseFeed } from '../../core/application/ports/release-feed';
import type { Preferences } from '../../core/application/preferences';
import type { Runtime } from '../../core/application/ports/runtime';
import type { Setup } from '../../core/application/setup';
import { Updates } from '../../core/application/updates';
import type { Platform } from '../../core/domain/platform';
import { TAURI_COMMAND } from './tauri-commands';

/** The app's releases and the runtime's newest version through `updates.rs`, which reaches those two lists and nothing else. */
export const tauriReleaseFeed: ReleaseFeed = {
  read: (list) => invoke<string>(TAURI_COMMAND.releaseFeed, { list }).catch(() => undefined),
};

/** The version this app was built as. */
export const tauriAppVersion = (): Promise<string | undefined> => invoke<string>(TAURI_COMMAND.appVersion).catch(() => undefined);

/** What a window hands over so it can offer updates: all optional, so a preview and a test offer nothing. */
export interface UpdateSeams {
  readonly feed?: ReleaseFeed;
  readonly appVersion?: () => Promise<string | undefined>;
}

/**
 * The update offers over one window's own setup and preferences. A runtime built from a checkout keeps its version
 * while its code moves, so it is never offered the published one, as setup never swaps a checkout for a release.
 */
export function updatesOver(seams: UpdateSeams, platform: Platform, setup: Setup, runtime: Runtime, preferences: Preferences, openPage: (url: string) => void): Updates {
  return new Updates(seams.feed, {
    platform,
    appVersion: () => seams.appVersion?.() ?? Promise.resolve(undefined),
    runtimeVersion: async () => {
      const source = await runtime.source?.().catch(() => undefined);
      if (source?.kind === 'local') return undefined;
      const state = await setup.check();
      return state.kind === 'ready' ? setup.state.version : undefined;
    },
    skipped: (kind) => preferences.skippedUpdate(kind),
    putOff: (kind, version) => preferences.putOffUpdate(kind, version),
    updateRuntime: async () => {
      await setup.bringUpToDate();
      return setup.state.failed;
    },
    openPage,
  });
}
