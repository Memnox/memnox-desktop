import { useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import type { SessionCard } from '@memnox/core/wire';
import { CircleX, MessageSquareText, Pin, PinOff, RotateCw } from 'lucide-react';
import {
  cardStatus,
  cardSubtitle,
  cardTitle,
  exchangeDetail,
  historyDays,
  isActive,
  isAnswering,
  mentions,
  type Exchange,
  type HeldCalls,
  type HistoryKeeper,
  type Sessions,
} from '../../core';
import { BrandLogo, IslandButton, LogoMark, PulseDot, SFSymbol, ShimmerText } from '../kit';
import { FilterChip, HeldStrip, Keycap, PRESS_DOWN } from './window-kit';
import './sessions.css';

/**
 * The side panel, the web twin of the Mac's `SideView`: what waits on the person, what works for them
 * now, then every exchange lately by day, each with how it went, and one search over all of it. It sits
 * flush on the left edge as the island's notch turned on its side.
 */

type SideFilter = 'all' | 'needs-you' | 'working' | 'history';

const FILTER_TITLE: Record<SideFilter, string> = { all: 'All', 'needs-you': 'Needs you', working: 'Working', history: 'History' };
/** How long "Clear all?" waits for the second press before it puts itself back. */
const CONFIRM_CLEAR_MS = 3_000;
/** The flare where the panel meets the screen's left edge, and its right side's radius. */
const FLARE = 14;
const RADIUS = 22;

export function SidePanel({
  calls,
  sessions,
  history,
  pinned,
  onPin,
  onOpenSession,
  onAskAgain,
  talkKeys = ['Ctrl', 'Alt', 'Space'],
  now: fixedNow,
}: {
  calls: HeldCalls;
  sessions: Sessions;
  history: HistoryKeeper;
  pinned: boolean;
  onPin: (on: boolean) => void;
  onOpenSession: (card: SessionCard) => void;
  onAskAgain: (question: string) => void;
  talkKeys?: readonly string[];
  now?: number;
}) {
  const held = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state,
  );
  const listed = useSyncExternalStore(
    (changed) => sessions.observe(changed),
    () => sessions.state,
  );
  const kept = useSyncExternalStore(
    (changed) => history.observe(changed),
    () => history.history,
  );
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<SideFilter>('all');
  const [picked, setPicked] = useState<string>();
  const now = fixedNow ?? Date.now();

  const needsYou = held.waiting.entries
    .map((entry) => entry.card)
    .reverse()
    .filter((card) => mentions(card.who, query) || mentions(card.what, query));
  const working = listed.cards.filter((card) => isActive(cardStatus(card))).filter((card) => mentions(cardTitle(card), query) || mentions(card.agentName, query) || mentions(card.repository ?? '', query));
  const days = useMemo(() => historyDays(kept, query, now), [kept, query, now]);
  // The chosen filter, or All once its section has emptied, so an answered call never leaves a blank panel.
  const shown: SideFilter =
    (filter === 'needs-you' && needsYou.length === 0) || (filter === 'working' && working.length === 0) || (filter === 'history' && days.length === 0) ? 'all' : filter;
  const shows = (section: SideFilter) => shown === 'all' || shown === section;

  return (
    <div className="relative h-full w-full overflow-hidden font-sans text-ink">
      <SideShape />
      <div className="relative flex h-full animate-[fade-in_200ms_ease-out_120ms_both] flex-col gap-2.5 px-2.5" style={{ paddingTop: FLARE + 10, paddingBottom: FLARE + 10, paddingRight: 10 }}>
        <SideSearch query={query} onQuery={setQuery} pinned={pinned} onPin={onPin} />
        <div className="flex items-center gap-1.5 px-0.5">
          <FilterChip title={FILTER_TITLE.all} chosen={shown === 'all'} onPress={() => setFilter('all')} />
          {needsYou.length > 0 && <FilterChip title={FILTER_TITLE['needs-you']} count={needsYou.length} chosen={shown === 'needs-you'} onPress={() => setFilter('needs-you')} />}
          {working.length > 0 && <FilterChip title={FILTER_TITLE.working} count={working.length} chosen={shown === 'working'} onPress={() => setFilter('working')} />}
          {days.length > 0 && <FilterChip title={FILTER_TITLE.history} chosen={shown === 'history'} onPress={() => setFilter('history')} />}
        </div>
        <div className="flex min-h-0 flex-1 flex-col gap-3.5 overflow-y-auto pb-2 [scrollbar-width:none]">
          {shows('needs-you') && needsYou.length > 0 && (
            <Section title="Needs you" count={needsYou.length} dot="#FF9F0A">
              {needsYou.map((card) => (
                <HeldStrip key={card.subject} calls={calls} card={card} />
              ))}
            </Section>
          )}
          {shows('working') && working.length > 0 && (
            <Section title="Working now" count={working.length} dot="#30D158">
              {working.map((card) => (
                <WorkingRow key={card.sessionId} card={card} now={now} onOpen={() => onOpenSession(card)} />
              ))}
            </Section>
          )}
          {shows('history') &&
            days.map((day) => (
              <Section key={day.start} title={day.title}>
                {day.exchanges.map((exchange) => (
                  <ExchangeRow key={exchange.id} exchange={exchange} now={now} opened={picked === exchange.id} onOpen={() => setPicked(picked === exchange.id ? undefined : exchange.id)} onAskAgain={() => onAskAgain(exchange.question)} />
                ))}
              </Section>
            ))}
          {shows('history') && days.length === 0 && <SideEmpty query={query} talkKeys={talkKeys} />}
        </div>
        <SideFooter talkKeys={talkKeys} canClear={kept.exchanges.length > 0} onClear={() => history.forget()} />
      </div>
    </div>
  );
}

