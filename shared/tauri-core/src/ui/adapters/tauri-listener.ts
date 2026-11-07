import { Channel, invoke } from '@tauri-apps/api/core';
import { TAURI_COMMAND } from './tauri-commands';

/** One step of the voice install, as Rust reports it. */
export interface InstallStep {
  part: string;
  done: number;
  total: number | null;
}

/** The microphone and the voice's models, through the Rust voice. */
export const voice = {
  installed: (): Promise<boolean> => invoke<boolean>(TAURI_COMMAND.voiceInstalled),

  install: (onStep: (step: InstallStep) => void): Promise<void> => {
    const steps = new Channel<InstallStep>();
    steps.onmessage = onStep;
    return invoke(TAURI_COMMAND.voiceInstall, { steps });
  },

  /**
   * What the person said in one utterance, undefined when they said nothing. `onLevel` hears the
   * microphone's loudness, from nothing to one, for every chunk it reads, so the orb moves with them.
   */
  listenOnce: async (onLevel?: (level: number) => void): Promise<string | undefined> => {
    const levels = new Channel<number>();
    if (onLevel !== undefined) levels.onmessage = onLevel;
    return (await invoke<string | null>(TAURI_COMMAND.listenOnce, { levels })) ?? undefined;
  },
};
