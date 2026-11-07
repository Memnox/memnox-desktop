import { invoke } from '@tauri-apps/api/core';
import type { Power } from '../../core';
import { TAURI_COMMAND } from './tauri-commands';

/** The charger and the hold on sleep, through `SetThreadExecutionState` or `systemd-inhibit`. */
export class TauriPower implements Power {
  onMains(): Promise<boolean> {
    return invoke<boolean>(TAURI_COMMAND.onPower);
  }

  keepAwake(on: boolean): Promise<void> {
    return invoke(TAURI_COMMAND.keepAwake, { on });
  }
}
