import { invoke } from '@tauri-apps/api/core';
import type { Power } from '../../core';

/** The charger and the hold on sleep, through `SetThreadExecutionState` or `systemd-inhibit`. */
export class TauriPower implements Power {
  onMains(): Promise<boolean> {
    return invoke<boolean>('on_power');
  }

  keepAwake(on: boolean): Promise<void> {
    return invoke('keep_awake', { on });
  }
}
