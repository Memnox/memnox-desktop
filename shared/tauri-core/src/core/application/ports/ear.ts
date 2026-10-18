/** What the open ear reports, in order, until it closes. */
export type EarEvent =
  /** How loud the room is and how loud the voice is playing, both from nothing to one. */
  | { readonly kind: 'level'; readonly heard: number; readonly playing: number }
  /** Somebody started talking: a new stretch of speech began. */
  | { readonly kind: 'speech' }
  /** The words of the stretch under way so far, or, once `final`, the whole of it. */
  | { readonly kind: 'words'; readonly text: string; readonly final: boolean }
  /** The last event, with why when the microphone failed. */
  | { readonly kind: 'closed'; readonly error?: string | null };

/**
 * The microphone kept open, hearing stretch after stretch of speech on this computer: Silero finds where
 * somebody spoke and Parakeet writes it down. One ear at a time; opening a second closes the first.
 */
export interface Ear {
  /** Resolves once the microphone is open, or rejects with why in plain words. */
  open(onEvent: (event: EarEvent) => void, options: { partials: boolean }): Promise<void>;
  /** Finishes the stretch under way, so its last words arrive, then closes; resolves after `closed`. */
  close(): Promise<void>;
}
