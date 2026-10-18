import { useEffect, useState } from 'react';
import type { DisplayHost, TraceCard } from '@memnox/core/wire';
import { openWords, pagePosition, pageSeconds, traceBar, traceSubtitle, traceTone, type FloatingCard } from '../../../core/domain/floating-cards';
import { traceStepName } from '../../../core/domain/session-text';
import { BrandLogo, LogoMark } from '../../kit';
import { MarkdownText, SYSTEM_MONO } from '../MarkdownText';
import { CardButton, CardFace, CardHeader, CodeExcerpt, FileList, PageDots } from './parts';

/** What the person asked of a card: its session's live window, or the session's own window. */
export interface CardActions {
  close: () => void;
  watch: (sessionId: string, host: DisplayHost | undefined) => void;
  open: (sessionId: string, host: DisplayHost | undefined) => void;
  link?: (href: string) => void;
  hovering?: (over: boolean) => void;
}

/** One floating card, by its kind. */
export function FloatingCardView({ card, actions }: { card: FloatingCard; actions: CardActions }) {
  switch (card.kind) {
    case 'summary':
      return <SummaryCardView card={card} actions={actions} />;
    case 'walk':
      return <WalkView card={card} actions={actions} />;
    case 'trace':
      return <TraceView title={card.title} trace={card.trace} actions={actions} />;
  }
}

/** The mark a card about a session wears: its agent's logo, else Memnox's. */
function markFor(agent: string | undefined) {
  return agent === undefined || agent === '' ? <LogoMark size={28} /> : <BrandLogo agent={agent} name={agent} size={28} />;
}

/**
 * `CardView`: a summary read while the voice says it: heading, the summary as markdown, the files it
 * changed and a few of the changed lines, then Watch live and Open.
 */
function SummaryCardView({ card, actions }: { card: Extract<FloatingCard, { kind: 'summary' }>; actions: CardActions }) {
  const session = card.sessionId;
  return (
    <CardFace onHover={actions.hovering}>
      <div className="flex flex-col gap-3">
        <CardHeader mark={markFor(card.agent)} title={card.title} subtitle={card.host?.app} onClose={actions.close} />
        <MarkdownText source={card.text} tone="window" onLink={actions.link} />
        <FileList files={card.files} />
        {card.excerpt !== undefined && <CodeExcerpt excerpt={card.excerpt} />}
        {session !== undefined && (
          <div className="flex items-center gap-2">
            <span className="flex-1" />
            <CardButton symbol="play.circle" onClick={() => actions.watch(session, card.host)}>
              Watch live
            </CardButton>
            <CardButton kind="primary" symbol="arrow.up.forward.app" onClick={() => actions.open(session, card.host)}>
              {openWords(card.host, 'Open session')}
            </CardButton>
          </div>
        )}
      </div>
    </CardFace>
  );
}

/**
 * `WalkView`: one page per changed file, turning on its own at the voice's pace until the person turns
 * one, sliding in from the trailing edge; Back and Next dim at the ends.
 */
