import { invoke } from '@tauri-apps/api/core';
import type { ConfirmKey } from '../../core';

/** The TPM key on Windows or the Secret Service key on Linux, each asking the person before it signs. */
export class TauriConfirmKey implements ConfirmKey {
  async publicPoint(): Promise<string | undefined> {
    return (await invoke<string | null>('confirm_key_point')) ?? undefined;
  }

  async sign(message: string, reason: string): Promise<string | undefined> {
    return (await invoke<string | null>('confirm_key_sign', { message, reason })) ?? undefined;
  }
}
