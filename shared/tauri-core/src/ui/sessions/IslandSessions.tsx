import { useEffect, useState } from 'react';
import type { SessionCard, SessionView, SessionViewStep } from '@memnox/core/wire';
import {
  agentColour,
  ago,
  badgeLabel,
  cardStatus,
  cardSubtitle,
  cardTitle,
  currentAsk,
  detailPlace,
  fileName,
  folderOf,
  isActive,
  meaningful,
  onlyNetwork,
  stepLine,
  totals,
  viewStatus,
} from '../../core';
import { IslandCard, MiddleCut, PRESSABLE, PulseDot, SFSymbol, ShimmerText, veilOf } from '../kit';
import { Counts, MiniSpinner, SessionLogo, StatusBadge, StepIcon } from './parts';
import './sessions.css';

/**
 * The open island's session screens, each the web twin of one Swift view in `Island/IslandOverview.swift`
 * and `Island/IslandSessionDetail.swift`. Each fills the content inset: 36 from the top, 10 elsewhere.
 */

const CONTENT_INSET = 'absolute inset-x-2.5 bottom-2.5 top-9';

/** The rim in amber while a call waits on you, and in the agent's own colour while it works. */
const HELD_VEIL = 'rgb(255 159 10 / 0.7)';
const WORKING_VEIL_OPACITY = 0.45;
const THINKING_VEIL_OPACITY = 0.3;
/** As many rows as the list card holds at the overview's height. */
const LISTED_SESSIONS = 4;
/** Two lines of what it did fit under the ask without pushing past the island's height. */
const LISTED_STEPS = 2;
/** As many files as fit under the totals, with the line that counts the rest. */
const SHOWN_FILES = 5;
const SHOWN_ROLL = 3;

/** The clock the screens read "ago" against, ticking so a line that says just now moves on. */
function useNow(everyMs = 15_000): number {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), everyMs);
    return () => clearInterval(tick);
  }, [everyMs]);
  return now;
}

/**
 * `IslandOverview`: the session in focus on the left with what it is doing, the rest as rows on the right.
 * Hovering a row focuses it; clicking the focus card opens it up close; clicking a row opens its window.
 */
export function Overview({
  cards,
  focusId,
  focused,
  onFocus,
  onDetail,
  onOpen,
}: {
  cards: readonly SessionCard[];
  focusId: string | undefined;
  focused: SessionView | undefined;
  onFocus: (sessionId: string) => void;
  onDetail: () => void;
  onOpen: (card: SessionCard) => void;
}) {
  const now = useNow();
  const card = cards.find((each) => each.sessionId === focusId) ?? cards[0];
  const veil =
    card === undefined
      ? undefined
      : (focused?.waitingOnYou ?? 0) > 0
        ? HELD_VEIL
        : isActive(cardStatus(card))
          ? veilOf(agentColour(card.agent), WORKING_VEIL_OPACITY)
          : undefined;
  // Flipped on just after the overview opens, so the rows arrive one after another.
  const [revealed, setRevealed] = useState(false);
  useEffect(() => {
    const frame = requestAnimationFrame(() => setRevealed(true));
    return () => cancelAnimationFrame(frame);
  }, []);
  return (
    <div className={`${CONTENT_INSET} flex gap-2.5`}>
      <IslandCard veil={veil} className="w-[280px] shrink-0 cursor-pointer" onClick={onDetail} title="See what it is changing" role="button" aria-label="See what it is changing">
        {card !== undefined && (
          <div className="flex h-full min-w-0 flex-col justify-center gap-0.5 pl-[88px] pr-3.5">
            <div className="flex min-w-0 items-center gap-[7px]">
              <span className="size-2 shrink-0 rounded-full" style={{ backgroundColor: agentColour(card.agent) }} />
              <span className="truncate text-body font-semibold text-white">{cardTitle(card)}</span>
            </div>
            <span className="truncate pl-[15px] text-caption text-white/50">{cardSubtitle(card, now)}</span>
            <StepRoll steps={meaningful(focused?.sessionId === card.sessionId ? focused.steps : [])} thinking={card.thinking} />
          </div>
        )}
      </IslandCard>
      <IslandCard className="min-w-0 flex-1">
        <div className="flex h-full flex-col gap-0.5 p-2">
          {cards.slice(0, LISTED_SESSIONS).map((each, index) => (
            <div
              key={each.sessionId}
              className="transition-[opacity,translate] duration-[440ms] ease-[cubic-bezier(0.3,1.2,0.6,1)]"
              style={{ opacity: revealed ? 1 : 0, translate: revealed ? '0 0' : '0 6px', transitionDelay: `${220 + index * 35}ms` }}
            >
              <SessionRow card={each} focused={each.sessionId === card?.sessionId} now={now} onHover={() => onFocus(each.sessionId)} onOpen={() => onOpen(each)} />
            </div>
          ))}
        </div>
      </IslandCard>
    </div>
  );
}

