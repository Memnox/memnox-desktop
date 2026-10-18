import { invoke } from '@tauri-apps/api/core';
import { emitTo, listen } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';

/** Told to the island by the side panel when an exchange is picked there, to open it tall. */
const PICKED_EVENT = 'side-exchange';
/** Told by Rust when a press lands outside every window of this app, which puts the open island away. */
const OUTSIDE_EVENT = 'island-outside';
/** Told to the island by Settings, whose home's Answer opens it on what waits. */
const ISLAND_OPEN_EVENT = 'island-open';

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
  setHitAreas(areas: readonly HitArea[], resting?: boolean): void {
    if (inTauri()) void invoke('island_hit_areas', { areas, resting }).catch(() => undefined);
  },

  /** Takes the keyboard for this window, or gives it back to where the person was typing. */
  keyboard(on: boolean): void {
    if (inTauri()) void invoke('island_keyboard', { on }).catch(() => undefined);
  },

  /**
   * Hears when the pointer leaves or reaches the island while the window ignores the mouse, since the
   * webview sees no pointer events then and so never hears it leave.
   */
  onPointer(listener: (over: boolean) => void): () => void {
    if (!inTauri()) return () => undefined;
    // Heard on this window alone, since the side panel and the card wall are followed the same way.
    const stop = getCurrentWebviewWindow().listen<{ over: boolean }>('island-pointer', (event) => listener(event.payload.over));
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** The side panel hands the island the exchange picked there, by its id in the shared history. */
  pick(id: string): void {
    if (inTauri()) void emitTo('island', PICKED_EVENT, id).catch(() => undefined);
  },

  onPicked(listener: (id: string) => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = listen<string>(PICKED_EVENT, (event) => listener(event.payload));
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** Asks the island to open on what waits, from Settings; nothing in a preview, where there is no island. */
  openFromSettings(): void {
    if (inTauri()) void emitTo('island', ISLAND_OPEN_EVENT).catch(() => undefined);
  },

  /** The displays the island can hang from and the one chosen, for the Appearance page. */
  screens(): Promise<{ chosen: string; displays: { id: string; name: string }[] }> {
    return inTauri() ? invoke('island_screens') : Promise.resolve({ chosen: 'notch', displays: [] });
  },

  chooseScreen(stored: string): Promise<void> {
    return inTauri() ? invoke('island_screen_choose', { stored }) : Promise.resolve();
  },

  /** Settings asks the island to open, for the home's Answer. */
  onOpenAsked(listener: () => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = listen(ISLAND_OPEN_EVENT, () => listener());
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** A press in another app, which a window of ours hears only from Rust, since the press never reaches it. */
  onOutsidePress(listener: () => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = getCurrentWebviewWindow().listen(OUTSIDE_EVENT, () => listener());
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },
};
