import { invoke } from '@tauri-apps/api/core';
import type { Speaker } from '../../core';

/** Kokoro through the Rust voice: sentences said in order, a stop that drops whatever waits. */
export class TauriSpeaker implements Speaker {
  private said: Promise<void> = Promise.resolve();

  queue(sentence: string): void {
    this.said = invoke<void>('speak', { sentence }).catch(() => undefined);
  }

  drained(): Promise<void> {
    return this.said;
  }

  stop(): void {
    void invoke('speak_stop');
  }
}
