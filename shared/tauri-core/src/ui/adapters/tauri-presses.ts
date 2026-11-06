import { Channel, invoke } from '@tauri-apps/api/core';
import type { Press, PressChannel } from '../../core/application/presses';
import { TAURI_COMMAND } from './tauri-commands';

/** Tells the island of a press in the Memnox window; Rust takes it only from the window's own labels. */
export const tellIsland: PressChannel = (press) => {
  void invoke(TAURI_COMMAND.windowPress, { press }).catch(() => undefined);
};

/** The island's end: a channel Rust holds for the island alone, so no other window can put a press in it. */
export function hearPresses(heard: (press: Press) => void): void {
  const presses = new Channel<Press>();
  presses.onmessage = heard;
  void invoke(TAURI_COMMAND.pressesListen, { presses }).catch(() => undefined);
}
