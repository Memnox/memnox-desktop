import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { SessionView } from '@memnox/core/wire';
import { readable, repositoryName, shortPath, statusLabel, statusTint, viewContext, viewPlace, viewStatus, type Sessions } from '../../core';
import { BrandLogo, SFSymbol } from '../kit';
import { StepRow } from './LiveSession';
import { CardButton, CardHeader, LiveSection } from './window-kit';
import { islandWindow } from '../adapters/tauri-island-window';
import { WALL } from './session-metrics';
import './sessions.css';
import { LiveSessionLines } from '../../core/domain/island-lines';

/**
 * The card wall, the web twin of the Mac's `CardWall` of `SessionPopupView`s: every session lately as its
 * own card, together, laid in columns 440 wide with each next card in the shortest column, read again
 * every two seconds while it is up.
 */

/** As many cards as the wall shows, the most recently active first. */
const SHOWN_CARDS = 8;
const { cardWidth: CARD_WIDTH, gap: GAP } = WALL;
const REFRESH_MS = 2_000;
/** Each card arrives this long after the one before it. */
const STAGGER_MS = 90;
/** Up a minute, or fifteen seconds after the pointer leaves, and never while it is over a card. */
const STAY_MS = 60_000;
const AFTER_LEAVE_MS = 15_000;
/** Cards grow in and scroll, so where they are is told again this often as well as after each change. */
const BOXES_EVERY_MS = 250;

/**
 * Tells Rust where the cards are, so a click between them lands on the app underneath, as each card on
 * the Mac is a panel of its own.
 */
function useCardBoxes(root: React.RefObject<HTMLDivElement | null>) {
  const last = useRef('');
  const report = () => {
    const cards = root.current?.querySelectorAll<HTMLElement>('[data-wall-card]') ?? [];
    const boxes = [...cards].map((card) => {
      const box = card.getBoundingClientRect();
      return { x: Math.floor(box.x), y: Math.floor(box.y), width: Math.ceil(box.width), height: Math.ceil(box.height) };
    });
    const key = JSON.stringify(boxes);
    if (key === last.current) return;
    last.current = key;
    islandWindow.setHitAreas(boxes);
  };
  useLayoutEffect(report);
  useEffect(() => {
    const every = setInterval(report, BOXES_EVERY_MS);
    return () => clearInterval(every);
  }, []);
}