function WalkView({ card, actions }: { card: Extract<FloatingCard, { kind: 'walk' }>; actions: CardActions }) {
  const [index, setIndex] = useState(0);
  const [byHand, setByHand] = useState(false);
  const [direction, setDirection] = useState<'next' | 'back'>('next');
  const count = card.pages.length;
  const page = card.pages[Math.min(index, count - 1)];

  useEffect(() => {
    if (byHand || page === undefined || index >= count - 1) return;
    const turn = setTimeout(() => {
      setDirection('next');
      setIndex((now) => Math.min(now + 1, count - 1));
    }, pageSeconds(page) * 1000);
    return () => clearTimeout(turn);
  }, [byHand, index, count, page]);

  function turn(by: number) {
    setByHand(true);
    setDirection(by > 0 ? 'next' : 'back');
    setIndex((now) => Math.min(Math.max(now + by, 0), count - 1));
  }

  if (page === undefined) return null;
  const session = card.sessionId;
  return (
    <CardFace onHover={actions.hovering}>
      <div className="flex flex-col gap-3">
        <CardHeader mark={markFor(card.agent)} title={card.title} accessory={<span className="tabular text-caption font-medium text-muted">{pagePosition(index, count)}</span>} onClose={actions.close} />
        <div className="relative h-[300px] overflow-hidden">
          <div key={index} className="flex flex-col gap-2.5" style={{ animation: `${direction === 'next' ? 'walk-in-next' : 'walk-in-back'} 460ms cubic-bezier(0.3, 1.1, 0.6, 1) both` }}>
            <FileList files={[{ path: page.path, added: page.added, removed: page.removed }]} />
            <p className="m-0 text-callout leading-[20px] text-foreground/[0.92] select-text">{page.note}</p>
            {page.lines.length > 0 && <CodeExcerpt excerpt={{ path: page.path, lines: page.lines }} />}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <PageDots count={count} current={index} />
          <span className="flex-1" />
          <CardButton symbol="chevron.left" disabled={index === 0} className={index === 0 ? '!opacity-35' : ''} onClick={() => turn(-1)}>
            Back
          </CardButton>
          <CardButton symbol="chevron.right" disabled={index >= count - 1} className={index >= count - 1 ? '!opacity-35' : ''} onClick={() => turn(1)}>
            Next
          </CardButton>
          {session !== undefined && (
            <CardButton kind="primary" symbol="arrow.up.forward.app" onClick={() => actions.open(session, card.host)}>
              Open
            </CardButton>
          )}
        </div>
      </div>
    </CardFace>
  );
}

const TONE: Record<ReturnType<typeof traceTone>, string> = {
  destructive: 'var(--mx-destructive)',
  warm: 'var(--mx-warm)',
  primary: '#3b82f7',
  success: 'var(--mx-success)',
};

/** Milliseconds under a second and seconds with one place above, the way a waterfall is read. */
function duration(ms: number): string {
  return ms < 1000 ? `${Math.trunc(ms)} ms` : `${(ms / 1000).toFixed(1)} s`;
}

/** The track every bar sits on. */
const TRACK = 170;

/**
 * `TraceView`: a trace the way a waterfall draws one: each step indented under what it ran inside, a
 * bar on the trace's own clock, blue at the top, green beneath, red when it failed, amber when refused.
 */
function TraceView({ title, trace, actions }: { title: string; trace: TraceCard; actions: CardActions }) {
  const [grown, setGrown] = useState(false);
  // A frame after the card is drawn, so each bar grows from nothing on its own delay.
  useEffect(() => {
    const frame = requestAnimationFrame(() => setGrown(true));
    return () => cancelAnimationFrame(frame);
  }, []);
  return (
    <CardFace onHover={actions.hovering}>
      <div className="flex flex-col gap-3">
        <CardHeader
          title={title}
          subtitle={traceSubtitle(trace.rows.length)}
          accessory={<span className={`${SYSTEM_MONO} text-body font-semibold text-primary`}>{duration(trace.totalMs)}</span>}
          onClose={actions.close}
        />
        <div className="flex flex-col gap-1.5">
          {trace.rows.map((row, index) => {
            const bar = traceBar(row, trace.totalMs, TRACK);
            return (
              <div key={index} className="flex items-center gap-2.5">
                <span className={`w-[150px] shrink-0 truncate text-footnote ${row.depth === 0 ? 'font-semibold text-foreground' : 'text-foreground/85'}`} style={{ paddingLeft: bar.indent }} title={row.name}>
                  {traceStepName(row.name)}
                </span>
                <span className="relative h-1.5 shrink-0 rounded-full bg-[var(--mx-ink-faint-fill)]" style={{ width: TRACK }}>
                  <span
                    className="absolute top-0 h-1.5 rounded-full transition-[width] duration-[620ms] ease-[cubic-bezier(0.3,1.1,0.6,1)]"
                    style={{ left: bar.offset, width: grown ? bar.width : 0, backgroundColor: TONE[traceTone(row)], transitionDelay: `${250 + index * 50}ms` }}
                  />
                </span>
                <span className={`w-[52px] shrink-0 text-right ${SYSTEM_MONO} text-caption text-muted`}>{duration(row.durationMs)}</span>
              </div>
            );
          })}
        </div>
      </div>
    </CardFace>
  );
}
