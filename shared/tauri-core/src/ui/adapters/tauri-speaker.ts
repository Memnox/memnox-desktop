import { invoke } from '@tauri-apps/api/core';
import type { Hushable, Speaker } from '../../core';
import { TAURI_COMMAND } from './tauri-commands';

/** Kokoro through the Rust voice: sentences said in order, a stop that cuts the one playing and drops the rest. */
export class TauriSpeaker implements Speaker, Hushable {
  private said: Promise<void> = Promise.resolve();

  queue(sentence: string): void {
    this.said = invoke<void>(TAURI_COMMAND.speak, { sentence }).catch(() => undefined);
  }

  drained(): Promise<void> {
    return this.said;
  }

  stop(): void {
    void invoke(TAURI_COMMAND.speakStop);
  }

  /** Held quiet while somebody may be talking over it. */
  hush(): void {
    void invoke(TAURI_COMMAND.speakHush);
  }

  carryOn(): void {
    void invoke(TAURI_COMMAND.speakCarryOn);
  }
}
