import { useEffect, useRef, type RefObject } from 'react';

/**
 * What the Mac's menus and popovers do without being asked: a press anywhere outside them, or Escape, puts them away.
 * Escape is caught before the window's own shortcuts see it, so closing a menu never also closes the window. A press
 * on `anchor`, the control that opened it, is left to that control, which toggles it.
 */
export function useDismiss(surface: RefObject<HTMLElement>, onClose: (() => void) | undefined, anchor?: RefObject<HTMLElement>): void {
  // The latest close, so a caller's new closure each render does not rebind the listeners.
  const close = useRef(onClose);
  close.current = onClose;
  const shown = onClose !== undefined;
  useEffect(() => {
    if (!shown) return;
    const inside = (target: EventTarget | null) =>
      target instanceof Node && (surface.current?.contains(target) === true || anchor?.current?.contains(target) === true);
    const pressed = (event: PointerEvent) => {
      if (!inside(event.target)) close.current?.();
    };
    const keyed = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.stopPropagation();
      close.current?.();
    };
    document.addEventListener('pointerdown', pressed, true);
    window.addEventListener('keydown', keyed, true);
    return () => {
      document.removeEventListener('pointerdown', pressed, true);
      window.removeEventListener('keydown', keyed, true);
    };
  }, [shown, surface, anchor]);
}