/**
 * The notch turned on its side: flush with the left edge, flowing into it at top and bottom with a concave
 * curve, rounded toward the work. Drawn in CSS, so it fills whatever height the window has.
 */
function SideShape() {
  const flare = (corner: string) => `radial-gradient(circle at ${corner}, transparent ${FLARE}px, var(--mx-panel) ${FLARE + 0.5}px)`;
  return (
    <div className="pointer-events-none absolute inset-0" aria-hidden>
      <span className="absolute left-0 top-0" style={{ width: FLARE, height: FLARE, background: flare('100% 0') }} />
      <span className="absolute inset-x-0 bg-panel" style={{ top: FLARE, bottom: FLARE, borderRadius: `0 ${RADIUS}px ${RADIUS}px 0` }} />
      <span className="absolute bottom-0 left-0" style={{ width: FLARE, height: FLARE, background: flare('100% 100%') }} />
    </div>
  );
}

/** The search over everything, 36 tall, and the pin that keeps the panel open while the person works. */
function SideSearch({ query, onQuery, pinned, onPin }: { query: string; onQuery: (query: string) => void; pinned: boolean; onPin: (on: boolean) => void }) {
  return (
    <div className="flex items-center gap-2">
      <label className="flex h-9 min-w-0 flex-1 items-center gap-2 rounded-card bg-ink/[0.08] px-3 transition-colors focus-within:bg-ink/[0.12]">
        <span className="grid shrink-0 text-ink-secondary">
          <SFSymbol name="magnifyingglass" size={13} />
        </span>
        <input
          className="min-w-0 flex-1 border-0 bg-transparent text-callout text-ink outline-none placeholder:text-ink-secondary"
          placeholder="Search"
          value={query}
          onChange={(event) => onQuery(event.target.value)}
          onKeyDown={(event) => event.key === 'Escape' && onQuery('')}
        />
        {query !== '' && (
          <button type="button" className={`${PRESS_DOWN} grid shrink-0 text-ink-tertiary`} onClick={() => onQuery('')} aria-label="Clear the search">
            <CircleX size={13} fill="currentColor" stroke="var(--mx-panel)" />
          </button>
        )}
      </label>
      <button
        type="button"
        className={`${PRESS_DOWN} grid size-9 shrink-0 place-items-center rounded-card bg-ink/[0.08] ${pinned ? 'text-primary' : 'text-ink-secondary'}`}
        onClick={() => onPin(!pinned)}
        title={pinned ? 'Let it close when you click elsewhere' : 'Keep it open while you work'}
        aria-pressed={pinned}
      >
        {pinned ? <Pin size={12} strokeWidth={2.25} fill="currentColor" /> : <PinOff size={12} strokeWidth={2.25} />}
      </button>
    </div>
  );
}

/** A section's heading: a 6 dot where it has a colour, the title 12 semibold at half ink, and its count. */
function Section({ title, count, dot, children }: { title: string; count?: number; dot?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col">
      <h3 className="m-0 flex items-center gap-1.5 px-2 pb-1 pt-2 text-footnote font-semibold text-ink-tertiary">
        {dot !== undefined && <span className="size-1.5 rounded-full" style={{ backgroundColor: dot }} />}
        {title}
        {count !== undefined && <span className="tabular">{count}</span>}
      </h3>
      <div className="flex flex-col gap-0.5">{children}</div>
    </section>
  );
}

