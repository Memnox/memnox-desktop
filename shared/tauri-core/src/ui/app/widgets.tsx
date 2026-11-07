import { ExternalLink, X } from 'lucide-react';
import { createPortal } from 'react-dom';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { shellLayout, type WidthClass } from '../../core/domain/destinations';
import { useInspectorHost } from './inspector-host';
import { Button, IconButton } from '../kit';
import { InspectorLines } from '../../core/domain/shell-lines';
import { scopeLabel, SCOPE_WORDS, type ScopeKind } from '../../core/domain/scope-lines';

/** Whose an item is, grey and in a word, the same chip on every rule, server, skill, profile, project and memory item. */
export function ScopeChip({ scope }: { scope: ScopeKind }) {
  return (
    <span aria-label={scopeLabel(scope)} title={scopeLabel(scope)} className="inline-flex shrink-0 items-center rounded-full border border-panel-edge px-2 py-px text-label font-medium text-muted">
      {SCOPE_WORDS[scope]}
    </span>
  );
}

/** Where the dragged width is remembered between openings. */
const INSPECTOR_KEY = 'memnox.inspector.width';

/** The details' width beside the page: never too narrow for a row of buttons, never more than half a wide window. */
const INSPECTOR_WIDTH = { least: 300, most: 640, first: 380 } as const;

/** The room kept between the dragged edge and the window's own, so the handle never sits on the window frame. */
const INSPECTOR_EDGE = 8;

function savedWidth(): number {
  const saved = Number(localStorage.getItem(INSPECTOR_KEY));
  return Number.isFinite(saved) && saved >= INSPECTOR_WIDTH.least && saved <= INSPECTOR_WIDTH.most ? saved : INSPECTOR_WIDTH.first;
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
    const next = Math.min(INSPECTOR_WIDTH.most, Math.max(INSPECTOR_WIDTH.least, window.innerWidth - event.clientX - INSPECTOR_EDGE));
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
      ? 'fixed inset-y-2 right-2 z-30 flex flex-col rounded-card border border-panel-edge bg-card shadow-lift'
      : 'fixed inset-0 z-30 flex flex-col bg-card';
  const popOut = host.popOut;
  const pane = (
    <aside className={frame} style={placed === 'full' ? undefined : { width: size }} aria-label={title}>
      {beside && (
        <div
          role="separator"
          aria-orientation="vertical"
          aria-label={InspectorLines.resize}
          className="absolute inset-y-0 -left-1 w-2 cursor-col-resize"
          onPointerDown={startDrag}
          onPointerMove={drag}
          onPointerUp={endDrag}
        />
      )}
      {/* The Mac's bar is 4 short of the shell's 56, so the details' rule sits under the page's. */}
      <header className="flex h-13 shrink-0 items-center gap-2 border-b border-panel-edge px-4">
        <span className="flex-1 truncate text-body-sm font-semibold text-foreground">{title}</span>
        {expand !== undefined && !host.alone && (
          <Button kind="quiet" onClick={expand}>
            {InspectorLines.expand}
          </Button>
        )}
        {popOut !== undefined && item !== undefined && !host.alone && (
          <IconButton
            icon={ExternalLink}
            label={InspectorLines.popOut}
            onClick={() => {
              popOut(item, title);
              close();
            }}
          />
        )}
        <IconButton icon={X} label={InspectorLines.close} onClick={shut} />
      </header>
      <div className="flex-1 overflow-y-auto p-5">{children}</div>
    </aside>
  );
  // Alone, the page under it is hidden, so the details are drawn over the whole window from outside it.
  return host.alone ? createPortal(pane, document.body) : pane;
}
