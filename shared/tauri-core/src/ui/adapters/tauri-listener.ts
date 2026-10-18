import { Channel, invoke } from '@tauri-apps/api/core';

/** One step of the voice install, as Rust reports it. */
export interface InstallStep {
  part: string;
  done: number;
  total: number | null;
}

/** The microphone and the voice's models, through the Rust voice. */
export const voice = {
  installed: (): Promise<boolean> => invoke<boolean>('voice_installed'),

  install: (onStep: (step: InstallStep) => void): Promise<void> => {
    const steps = new Channel<InstallStep>();
    steps.onmessage = onStep;
    return invoke('voice_install', { steps });
  },

  /**
   * What the person said in one utterance, undefined when they said nothing. `onLevel` hears the
   * microphone's loudness, from nothing to one, for every chunk it reads, so the orb moves with them.
   */
  listenOnce: async (onLevel?: (level: number) => void): Promise<string | undefined> => {
    const levels = new Channel<number>();
    if (onLevel !== undefined) levels.onmessage = onLevel;
    return (await invoke<string | null>('listen_once', { levels })) ?? undefined;
  },
};