/**
 * `IslandStepRoll`: the last three things a session did, oldest at the top, the newest bright and
 * shimmering while it thinks, rolling up as more arrive under a fade at the top.
 */
export function StepRoll({ steps, thinking }: { steps: readonly SessionViewStep[]; thinking: boolean }) {
  const shown = steps.slice(-SHOWN_ROLL);
  return (
    <div
      className="flex h-[84px] flex-col justify-end overflow-hidden"
      style={{ maskImage: 'linear-gradient(to bottom, transparent 0%, #000 28%, #000 100%)', WebkitMaskImage: 'linear-gradient(to bottom, transparent 0%, #000 28%, #000 100%)' }}
    >
      {shown.map((step, index) => {
        const current = index === shown.length - 1;
        const line = stepLine(step);
        return (
          <div key={`${step.at}-${step.text}`} className="flex h-[26px] min-w-0 shrink-0 animate-[step-in_450ms_cubic-bezier(0.3,0.9,0.3,1)_both] items-center gap-[9px]">
            <StepIcon step={step} current={current} />
            <span className="flex min-w-0 flex-1">
              {current && thinking ? (
                <ShimmerText>{line}</ShimmerText>
              ) : (
                <MiddleCut text={line} className={current ? 'text-body font-medium text-island-soft' : 'text-footnote text-quiet'} />
              )}
            </span>
          </div>
        );
      })}
      {shown.length === 0 && <span className="flex h-[26px] shrink-0 items-center text-footnote text-quiet">{thinking ? 'Thinking' : 'Nothing done yet'}</span>}
    </div>
  );
}

/**
 * `IslandSessionRow`: the logo, the title and subtitle, and on the right an arrow when focused or a
 * breathing sky dot while it works. Hover focuses it on the left; a click opens its window.
 */
export function SessionRow({ card, focused, now, onHover, onOpen }: { card: SessionCard; focused: boolean; now: number; onHover: () => void; onOpen: () => void }) {
  const active = isActive(cardStatus(card));
  return (
    <button
      type="button"
      className={`${PRESSABLE} flex h-[30px] w-full min-w-0 items-center gap-2.5 rounded-[11px] px-2 text-left transition-colors duration-150 ease-out ${focused ? 'bg-white/[0.08]' : 'bg-transparent'}`}
      onPointerEnter={onHover}
      onFocus={onHover}
      onClick={onOpen}
      title="Go to this session"
    >
      <SessionLogo agent={card.agent} name={card.agentName} size={22} />
      <span className="flex min-w-0 flex-1 flex-col gap-px">
        <span className={`truncate text-footnote leading-[14px] font-semibold ${focused ? 'text-white' : 'text-white/85'}`}>{cardTitle(card)}</span>
        <span className="truncate text-caption leading-[13px] text-white/40">{cardSubtitle(card, now)}</span>
      </span>
      {focused ? (
        <span className="grid shrink-0 animate-[arrow-in_200ms_ease-out_both] text-white/60">
          <SFSymbol name="arrow.up.forward" size={11} weight="semibold" />
        </span>
      ) : (
        active && <PulseDot colour="#8CC8FF" size={7} />
      )}
    </button>
  );
}

/**
 * `IslandSessionDetail`: who and where with how it stands, what it was asked and what it did last on the
 * left; the files it changed on the right, which open the live window and its diffs.
 */
