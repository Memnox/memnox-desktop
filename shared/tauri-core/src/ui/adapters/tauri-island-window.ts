import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

/** A box in the island window's own CSS pixels, top left at the window's top left. */
export interface HitArea {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** True inside the Tauri app, false in the preview page, where there is no window to tell. */
const inTauri = (): boolean => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/**
 * The island window as Rust holds it: the webview says where its shape, its pills and its satellites
 * are, and Rust lets every click elsewhere fall through to the window underneath.
 */
export const islandWindow = {
  /** Where clicks are taken; everywhere else they pass through. */
  setHitAreas(areas: readonly HitArea[]): void {
    if (inTauri()) void invoke('island_hit_areas', { areas }).catch(() => undefined);
  },

  /**
   * Hears when the pointer leaves or reaches the island while the window ignores the mouse, since the
   * webview sees no pointer events then and so never hears it leave.
   */
  onPointer(listener: (over: boolean) => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = listen<{ over: boolean }>('island-pointer', (event) => listener(event.payload.over));
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },
};
