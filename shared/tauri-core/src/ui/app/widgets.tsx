import { X, type LucideIcon } from 'lucide-react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { TabInfo, WidthClass } from '../../core/domain/destinations';

/** Green, amber, red and grey, each always beside a word, since colour alone says nothing to many people. */
export type Tone = 'good' | 'attention' | 'bad' | 'quiet';

const TONE_TEXT: Record<Tone, string> = {
  good: 'text-success',
  attention: 'text-warm',
  bad: 'text-destructive',
  quiet: 'text-muted',
};

const TONE_DOT: Record<Tone, string> = {
  good: 'bg-success',
  attention: 'bg-warm',
  bad: 'bg-destructive',
  quiet: 'bg-faint',
};

export function StatusWord({ tone, children }: { tone: Tone; children: ReactNode }) {
  return (
    <span className={`inline-flex items-center gap-1.5 text-footnote font-medium ${TONE_TEXT[tone]}`}>
      <span aria-hidden className={`size-1.5 rounded-full ${TONE_DOT[tone]}`} />
      {children}
    </span>
  );
}

/** One count at a glance, as the Mac's `StatTile`: the number large, what it counts under it. */
export function StatTile({ value, label, tone = 'quiet', onClick }: { value: number | string; label: string; tone?: Tone; onClick?: () => void }) {
  const body = (
    <>
      <span className={`text-[26px] leading-none font-semibold tabular-nums ${tone === 'quiet' ? 'text-foreground' : TONE_TEXT[tone]}`}>{value}</span>
      <span className="text-footnote text-muted">{label}</span>
    </>
  );
  const frame = 'flex min-w-0 flex-col gap-2 rounded-xl border border-panel-edge bg-card px-4 py-3.5 text-left';
  if (onClick === undefined) return <div className={frame}>{body}</div>;
  return (
    <button type="button" className={`${frame} mx-focus cursor-pointer transition-colors hover:bg-hover`} onClick={onClick}>
      {body}
    </button>
  );
}

/** A titled block of a page, with one optional action on the right of its title. */
export function Section({ title, trailing, children }: { title: string; trailing?: ReactNode; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <div className="flex min-h-7 items-center justify-between gap-3">
        <h2 className="text-headline font-semibold text-foreground">{title}</h2>
        {trailing}
      </div>
      {children}
    </section>
  );
}

/** A list in one rounded panel, rows divided by hairlines. */
export function Panel({ children }: { children: ReactNode }) {
  return <div className="divide-y divide-panel-edge overflow-hidden rounded-xl border border-panel-edge bg-card">{children}</div>;
}

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
        <span className="truncate text-body font-medium text-foreground">{title}</span>
        {caption !== undefined && <span className="truncate text-footnote text-muted">{caption}</span>}
      </span>
      {trailing !== undefined && <span className="flex shrink-0 items-center gap-2">{trailing}</span>}
    </>
  );
  const frame = `flex w-full items-center gap-3 px-3.5 py-2.5 text-left ${chosen ? 'bg-hover' : ''}`;
  if (onClick === undefined) return <div className={frame}>{inner}</div>;
  return (
    <button type="button" className={`${frame} mx-focus cursor-pointer transition-colors hover:bg-hover`} onClick={onClick} aria-pressed={chosen}>
      {inner}
    </button>
  );
}

/** Cards that flow into as many columns as the width holds, each at least 260 wide. */
export function CardGrid({ children }: { children: ReactNode }) {
  return <div className="mx-card-grid">{children}</div>;
}

/** What to do when there is nothing here yet, never only that nothing is here. */
export function EmptyState({ icon: Icon, title, body, action }: { icon: LucideIcon; title: string; body: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-xl border border-dashed border-panel-edge px-6 py-10 text-center">
      <Icon size={22} strokeWidth={1.7} className="text-muted" aria-hidden />
      <p className="text-body font-semibold text-foreground">{title}</p>
      <p className="max-w-[420px] text-footnote text-muted">{body}</p>
      {action !== undefined && <div className="pt-2">{action}</div>}
    </div>
  );
}

/** A read that failed is said, never drawn as an empty page. */
export function ReadFailed({ what, retry }: { what: string; retry: () => void }) {
  return (
    <div role="alert" className="flex items-center justify-between gap-3 rounded-xl border border-panel-edge bg-card px-4 py-3">
      <StatusWord tone="bad">{`Memnox could not read ${what}.`}</StatusWord>
      <button type="button" className="mx-focus cursor-pointer text-footnote font-medium text-primary" onClick={retry}>
        Try again
      </button>
    </div>
  );
}

