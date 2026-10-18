import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { SFSymbol, type SFSymbolName } from './symbols';

/** The answer that lets something happen, or any other. */
export type IslandButtonKind = 'primary' | 'secondary';

/**
 * `IslandButton`'s look as classes, for a link or a menu trigger that must read as the pill: a borderless
 * capsule, 12.5 medium, 14 by 7, scale 0.94 pressed on spring(0.2, 0.6). Primary is #F5F6F8 with
 * #0B0C0E words in every state; secondary is white 9% at rest and 15% held down, with white words. It
 * has no hover look at all, as on the Mac. A lone disabled pill dims to 0.4; a card dims its whole row instead.
 */
export function islandButtonClass(kind: IslandButtonKind): string {
  const fill =
    kind === 'primary'
      ? 'bg-island-primary-fill text-island-primary-text'
      : 'bg-white/[0.09] text-white enabled:active:bg-white/15';
  return [
    'inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-full border-0',
    'px-3.5 py-[7px] font-sans text-button font-medium',
    'cursor-pointer select-none outline-none transition-[scale,background-color] duration-[220ms] ease-press',
    'enabled:active:scale-[0.94] disabled:cursor-default disabled:opacity-40',
    'focus-visible:ring-2 focus-visible:ring-primary/70',
    fill,
  ].join(' ');
}

export interface IslandButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  kind?: IslandButtonKind;
  /** A symbol before the words, 6 apart from them; 12 medium, as the Touch ID mark on the held call. */
  symbol?: SFSymbolName;
  symbolSize?: number;
  /** In a row the card dims whole while busy, so the pill does not dim a second time on its own. */
  inRow?: boolean;
  children: ReactNode;
}

/** The pill every island card answers with. */
export function IslandButton({ kind = 'secondary', symbol, symbolSize = 12, inRow = false, children, className, type = 'button', ...rest }: IslandButtonProps) {
  return (
    <button type={type} className={`${islandButtonClass(kind)} ${inRow ? 'disabled:!opacity-100' : ''} ${className ?? ''}`} {...rest}>
      {symbol !== undefined && <SFSymbol name={symbol} size={symbolSize} weight="medium" />}
      {children}
    </button>
  );
}
