import { useRef, type ReactNode } from 'react';
import { Pressable } from './Button';
import { useDismiss } from './dismiss';

/**
 * A panel slid in from the leading edge over a dimmed window, as `AppShellView.sheet` lays the sidebar over the page on
 * the narrowest windows: the panel on the ground colour, and beside it a scrim at `sheetScrim` that closes it when
 * pressed. Escape closes it too.
 */
export function SideDrawer({ label, closeLabel, onClose, children }: { label: string; closeLabel: string; onClose: () => void; children: ReactNode }) {
  const panel = useRef<HTMLDivElement>(null);
  // The scrim is the outside press, so only Escape is left for the hook to catch.
  useDismiss(panel, onClose, panel);
  return (
    <div className="fixed inset-0 z-40 flex" role="dialog" aria-modal="true" aria-label={label}>
      <div ref={panel} className="h-full animate-drawer-in bg-background shadow-2xl">
        {children}
      </div>
      <Pressable className="flex-1 animate-scrim-in cursor-default bg-black/40" aria-label={closeLabel} onClick={onClose} />
    </div>
  );
}
