import { ExternalLink, RotateCw, TriangleAlert, X, type LucideIcon } from 'lucide-react';
import { createPortal } from 'react-dom';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { shellLayout, type WidthClass } from '../../core/domain/destinations';
import { useInspectorHost } from './inspector-host';
import { scopeLabel, SCOPE_WORDS, type ScopeKind } from '../../core/domain/scope-lines';

/** Green, amber, red and grey, each always beside a word, since colour alone says nothing to many people. */
export type Tone = 'good' | 'attention' | 'bad' | 'quiet';

const TONE_TEXT: Record<Tone, string> = {
  good: 'text-success',
  attention: 'text-warm',
  bad: 'text-destructive',
  quiet: 'text-muted',
};

/** The console's pill tints: its own colour at 12 to 14 percent under the word, grey on the muted fill. */
const TONE_PILL: Record<Tone, string> = {
  good: 'text-success bg-[color-mix(in_oklab,var(--mx-success)_12%,transparent)]',
  attention: 'text-warm bg-[color-mix(in_oklab,var(--mx-warm)_14%,transparent)]',
  bad: 'text-destructive bg-[color-mix(in_oklab,var(--mx-destructive)_12%,transparent)]',
  quiet: 'text-muted bg-hover',
};

/** A state worn as the console's pill, its colour always beside the word. */
export function StatusWord({ tone, children }: { tone: Tone; children: ReactNode }) {
  return <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-meta font-medium whitespace-nowrap ${TONE_PILL[tone]}`}>{children}</span>;
}

/** Whose an item is, grey and in a word, the same chip on every rule, server, skill, profile, project and memory item. */
export function ScopeChip({ scope }: { scope: ScopeKind }) {
  return (
    <span aria-label={scopeLabel(scope)} title={scopeLabel(scope)} className="inline-flex shrink-0 items-center rounded-full border border-panel-edge px-2 py-px text-label font-medium text-muted">
      {SCOPE_WORDS[scope]}
    </span>
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
  const frame = 'flex min-w-0 flex-col gap-4 rounded-xl border border-panel-edge bg-card p-4 text-left';
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
        <h2 className="text-base font-medium text-foreground">{title}</h2>
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
        <span className="truncate text-body-sm font-medium text-foreground">{title}</span>
        {caption !== undefined && <span className="truncate text-meta text-muted">{caption}</span>}
      </span>
      {trailing !== undefined && <span className="flex shrink-0 items-center gap-2">{trailing}</span>}
    </>
  );
  const frame = `flex w-full items-center gap-3 px-4 py-3 text-left ${chosen ? 'bg-active' : ''}`;
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
    <div className="flex flex-col items-center gap-2 rounded-xl border border-panel-edge bg-card p-10 text-center">
      <Icon size={20} strokeWidth={1.8} className="text-muted" aria-hidden />
      <p className="text-body-sm font-medium text-foreground">{title}</p>
      <p className="max-w-md text-body-sm leading-relaxed text-muted">{body}</p>
      {action !== undefined && <div className="pt-2">{action}</div>}
    </div>
  );
}

/** A read that failed is said, never drawn as an empty page. */
export function ReadFailed({ what, retry }: { what: string; retry: () => void }) {
  return (
    <div role="alert" className="flex flex-wrap items-center gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-body-sm">
      <TriangleAlert size={16} className="shrink-0 text-destructive" aria-hidden />
      <p className="min-w-0 flex-1 font-medium text-foreground">{`Memnox could not read ${what}.`}</p>
      <button
        type="button"
        className="mx-focus inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg border border-panel-edge bg-background px-3.5 font-medium text-foreground hover:bg-hover"
        onClick={retry}
      >
        <RotateCw size={14} aria-hidden />
        Try again
      </button>
    </div>
  );
}

const INSPECTOR_KEY = 'memnox.inspector.width';
const INSPECTOR_MIN = 300;
const INSPECTOR_MAX = 640;
const INSPECTOR_DEFAULT = 380;
const POP_OUT = 'Open in its own window';

function savedWidth(): number {
  const saved = Number(localStorage.getItem(INSPECTOR_KEY));
  return Number.isFinite(saved) && saved >= INSPECTOR_MIN && saved <= INSPECTOR_MAX ? saved : INSPECTOR_DEFAULT;
}

/**
 * The selected item's details. Wide windows keep it beside the page at a width the person drags and the
 * window remembers; narrower ones float it over the page, and the narrowest give it the whole width.
 */
export function Inspector({
  title,
  width,
  close,
  expand,
  item,
  children,
}: {
  title: string;
  width: WidthClass;
  close: () => void;
  expand?: () => void;
  /** The item's id on its page, which lets the details pop out into a window of their own. */
  item?: string;
  children: ReactNode;
}) {
  const [size, setSize] = useState(savedWidth);
  const dragging = useRef(false);
  const host = useInspectorHost();
  const shut = host.alone ? host.close : close;

  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') shut();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [shut]);

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

  const placed = host.alone ? 'full' : shellLayout(width, false).inspector;
  const beside = placed === 'beside';
  const frame = beside
    ? 'relative flex shrink-0 flex-col border-l border-panel-edge bg-card'
    : placed === 'drawer'
      ? 'fixed inset-y-2 right-2 z-30 flex flex-col rounded-xl border border-panel-edge bg-card shadow-[0_24px_60px_rgb(0_0_0/0.18)]'
      : 'fixed inset-0 z-30 flex flex-col bg-card';
  const popOut = host.popOut;
  const pane = (
    <aside className={frame} style={placed === 'full' ? undefined : { width: size }} aria-label={title}>
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
        <span className="flex-1 truncate text-body-sm font-semibold text-foreground">{title}</span>
        {expand !== undefined && !host.alone && (
          <button type="button" className="mx-focus h-8 cursor-pointer rounded-lg px-2.5 text-meta font-medium text-muted hover:bg-hover hover:text-foreground" onClick={expand}>
            Open full page
          </button>
        )}
        {popOut !== undefined && item !== undefined && !host.alone && (
          <button
            type="button"
            className="mx-focus grid size-8 cursor-pointer place-items-center rounded-lg text-muted hover:bg-hover hover:text-foreground"
            onClick={() => {
              popOut(item, title);
              close();
            }}
            aria-label={POP_OUT}
            title={POP_OUT}
          >
            <ExternalLink size={14} />
          </button>
        )}
        <button type="button" className="mx-focus grid size-8 cursor-pointer place-items-center rounded-lg text-muted hover:bg-hover hover:text-foreground" onClick={shut} aria-label="Close the details">
          <X size={15} />
        </button>
      </header>
      <div className="flex-1 overflow-y-auto p-5">{children}</div>
    </aside>
  );
  // Alone, the page under it is hidden, so the details are drawn over the whole window from outside it.
  return host.alone ? createPortal(pane, document.body) : pane;
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
      <summary className="mx-focus cursor-pointer list-none text-label font-medium tracking-[0.14em] text-muted uppercase select-none">{title}</summary>
      <div className="pt-2.5">{children}</div>
    </details>
  );
}
