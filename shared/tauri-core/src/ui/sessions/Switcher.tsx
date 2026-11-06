import { useEffect, useRef, useState } from 'react';
import type { SessionCard } from '@memnox/core/wire';
import { cardStatus, cardTitle, statusLabel, statusTint } from '../../core';
import { shelfPlace, shelfStart, SWITCHER_TIMING, turnMs } from '../../core/domain/switcher';
import { BrandLogo } from '../kit';
import { tinted } from './parts';
import './sessions.css';
import { SessionCardLines } from '../../core/domain/island-lines';

/**
 * The switcher's look, as the Mac's shelf: the window dims to 38%, the shelf rises from 40 below to rest 30 above
 * centre in a 440 perspective, the front card wears its status colour at 80% and a deeper shadow, and each card's
 * depth orders it. The turn eases with a slight overshoot, and the switcher closes a frame after its exit.
 */
const SWITCHER_LOOK = { dim: 0.38, enterFrom: 40, restAt: -30, perspective: 440, zBase: 100, zStep: 10, frontEdge: 0.8, overshoot: 0.6, doneSlackMs: 10 } as const;

/**
 * The switcher, the web twin of the Mac's `SwitcherPanel`: the sessions as cards on a shelf, turning past
 * until the one asked for faces the person, which then comes forward before the row leaves. `onDone` runs
 * once it has gone, which is where the session's live window opens.
 */
export function Switcher({ cards, target, onDone, still = false }: { cards: readonly SessionCard[]; target: string; onDone: () => void; still?: boolean }) {
  const index = Math.max(0, cards.findIndex((card) => card.sessionId === target));
  const start = still ? index : shelfStart(index, cards.length);
  const [selected, setSelected] = useState(start);
  const [shown, setShown] = useState(still);
  const [chosen, setChosen] = useState(false);
  const done = useRef(onDone);
  done.current = onDone;

  useEffect(() => {
    if (still) return;
    const timers: ReturnType<typeof setTimeout>[] = [];
    let frame = 0;
    const at = (ms: number, step: () => void) => timers.push(setTimeout(step, ms));
    requestAnimationFrame(() => setShown(true));
    const turn = turnMs(start, index);
    at(SWITCHER_TIMING.settleBeforeTurn, () => {
      const began = performance.now();
      const tick = (now: number) => {
        const p = Math.min(1, (now - began) / turn);
        // A spring at damping 0.82 eases out with the slightest overshoot, which this curve stands in for.
        const eased = 1 - Math.pow(1 - p, 3) * (1 - SWITCHER_LOOK.overshoot * p);
        setSelected(start + (index - start) * eased);
        if (p < 1) frame = requestAnimationFrame(tick);
      };
      frame = requestAnimationFrame(tick);
    });
    const chooseAt = SWITCHER_TIMING.settleBeforeTurn + SWITCHER_TIMING.perStep * Math.abs(index - start) + SWITCHER_TIMING.hold;
    at(chooseAt, () => setChosen(true));
    at(chooseAt + SWITCHER_TIMING.chosenHold, () => setShown(false));
    at(chooseAt + SWITCHER_TIMING.chosenHold + SWITCHER_TIMING.exit + SWITCHER_LOOK.doneSlackMs, () => done.current());
    return () => {
      timers.forEach(clearTimeout);
      cancelAnimationFrame(frame);
    };
  }, [start, index, still]);

  return (
    <div className="fixed inset-0 overflow-hidden font-sans">
      <div className="absolute inset-0 bg-black transition-opacity" style={{ opacity: shown ? SWITCHER_LOOK.dim : 0, transitionDuration: `${shown ? SWITCHER_TIMING.fadeIn : SWITCHER_TIMING.exit}ms` }} />
      <div
        className="absolute inset-0 grid place-items-center transition-[opacity,translate]"
        style={{ opacity: shown ? 1 : 0, translate: `0 ${shown ? SWITCHER_LOOK.restAt : SWITCHER_LOOK.enterFrom}px`, transitionDuration: `${shown ? SWITCHER_TIMING.fadeIn : SWITCHER_TIMING.exit}ms`, perspective: SWITCHER_LOOK.perspective }}
      >
        {cards.map((card, at) => {
          const place = shelfPlace(at - selected, chosen);
          return (
            <div
              key={card.sessionId}
              className="col-start-1 row-start-1 transition-[scale,translate,filter] duration-[450ms] ease-[cubic-bezier(0.34,1.35,0.64,1)]"
              style={{
                transform: `translateX(${place.x}px) rotateY(${place.rotateY}deg)`,
                scale: place.scale,
                translate: `0 ${place.y}px`,
                filter: `brightness(${1 + place.brightness})`,
                opacity: place.hidden ? 0 : 1,
                zIndex: Math.round(SWITCHER_LOOK.zBase + place.z * SWITCHER_LOOK.zStep),
              }}
            >
              <SessionTile card={card} front={place.front} />
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** The card reflected in the glass it stands on, `reflectionGap` below it and fading out at `reflectionOpacity`. */
const TILE_REFLECTION = 'below var(--mx-session-tile-reflection-gap) linear-gradient(transparent 70%, rgb(0 0 0 / var(--mx-session-tile-reflection)))';

/** One session as a card: where it runs, who it is, what it is on and how it stands, reflected in the glass below. */
function SessionTile({ card, front }: { card: SessionCard; front: boolean }) {
  const status = cardStatus(card);
  const colour = statusTint(status);
  return (
    <div
      className={`flex h-session-tile-height w-session-tile-width flex-col gap-3 rounded-island border-(length:--mx-session-surface-edge) bg-surface p-session-tile-pad text-foreground ${front ? 'shadow-session-tile-front' : 'border-ink/[0.11] shadow-session-tile'}`}
      style={{
        borderColor: front ? tinted(colour, SWITCHER_LOOK.frontEdge) : undefined,
        WebkitBoxReflect: TILE_REFLECTION,
      }}
    >
      <div className="flex min-w-0 items-center gap-2.5">
        <BrandLogo agent={card.agent} name={card.agentName} size={36} />
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="truncate font-display text-session-tile-name leading-tight text-foreground">{card.agentName}</span>
          <span className="truncate text-caption text-muted">{card.runningIn ?? SessionCardLines.somewhereUnknown}</span>
        </div>
      </div>
      <p className="m-0 line-clamp-4 text-body text-foreground/90">{cardTitle(card)}</p>
      <span className="flex-1" />
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="size-session-dot shrink-0 rounded-full" style={{ backgroundColor: colour }} />
        <span className="shrink-0 text-caption font-medium" style={{ color: colour }}>
          {statusLabel(status)}
        </span>
        <span className="flex-1" />
        {card.repository !== undefined && <span className="truncate text-caption text-muted">{card.repository}</span>}
      </div>
    </div>
  );
}
