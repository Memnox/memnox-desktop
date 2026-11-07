import type { LucideIcon } from 'lucide-react';
import { useState, type ReactNode } from 'react';
import { Pressable } from './Button';
import { TONE_TEXT, type Tone } from './Badge';
import { PRESS_DIP } from './press';

/** How much room a card keeps inside its edge: none where its rows carry it, 16 for a tile, 20 for a settings card. */
export type CardPad = 'none' | 'regular' | 'roomy';

const CARD_PAD: Record<CardPad, string> = { none: 'overflow-hidden', regular: 'p-4', roomy: 'p-5' };

/**
 * The console's card: radius 12, the panel edge, the card fill. `chosen` draws its edge in the brand blue.
 * `className` lays out what it holds and never repaints the card itself.
 */
export function Card({
  as: Tag = 'div',
  pad = 'regular',
  chosen = false,
  className,
  label,
  children,
}: {
  as?: 'div' | 'section' | 'article' | 'li';
  /** Names the card for a screen reader where its words alone do not. */
  label?: string;
  pad?: CardPad;
  chosen?: boolean;
  className?: string;
  children: ReactNode;
}) {
  return <Tag aria-label={label} className={`rounded-card border bg-card ${chosen ? 'border-primary' : 'border-panel-edge'} ${CARD_PAD[pad]} ${className ?? ''}`}>{children}</Tag>;
}

/**
 * Cards that flow into as many columns as the width holds. `min` is the narrowest a card may be, 260 unless
 * the page passes the Mac's own minimum for it, and `gap` is the space between cards, 12 unless passed.
 */
export function CardGrid({ children, min, gap }: { children: ReactNode; min?: number; gap?: number }) {
  const style = {
    ...(min === undefined ? {} : { gridTemplateColumns: `repeat(auto-fill, minmax(${min}px, 1fr))` }),
    ...(gap === undefined ? {} : { gap: `${gap}px` }),
  };
  return (
    <div className="mx-card-grid" style={style}>
      {children}
    </div>
  );
}

/** `ShellSection`: a 16 medium title, an optional action on its baseline at the right, then 10 to what it holds. */
export function Section({ title, trailing, children }: { title: string; trailing?: ReactNode; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between gap-3">
        <h2 className="text-base font-medium text-foreground">{title}</h2>
        {trailing}
      </div>
      {children}
    </section>
  );
}

/** `ShellPanel`: a list in one rounded panel, rows divided by hairlines. */
export function Panel({ children }: { children: ReactNode }) {
  return <div className="divide-y divide-panel-edge overflow-hidden rounded-card border border-panel-edge bg-card">{children}</div>;
}

/** `ShellRow`: one row of a panel, 16 across and 12 down: something leading, a title over its caption, something trailing; it presses where given `onClick`. */
export function Row({
  leading,
  title,
  caption,
  trailing,
  onClick,
  chosen = false,
}: {
  leading?: ReactNode;
  title: ReactNode;
  caption?: ReactNode;
  trailing?: ReactNode;
  onClick?: () => void;
  chosen?: boolean;
}) {
  const inner = (
    <>
      {leading !== undefined && <span className="shrink-0">{leading}</span>}
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="truncate text-body-sm font-medium text-foreground">{title}</span>
        {caption !== undefined && <span className="truncate text-meta text-muted">{caption}</span>}
      </span>
      {trailing !== undefined && <span className="flex shrink-0 items-center gap-2">{trailing}</span>}
    </>
  );
  const frame = `flex w-full items-center gap-3 px-4 py-3 text-left ${chosen ? 'bg-active' : ''}`;
  if (onClick === undefined) return <div className={frame}>{inner}</div>;
  return (
    <Pressable className={`${frame} mx-focus cursor-pointer hover:bg-hover ${PRESS_DIP}`} onClick={onClick} aria-pressed={chosen}>
      {inner}
    </Pressable>
  );
}

/** One count at a glance, as the console's stat card: what it counts above, the number large under it. */
export function StatTile({ value, label, tone = 'quiet', onClick }: { value: number | string; label: string; tone?: Tone; onClick?: () => void }) {
  const body = (
    <>
      <span className="truncate text-body-sm font-medium text-foreground">{label}</span>
      <span className={`text-2xl leading-none font-semibold tracking-[-0.02em] tabular-nums ${tone === 'quiet' ? 'text-foreground' : TONE_TEXT[tone]}`}>{value}</span>
    </>
  );
  const frame = 'flex min-w-0 flex-col gap-4 rounded-card border border-panel-edge bg-card p-4 text-left';
  if (onClick === undefined) return <div className={frame}>{body}</div>;
  return (
    <Pressable className={`${frame} mx-focus cursor-pointer hover:bg-hover ${PRESS_DIP}`} onClick={onClick}>
      {body}
    </Pressable>
  );
}

/** The empty state's glyph, a touch larger than a row's so it reads as the page's own. */
const EMPTY_ICON = 20;

/** `EmptyState`: what to do when there is nothing here yet, never only that nothing is here, 40 inside a bordered card. */
export function EmptyState({ icon: Icon, title, body, action }: { icon: LucideIcon; title: string; body: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-card border border-panel-edge bg-card p-10 text-center">
      <Icon size={EMPTY_ICON} strokeWidth={1.8} className="text-muted" aria-hidden />
      <p className="text-body-sm font-medium text-foreground">{title}</p>
      <p className="max-w-md text-body-sm leading-relaxed text-muted">{body}</p>
      {action !== undefined && <div className="pt-2">{action}</div>}
    </div>
  );
}

/** Where each fold is remembered, by its name after this. */
const FOLD_KEY_PREFIX = 'memnox.fold.';

/** What a fold left shut remembers; anything else opens it. */
const FOLD_CLOSED = 'closed';
const FOLD_OPEN = 'open';

/** A section that folds, remembered per name so it opens as it was left. */
export function Fold({ name, title, children }: { name: string; title: string; children: ReactNode }) {
  const key = `${FOLD_KEY_PREFIX}${name}`;
  const [open, setOpen] = useState(() => localStorage.getItem(key) !== FOLD_CLOSED);
  return (
    <details
      open={open}
      onToggle={(event) => {
        const now = (event.currentTarget as HTMLDetailsElement).open;
        setOpen(now);
        localStorage.setItem(key, now ? FOLD_OPEN : FOLD_CLOSED);
      }}
      className="group"
    >
      <summary className="mx-focus cursor-pointer list-none text-label font-medium tracking-[0.14em] text-muted uppercase select-none">{title}</summary>
      <div className="pt-2.5">{children}</div>
    </details>
  );
}
