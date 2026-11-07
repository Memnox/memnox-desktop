import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { createPortal } from 'react-dom';
import { useDismiss } from './dismiss';
import { SPACING } from './metrics';

/**
 * Which side of its press a popover opens on, as SwiftUI's `arrowEdge` places it: `below` hangs under the press,
 * `trailing` stands beside it, its top level with the press's.
 */
export type PopoverSide = 'below' | 'trailing';

/** The room between the press and the popover. */
const POPOVER_GAP = SPACING.small;

/** Where the popover's top left corner sits in the window, measured from the press. */
function placed(press: DOMRect, side: PopoverSide): { top: number; left: number } {
  switch (side) {
    case 'below':
      return { top: press.bottom + POPOVER_GAP, left: press.left };
    case 'trailing':
      return { top: press.top, left: press.right + POPOVER_GAP };
  }
}

/**
 * A panel anchored to the press that opened it, as the Mac's `.popover`: the console's card at radius 12 with the
 * lift under it, drawn over the whole window so a scrolling sidebar does not clip it. A press outside it or Escape
 * puts it away through `onClose`; a press on the anchor is left to the anchor, which toggles it.
 */
export function Popover({
  anchor,
  side = 'below',
  label,
  onClose,
  className,
  children,
}: {
  anchor: RefObject<HTMLElement>;
  side?: PopoverSide;
  /** Names the panel for a screen reader. */
  label: string;
  onClose: () => void;
  /** Only its width and what it holds, as `w-switcher p-3`. */
  className?: string;
  children: ReactNode;
}) {
  const surface = useRef<HTMLDivElement>(null);
  const [place, setPlace] = useState<{ top: number; left: number }>();
  useDismiss(surface, onClose, anchor);
  useLayoutEffect(() => {
    const measure = () => {
      const press = anchor.current?.getBoundingClientRect();
      if (press !== undefined) setPlace(placed(press, side));
    };
    measure();
    // The press moves with the window and with whatever scrolls it, so the popover follows.
    window.addEventListener('resize', measure);
    window.addEventListener('scroll', measure, true);
    return () => {
      window.removeEventListener('resize', measure);
      window.removeEventListener('scroll', measure, true);
    };
  }, [anchor, side]);
  return createPortal(
    <div
      ref={surface}
      role="dialog"
      aria-label={label}
      className={`fixed z-50 flex flex-col rounded-card border border-panel-edge bg-card shadow-lift ${place === undefined ? 'invisible' : ''} ${className ?? ''}`}
      style={place}
    >
      {children}
    </div>,
    document.body,
  );
}
