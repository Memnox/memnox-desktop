import { createContext, useContext, useState } from 'react';

/** What an inspector needs from the window it is drawn in: whether it is the whole window, and how to pop one out. */
export interface InspectorHost {
  /** The window is a popped out inspector, so the inspector fills it and closing it closes the window. */
  readonly alone: boolean;
  /** The item the window's link named, which its page opens with picked. */
  readonly item: string | undefined;
  /** Opens the item's details in a window of their own; absent where no window can be made, as in a preview. */
  readonly popOut: ((item: string, title: string) => void) | undefined;
  readonly close: () => void;
}

export const InspectorWindow = createContext<InspectorHost>({ alone: false, item: undefined, popOut: undefined, close: () => undefined });

export function useInspectorHost(): InspectorHost {
  return useContext(InspectorWindow);
}

/** A page's picked item, starting on the one the window's link named, so a popped out inspector opens on it. */
export function usePicked(): [string | undefined, (item: string | undefined) => void] {
  const { item } = useInspectorHost();
  return useState<string | undefined>(item);
}
