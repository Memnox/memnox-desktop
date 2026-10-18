import type { HistoryStore } from '../../core';

/** Where the exchanges are kept, the webview's own storage, which every window of this app shares. */
export const HISTORY_KEY = 'memnox.history';

/** The history kept between launches; a storage the webview refuses reads as empty rather than failing. */
export const localHistory: HistoryStore = {
  load() {
    try {
      return window.localStorage.getItem(HISTORY_KEY);
    } catch {
      return null;
    }
  },
  save(text) {
    try {
      window.localStorage.setItem(HISTORY_KEY, text);
    } catch {
      // A full or refused storage loses only this change; the side panel still shows what it holds.
    }
  },
};