export function TabBar({ tabs, chosen, choose }: { tabs: readonly TabInfo[]; chosen: string | undefined; choose: (tab: string) => void }) {
  if (tabs.length < 2) return null;
  return (
    <div role="tablist" className="flex shrink-0 gap-1 overflow-x-auto border-b border-panel-edge px-4 [scrollbar-width:none]">
      {tabs.map((tab) => {
        const on = tab.id === chosen;
        return (
          <button
            key={tab.id}
            type="button"
            role="tab"
            aria-selected={on}
            className={`mx-focus relative cursor-pointer px-2.5 py-2.5 text-body whitespace-nowrap transition-colors ${on ? 'font-medium text-foreground' : 'text-muted hover:text-foreground'}`}
            onClick={() => choose(tab.id)}
          >
            {tab.title}
            {on && <span aria-hidden className="absolute inset-x-2 -bottom-px h-0.5 rounded-full bg-primary" />}
          </button>
        );
      })}
    </div>
  );
}

const INSPECTOR_KEY = 'memnox.inspector.width';
const INSPECTOR_MIN = 300;
const INSPECTOR_MAX = 640;
const INSPECTOR_DEFAULT = 380;

function savedWidth(): number {
  const saved = Number(localStorage.getItem(INSPECTOR_KEY));
  return Number.isFinite(saved) && saved >= INSPECTOR_MIN && saved <= INSPECTOR_MAX ? saved : INSPECTOR_DEFAULT;
}

/**
 * The selected item's details. Wide windows keep it beside the page at a width the person drags and the
 * window remembers; narrower ones float it over the page, and the narrowest give it the whole width.
 */
export function Inspector({ title, width, close, expand, children }: { title: string; width: WidthClass; close: () => void; expand?: () => void; children: ReactNode }) {
  const [size, setSize] = useState(savedWidth);
  const dragging = useRef(false);

  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [close]);

  const startDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    dragging.current = true;
    event.currentTarget.setPointerCapture(event.pointerId);
  };
  const drag = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!dragging.current) return;
    const next = Math.min(INSPECTOR_MAX, Math.max(INSPECTOR_MIN, window.innerWidth - event.clientX - 8));
    setSize(next);
  };
  const endDrag = () => {
    if (!dragging.current) return;
    dragging.current = false;
    localStorage.setItem(INSPECTOR_KEY, String(Math.round(size)));
  };

  const beside = width === 'wide';
  const frame = beside
    ? 'relative flex shrink-0 flex-col border-l border-panel-edge bg-background'
    : width === 'medium'
      ? 'fixed inset-y-2 right-2 z-30 flex flex-col rounded-2xl border border-panel-edge bg-background shadow-2xl'
      : 'fixed inset-0 z-30 flex flex-col bg-background';
  return (
    <aside className={frame} style={width === 'wide' || width === 'medium' ? { width: size } : undefined} aria-label={title}>
      {beside && (
        <div
          role="separator"
          aria-orientation="vertical"
          aria-label="Resize the details"
          className="absolute inset-y-0 -left-1 w-2 cursor-col-resize"
          onPointerDown={startDrag}
          onPointerMove={drag}
          onPointerUp={endDrag}
        />
      )}
      <header className="flex h-12 shrink-0 items-center gap-2 border-b border-panel-edge px-4">
        <span className="flex-1 truncate text-headline font-semibold text-foreground">{title}</span>
        {expand !== undefined && (
          <button type="button" className="mx-focus cursor-pointer rounded-md px-2 py-1 text-footnote text-muted hover:bg-hover" onClick={expand}>
            Open full page
          </button>
        )}
        <button type="button" className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover" onClick={close} aria-label="Close the details">
          <X size={15} />
        </button>
      </header>
      <div className="flex-1 overflow-y-auto p-4">{children}</div>
    </aside>
  );
}

/** A section that folds, remembered per name so it opens as it was left. */
export function Fold({ name, title, children }: { name: string; title: string; children: ReactNode }) {
  const key = `memnox.fold.${name}`;
  const [open, setOpen] = useState(() => localStorage.getItem(key) !== 'closed');
  return (
    <details
      open={open}
      onToggle={(event) => {
        const now = (event.currentTarget as HTMLDetailsElement).open;
        setOpen(now);
        localStorage.setItem(key, now ? 'open' : 'closed');
      }}
      className="group"
    >
      <summary className="mx-focus cursor-pointer list-none text-footnote font-semibold text-muted select-none">{title}</summary>
      <div className="pt-2.5">{children}</div>
    </details>
  );
}
