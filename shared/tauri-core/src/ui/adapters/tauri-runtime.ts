import { invoke } from '@tauri-apps/api/core';
import type { Runtime, RuntimeStep } from '../../core';

/** The runtime through Rust, which runs only the fixed line each step names. */
export class TauriRuntime implements Runtime {
  found(): Promise<boolean> {
    return invoke<boolean>('runtime_found');
  }

  install(): Promise<boolean> {
    return invoke<boolean>('runtime_install');
  }

  wired(): Promise<boolean> {
    return invoke<boolean>('runtime_wired');
  }

  run(step: RuntimeStep): Promise<boolean> {
    return invoke<boolean>('runtime_run', { step });
  }
}

/** The Kokoro voices on offer and the one chosen, kept by Rust beside the app's settings. */
export const kokoro = {
  choice: () => invoke<{ voices: string[]; chosen: string | null }>('voice_choice'),
  choose: (id: string) => invoke<void>('choose_voice', { id }),
};
