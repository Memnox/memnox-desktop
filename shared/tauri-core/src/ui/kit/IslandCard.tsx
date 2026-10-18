import type { CSSProperties, HTMLAttributes, ReactNode } from 'react';

/** The status colours a card's rim takes, at the opacity each screen gives them. */
export const VEIL = {
  /** A held call or an agent's question waiting. */
  waiting: 'rgb(255 159 10 / 0.42)',
  /** A held call settled elsewhere. */
  settled: 'rgb(48 209 88 / 0.42)',
  finished: 'rgb(48 209 88 / 0.5)',
  empty: 'rgb(99 102 241 / 0.25)',
  answering: 'rgb(59 130 247 / 0.22)',
  draft: 'rgb(59 130 247 / 0.38)',
} as const;

/** A colour given as hex at this opacity, for a veil in an agent's or a rule's own colour. */
export function veilOf(hex: string, opacity: number): string {
  const value = Number.parseInt(hex.replace('#', ''), 16);
  return `rgb(${(value >> 16) & 255} ${(value >> 8) & 255} ${value & 255} / ${opacity})`;
}

/**
 * The flat card every island screen draws on: #141518, radius 16, no blur and no shadow, and a 1 px rim
 * that is white 4% at rest or a status colour as its veil, fading over 0.4 s when that changes.
 */
export function IslandCard({
  veil,
  className,
  style,
  children,
  ...rest
}: { veil?: string; children: ReactNode } & HTMLAttributes<HTMLDivElement>) {
  const rim: CSSProperties = veil === undefined ? {} : { borderColor: veil };
  return (
    <div
      className={`rounded-island border border-white/[0.04] bg-island-card transition-[border-color] duration-[400ms] ease-in-out ${className ?? ''}`}
      style={{ ...rim, ...style }}
      {...rest}
    >
      {children}
    </div>
  );
}