export function Board({ sessions, title, onWatch, onClose, initial }: { sessions: Sessions; title: string; onWatch: (sessionId: string) => void; onClose: () => void; initial?: readonly SessionView[] }) {
  const [views, setViews] = useState<readonly SessionView[]>(initial ?? []);
  const [closed, setClosed] = useState<ReadonlySet<string>>(new Set());
  const [hovered, setHovered] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useCardBoxes(root);
  // The window lets the pointer through between cards, so Rust says when it left the last one.
  useEffect(() => islandWindow.onPointer((over) => !over && setHovered(false)), []);
  const [columns, setColumns] = useState(Math.max(1, Math.floor((window.innerWidth + GAP) / (CARD_WIDTH + GAP))));

  useEffect(() => {
    const resized = () => setColumns(Math.max(1, Math.floor((window.innerWidth + GAP) / (CARD_WIDTH + GAP))));
    window.addEventListener('resize', resized);
    return () => window.removeEventListener('resize', resized);
  }, []);

  useEffect(() => {
    if (initial !== undefined) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const read = async () => {
      const cards = (await sessions.list()).slice(0, SHOWN_CARDS);
      const fresh = (await Promise.all(cards.map((card) => sessions.view(card.sessionId)))).filter((view): view is SessionView => view !== undefined);
      if (stopped) return;
      setViews(fresh);
      timer = setTimeout(() => void read(), REFRESH_MS);
    };
    void read();
    return () => {
      stopped = true;
      if (timer !== undefined) clearTimeout(timer);
    };
  }, [sessions, initial]);

  // It goes on its own after a minute, sooner once the pointer has left, never while it is over a card.
  useEffect(() => {
    if (hovered || initial !== undefined) return;
    const leave = setTimeout(onClose, closed.size === 0 && views.length === 0 ? STAY_MS : AFTER_LEAVE_MS);
    return () => clearTimeout(leave);
  }, [hovered, onClose, initial, closed.size, views.length]);

  useEffect(() => {
    const pressed = (event: KeyboardEvent) => event.key === 'Escape' && onClose();
    window.addEventListener('keydown', pressed);
    return () => window.removeEventListener('keydown', pressed);
  }, [onClose]);

  const shown = views.filter((view) => !closed.has(view.sessionId));
  useEffect(() => {
    if (views.length > 0 && shown.length === 0) onClose();
  }, [views.length, shown.length, onClose]);

  // Each next card goes into the shortest column, by an estimate of its height, as the Mac's masonry lays them.
  const laid: SessionView[][] = Array.from({ length: columns }, () => []);
  const heights = new Array<number>(columns).fill(0);
  for (const view of shown) {
    const column = heights.indexOf(Math.min(...heights));
    laid[column]?.push(view);
    heights[column] = (heights[column] ?? 0) + estimate(view);
  }
  let order = 0;
  return (
    <div ref={root} className="flex h-screen w-screen items-start gap-4 overflow-y-auto p-10 font-sans [scrollbar-width:none]" aria-label={title}>
      {laid.map((column, at) => (
        <div key={at} className="flex shrink-0 flex-col gap-4" style={{ width: CARD_WIDTH }}>
          {column.map((view) => (
            <div key={view.sessionId} data-wall-card onPointerEnter={() => setHovered(true)} onPointerLeave={() => setHovered(false)}>
              <SessionPopup view={view} order={order++} onWatch={() => onWatch(view.sessionId)} onClose={() => setClosed(new Set([...closed, view.sessionId]))} />
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

/** A card's rough parts: its frame, up to three steps and three files at a row each, and the last thing said. */
const ESTIMATE = { frame: 300, rowsShown: 3, row: 20, lastSaid: 60 } as const;

/** A rough height, enough to lay each next card in the shortest column. */
function estimate(view: SessionView): number {
  const rows = Math.min(ESTIMATE.rowsShown, view.steps.length) + Math.min(ESTIMATE.rowsShown, view.files.length);
  return ESTIMATE.frame + rows * ESTIMATE.row + (view.lastSaid === undefined ? 0 : ESTIMATE.lastSaid);
}

/**
 * `SessionPopupView`: the agent, where it runs and how it stands; what it was asked; what it is doing now;
 * where the work stands; its latest steps and the files it changed; and Watch live.
 */
export function SessionPopup({ view, order, onWatch, onClose, now = Date.now() }: { view: SessionView; order: number; onWatch: () => void; onClose: () => void; now?: number }) {
  const status = viewStatus(view);
  const colour = statusTint(status);
  const task = readable(view.task);
  const lastAsk = readable(view.lastAsk);
  const context = viewContext(view, now);
  const latest = view.steps[view.steps.length - 1];
  const line = view.paused !== undefined ? LiveSessionLines.paused(view.paused) : view.thinking ? LiveSessionLines.thinking : latest?.text;
  const conversation = (view.conversation ?? []).slice(-2);
  return (
    <article
      className="motion-arrive group flex animate-[float-in_550ms_cubic-bezier(0.34,1.45,0.64,1)_both] flex-col gap-3 rounded-session-card border border-ink/[0.07] bg-(--mx-page) p-5 text-foreground shadow-session-card transition-colors duration-[250ms] ease-out hover:border-ink/16"
      style={{ animationDelay: `${order * STAGGER_MS}ms`, transformOrigin: 'top left' }}
    >
      <CardHeader
        mark={<BrandLogo agent={view.agent} name={view.agentName} size={28} />}
        title={view.agentName}
        subtitle={viewPlace(view) ?? repositoryName(view.repository)}
        accessory={
          <span className="inline-flex shrink-0 items-center gap-1.5 text-caption font-medium" style={{ color: colour }}>
            <span className="size-session-dot rounded-full" style={{ backgroundColor: colour }} />
            {statusLabel(status)}
          </span>
        }
        onClose={onClose}
      />
      <LiveSection title={LiveSessionLines.about}>
        <div className="flex flex-col gap-1.5">
          {task !== undefined ? <p className="m-0 line-clamp-3 text-callout font-medium text-foreground/[0.92]">{task}</p> : <p className="m-0 text-callout text-muted">{LiveSessionLines.noRequest}</p>}
          {lastAsk !== undefined && lastAsk !== task && <p className="m-0 line-clamp-2 text-footnote text-foreground/[0.62]">{LiveSessionLines.latestAsk(lastAsk)}</p>}
          {context !== undefined && <p className="m-0 line-clamp-2 text-caption text-muted">{context}</p>}
        </div>
      </LiveSection>
      {line !== undefined && (
        <div className="flex items-center gap-2 rounded-island border border-ink/[0.035] bg-(--mx-section) px-3.5 py-session-now-y">
          <span className="grid shrink-0 text-primary">
            <SFSymbol name={view.thinking ? 'sparkles' : 'arrow.right.circle'} size={13} />
          </span>
          <span className="truncate text-body font-medium">{line}</span>
        </div>
      )}
      {view.lastSaid !== undefined ? (
        <LiveSection title={LiveSessionLines.whereItStands}>
          <p className="m-0 line-clamp-4 text-callout text-foreground/[0.92]">{view.lastSaid}</p>
        </LiveSection>
      ) : (
        conversation.length > 0 && (
          <LiveSection title="Conversation">
            <div className="flex flex-col gap-1.5">
              {conversation.map((each, index) =>
                each.who === 'person' ? (
                  <span key={index} className="ml-session-bubble-indent line-clamp-3 self-end rounded-card bg-primary/[0.32] px-session-bubble-x py-session-bubble-y text-body">
                    {each.text}
                  </span>
                ) : (
                  <span key={index} className={`line-clamp-3 pr-10 ${each.who === 'tool' ? 'font-mono text-caption text-muted' : 'text-body text-foreground/[0.92]'}`}>
                    {each.text}
                  </span>
                ),
              )}
            </div>
          </LiveSection>
        )
      )}
      {view.steps.length > 0 && (
        <LiveSection title="Latest steps">
          <div className="flex flex-col gap-session-step">
            {view.steps.slice(-3).map((step, index) => (
              <StepRow key={index} step={step} now={now} />
            ))}
          </div>
        </LiveSection>
      )}
      {view.files.length > 0 && (
        <LiveSection title="Changed">
          <div className="flex flex-col gap-1 pt-0.5">
            {view.files.slice(0, 3).map((file) => (
              <div key={file.path} className="flex min-w-0 items-center gap-2" title={file.path}>
                <span className="min-w-0 flex-1 truncate font-mono text-footnote text-foreground/90" style={{ direction: 'rtl', textAlign: 'left' }}>
                  <bdi>{shortPath(file.path)}</bdi>
                </span>
                {file.added !== undefined && file.added > 0 && <span className="font-mono text-session-code font-medium text-success">+{file.added}</span>}
                {file.removed !== undefined && file.removed > 0 && (
                  <span className="font-mono text-session-code font-medium text-destructive">
                    {'−'}
                    {file.removed}
                  </span>
                )}
              </div>
            ))}
          </div>
        </LiveSection>
      )}
      <div className="flex items-center gap-2">
        <span className="flex-1" />
        <CardButton title="Watch live" symbol="play.circle" primary onPress={onWatch} />
      </div>
    </article>
  );
}
