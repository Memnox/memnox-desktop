import { invoke } from '@tauri-apps/api/core';
import type { Runtime, RuntimeStep } from '../../core';
import { runtimeSourceOf, type RuntimeSource } from '../../core/domain/runtime-source';
import { TAURI_COMMAND } from './tauri-commands';

/** The runtime through Rust, which runs only the fixed line each step names. */
export class TauriRuntime implements Runtime {
  found(): Promise<boolean> {
    return invoke<boolean>(TAURI_COMMAND.runtimeFound);
  }

  install(): Promise<boolean> {
    return invoke<boolean>(TAURI_COMMAND.runtimeInstall);
  }

  wired(): Promise<boolean> {
    return invoke<boolean>(TAURI_COMMAND.runtimeWired);
  }

  run(step: RuntimeStep): Promise<boolean> {
    return invoke<boolean>(TAURI_COMMAND.runtimeRun, { step });
  }

  build(): Promise<boolean> {
    return invoke<boolean>(TAURI_COMMAND.runtimeBuild);
  }

  async source(): Promise<RuntimeSource> {
    return runtimeSourceOf(await invoke<{ kind?: unknown; checkout?: unknown }>(TAURI_COMMAND.runtimeSource));
  }
}

/** The Kokoro voices on offer and the one chosen, kept by Rust beside the app's settings. */
export const kokoro = {
  choice: () => invoke<{ voices: string[]; chosen: string | null }>(TAURI_COMMAND.voiceChoice),
  choose: (id: string) => invoke<void>(TAURI_COMMAND.chooseVoice, { id }),
};
