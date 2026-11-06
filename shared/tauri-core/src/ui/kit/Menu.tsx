import type { ReactNode } from 'react';
import { Pressable } from './Button';

/**
 * Whose surface a menu opens on: the console's card under a page's press, or the island's dark glass, as the Mac's
 * `NSMenu` over a card.
 */
export type MenuTone = 'console' | 'island';

const MENU_FRAME: Record<MenuTone, string> = {
  console: 'flex flex-col rounded-lg border border-panel-edge bg-card p-1 shadow-[0_12px_32px_rgb(0_0_0/0.16)]',
  island: 'min-w-max animate-[fade-in_120ms_ease-out] rounded-control border border-white/[0.14] bg-[#2a2a2c]/95 p-[5px] shadow-[0_8px_24px_rgb(0_0_0/0.5)] backdrop-blur-xl',
};

const MENU_ITEM: Record<MenuTone, string> = {
  console: 'mx-focus flex w-full cursor-pointer items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-body-sm text-foreground hover:bg-hover disabled:cursor-default disabled:text-faint disabled:hover:bg-transparent',
  island: 'flex w-full cursor-pointer items-center gap-1.5 rounded-key px-2 py-[3px] text-left text-body text-white hover:bg-primary',
};

/** A menu's list. `className` only places it beside its press, as `absolute top-7 right-0 z-20 w-60`. */
export function Menu({ tone = 'console', className, onMouseLeave, children }: { tone?: MenuTone; className?: string; onMouseLeave?: () => void; children: ReactNode }) {
  return (
    <div role="menu" className={`${MENU_FRAME[tone]} ${className ?? ''}`} onMouseLeave={onMouseLeave}>
      {children}
    </div>
  );
}

/** One choice of a menu, its glyph before its words. */
export function MenuItem({ tone = 'console', onPress, disabled, children }: { tone?: MenuTone; onPress?: () => void; disabled?: boolean; children: ReactNode }) {
  return (
    <Pressable role="menuitem" className={MENU_ITEM[tone]} disabled={disabled} onClick={onPress}>
      {children}
    </Pressable>
  );
}

/** A hairline between groups of a menu. */
export function MenuSeparator() {
  return <div className="my-1 h-px bg-panel-edge" role="separator" />;
}