/** A session working now: its logo, what it is on, and the arrow to its window on hover. */
function WorkingRow({ card, now, onOpen }: { card: SessionCard; now: number; onOpen: () => void }) {
  return (
    <button type="button" className={`${PRESS_DOWN} group flex min-h-11 w-full min-w-0 items-center gap-2.5 rounded-card px-2 py-[7px] text-left hover:bg-ink/[0.06]`} onClick={onOpen} title="Go to this session">
      <BrandLogo agent={card.agent} name={card.agentName} size={26} />
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-body font-semibold text-ink">{cardTitle(card)}</span>
        {card.thinking ? <ShimmerText className="!text-caption !font-normal">{cardSubtitle(card, now)}</ShimmerText> : <span className="truncate text-caption text-muted">{cardSubtitle(card, now)}</span>}
      </span>
      <span className="grid shrink-0 text-ink-secondary opacity-0 transition-opacity group-hover:opacity-100">
        <SFSymbol name="arrow.up.forward" size={11} weight="semibold" />
      </span>
    </button>
  );
}

/** One exchange: the Memnox disc, or a red one if it failed, the question and how it went; a click opens the answer. */
function ExchangeRow({ exchange, now, opened, onOpen, onAskAgain }: { exchange: Exchange; now: number; opened: boolean; onOpen: () => void; onAskAgain: () => void }) {
  const failed = exchange.failure !== undefined;
  const answering = isAnswering(exchange);
  const detail = exchangeDetail(exchange, now);
  return (
    <div className={`group flex flex-col rounded-card ${opened ? 'bg-ink/10' : 'hover:bg-ink/[0.06]'}`}>
      <button type="button" className={`${PRESS_DOWN} flex min-h-11 w-full min-w-0 items-center gap-2.5 px-2 py-[7px] text-left`} onClick={onOpen} aria-expanded={opened}>
        <span className="grid size-[22px] shrink-0 place-items-center rounded-full text-white" style={{ backgroundColor: failed ? 'rgb(255 69 58 / 0.85)' : '#3B82F7' }}>
          {failed ? <span className="text-caption font-bold leading-none">!</span> : <LogoMark size={12} />}
        </span>
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-body font-semibold text-ink">{exchange.question}</span>
          {answering ? (
            <ShimmerText className="!text-caption !font-normal">{detail}</ShimmerText>
          ) : (
            <span className={`truncate text-caption ${failed ? 'text-[#C0213A] dark:text-[#F77C86]' : 'text-muted'}`}>{detail}</span>
          )}
        </span>
        {answering && <PulseDot colour="#3B82F7" size={7} />}
        {failed && <span className="size-[7px] shrink-0 rounded-full bg-red group-hover:hidden" />}
        {failed && (
          <span className="hidden shrink-0 group-hover:inline-flex" onClick={(event) => event.stopPropagation()}>
            <IslandButton className="!px-2.5 !py-1 !text-caption" onClick={onAskAgain}>
              <RotateCw size={11} strokeWidth={2.25} />
              Ask again
            </IslandButton>
          </span>
        )}
      </button>
      {opened && exchange.answer !== '' && <p className="m-0 select-text whitespace-pre-wrap px-2 pb-2.5 pl-[42px] text-body text-ink-primary">{exchange.answer}</p>}
    </div>
  );
}

/** Nothing asked yet, or nothing that mentions the search. */
function SideEmpty({ query, talkKeys }: { query: string; talkKeys: readonly string[] }) {
  const searching = query.trim() !== '';
  return (
    <div className="flex flex-col items-center gap-1.5 px-4 pt-10 text-center">
      <MessageSquareText size={17} className="text-ink-tertiary" />
      <span className="text-callout font-semibold text-ink">{searching ? `Nothing mentions “${query.trim()}”` : 'Nothing asked yet'}</span>
      {!searching && <span className="text-body text-ink-secondary">Press {talkKeys.join(' ')} and ask anything. Every answer stays here, on this computer.</span>}
    </div>
  );
}

/** The keys that ask, and Clear history, which asks "Clear all?" for three seconds first. */
function SideFooter({ talkKeys, canClear, onClear }: { talkKeys: readonly string[]; canClear: boolean; onClear: () => void }) {
  const [confirming, setConfirming] = useState(false);
  useEffect(() => {
    if (!confirming) return;
    const back = setTimeout(() => setConfirming(false), CONFIRM_CLEAR_MS);
    return () => clearTimeout(back);
  }, [confirming]);
  return (
    <div className="flex items-center gap-[3px] p-1.5">
      {talkKeys.map((key) => (
        <Keycap key={key}>{key}</Keycap>
      ))}
      <span className="pl-1.5 text-footnote text-ink-secondary">to ask</span>
      <span className="flex-1" />
      {canClear && (
        <button
          type="button"
          className={`${PRESS_DOWN} text-footnote font-medium ${confirming ? 'text-[#C0213A] dark:text-[#F77C86]' : 'text-ink-secondary hover:text-ink'}`}
          onClick={() => {
            if (!confirming) return setConfirming(true);
            setConfirming(false);
            onClear();
          }}
        >
          {confirming ? 'Clear all?' : 'Clear history'}
        </button>
      )}
    </div>
  );
}