export function SessionDetail({ session, onOpen, onWatch }: { session: SessionView; onOpen: () => void; onWatch: () => void }) {
  const now = useNow();
  const status = viewStatus(session);
  const place = detailPlace(session);
  const asked = currentAsk(session);
  const steps = meaningful(session.steps).slice(-LISTED_STEPS).reverse();
  return (
    <div className={`${CONTENT_INSET} flex gap-2.5`}>
      <IslandCard veil={session.thinking ? veilOf(agentColour(session.agent), THINKING_VEIL_OPACITY) : undefined} className="w-[260px] shrink-0">
        <div className="flex h-full min-w-0 flex-col gap-2.5 p-3.5">
          <div className="flex min-w-0 items-center gap-2">
            <SessionLogo agent={session.agent} name={session.agentName} size={30} />
            <div className="flex min-w-0 flex-1 flex-col gap-[3px]">
              <span className="truncate text-callout font-semibold text-white">{session.agentName}</span>
              <span className="flex min-w-0 items-center gap-1.5">
                <StatusBadge status={status} label={badgeLabel(session, now)} />
                {place !== undefined && (
                  <span className="flex min-w-0 flex-1">
                    <MiddleCut text={place} className="text-caption text-white/50" />
                  </span>
                )}
              </span>
            </div>
            <button
              type="button"
              className={`${PRESSABLE} grid size-[26px] shrink-0 place-items-center rounded-full bg-white/[0.08] text-white`}
              onClick={onOpen}
              title={session.runningIn === undefined ? 'Open this session' : `Open this session in ${session.runningIn}`}
              aria-label="Open this session"
            >
              <SFSymbol name="arrow.up.forward" size={11} weight="semibold" />
            </button>
          </div>
          {asked !== undefined && (
            <div className="flex min-w-0 flex-col gap-0.5">
              <span className={`text-micro font-semibold uppercase tracking-[0.6px] ${asked.followUp ? 'text-island-sky' : 'text-white/40'}`}>{asked.followUp ? 'Follow-up' : 'Asked'}</span>
              <span className="line-clamp-2 text-footnote text-island-soft" title={asked.words}>
                {asked.words}
              </span>
            </div>
          )}
          {steps.length > 0 && (
            <div className="flex min-w-0 flex-col gap-[7px]">
              {steps.map((step, index) => (
                <StepLine key={`${step.at}-${step.text}`} step={step} latest={index === 0} working={index === 0 && session.thinking} now={now} />
              ))}
            </div>
          )}
        </div>
      </IslandCard>
      <FilesPanel session={session} onWatch={onWatch} />
    </div>
  );
}

/** `IslandStepLine`: one thing the session did, with how long ago on the right; a spinner while it is still at work. */
function StepLine({ step, latest, working, now }: { step: SessionViewStep; latest: boolean; working: boolean; now: number }) {
  const since = ago(step.at, now);
  return (
    <div className="flex min-w-0 items-center gap-2" title={step.text}>
      {working ? (
        <span className="grid w-3.5 shrink-0 place-items-center">
          <MiniSpinner />
        </span>
      ) : (
        <StepIcon step={step} current={latest} />
      )}
      <span className="flex min-w-0 flex-1">
        <MiddleCut text={stepLine(step)} className={`text-footnote ${latest ? 'font-medium text-white' : 'text-island-soft'}`} />
      </span>
      {since !== undefined && <span className="tabular shrink-0 whitespace-nowrap text-micro text-white/35">{since}</span>}
    </div>
  );
}

/**
 * `IslandFilesPanel`: the files the session changed with the totals over them; the whole card is one
 * button that opens the live window, where each file opens into its real diff.
 */
function FilesPanel({ session, onWatch }: { session: SessionView; onWatch: () => void }) {
  const files = session.files;
  const sum = totals(files);
  const rest = files.length - SHOWN_FILES;
  return (
    <button type="button" className={`${PRESSABLE} group flex min-w-0 flex-1 text-left`} onClick={onWatch} title="Open the live window to read the diffs">
      <IslandCard className="flex size-full min-w-0 flex-col gap-[7px] p-3.5">
        {files.length === 0 ? (
          <span className="m-auto text-center text-footnote text-island-soft">
            {onlyNetwork(session.steps) ? 'Memnox sees only where this session connects, not the files it changes' : 'No files changed yet'}
          </span>
        ) : (
          <>
            <div className="flex items-center gap-1.5">
              <span className="text-caption font-semibold text-white">{files.length === 1 ? '1 file changed' : `${files.length} files changed`}</span>
              <span className="min-w-1.5 flex-1" />
              <Counts added={sum.added} removed={sum.removed} />
            </div>
            {files.slice(0, SHOWN_FILES).map((file) => (
              <div key={file.path} className="flex min-w-0 items-center gap-1.5" title={file.path}>
                <span className="grid shrink-0 text-white/40">
                  <SFSymbol name="doc.text" size={10} weight="regular" />
                </span>
                {/* The name first, as its layout priority gives it, and the folder takes what is left. */}
                <span className="flex min-w-0 max-w-[70%] shrink-0">
                  <MiddleCut text={fileName(file.path)} className="text-footnote font-medium text-white" />
                </span>
                <span className="min-w-0 flex-1 shrink-[1000] truncate text-caption text-white/40" style={{ direction: 'rtl', textAlign: 'left' }}>
                  {/* Cut at its head, as `truncationMode(.head)` does, so the folder nearest the file stays. */}
                  <bdi>{folderOf(file.path)}</bdi>
                </span>
                <Counts added={file.added} removed={file.removed} />
              </div>
            ))}
            <span className="flex-1" />
            <span className="flex items-center gap-1 text-caption font-medium text-white/55 transition-colors group-hover:text-island-sky">
              <SFSymbol name="plusminus" size={11} weight="medium" />
              {rest > 0 ? `${rest} more, see every diff` : 'See the diffs'}
            </span>
          </>
        )}
      </IslandCard>
    </button>
  );
}
