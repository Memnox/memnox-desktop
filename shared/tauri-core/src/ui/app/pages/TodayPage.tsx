import { ChevronDown, ChevronUp, CircleArrowRight, CircleCheck, CircleDashed, CircleX, Fingerprint, TriangleAlert, type LucideIcon } from 'lucide-react';
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { HOLD_ANSWER } from '@memnox/core/wire';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import type { HeldCard } from '../../../core/domain/held-card';
import { briefItems, HOME_BRIEF_NONE, HOME_BRIEF_TITLE, homeBrief, type HomeBriefBlock } from '../../../core/domain/home-brief';
import { HomeLines } from '../../../core/domain/home-lines';
import { heldSigningLine, TodayNotes, TodayPageLines } from '../../../core/domain/home-page-lines';
import {
  age,
  choiceFor,
  heldId,
  NO_CHOICES,
  NO_RECOMMENDATION,
  position,
  signs,
  startOfDay,
  step,
  stripLine,
  syncedLine,
  TODAY_STATE_LABEL,
  under,
  URGENT_SHOWN,
  waited,
  waitsLine,
  type TodayChoice,
  type TodayItem,
  type TodaySources,
  type TodayState,
} from '../../../core/domain/today-board';
import { AgentName, BrandLogo } from '../../kit/logos';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { bringForward } from '../../sessions/open-session';
import { Inspector } from '../widgets';
import { GoLink } from './HomePage';
import { Button, IconButton, PRESS_DIP, Pressable, StatusWord, type Tone } from '../../kit';
import { handHeld, heldBusy } from '../held-hand';

/** The window reads the clock this often, so ages and the synced time stay true while it is open. */
const CLOCK_MS = 15_000;
/** How long the window waits before opening the live feed again after the daemon went away. */
const RECONNECT_MS = 2_000;

/** Each state's mark and colour, as the Mac's `StateMark` draws them, so the colour is never all that says it. */
const STATE_MARK: Record<TodayState, { icon: LucideIcon; tone: Tone }> = {
  'needs-you': { icon: TriangleAlert, tone: 'attention' },
  stopped: { icon: CircleX, tone: 'bad' },
  working: { icon: CircleDashed, tone: 'good' },
  'up-next': { icon: CircleArrowRight, tone: 'quiet' },
  done: { icon: CircleCheck, tone: 'good' },
};

const MARK_TEXT: Record<Tone, string> = {
  good: 'text-success',
  attention: 'text-warm',
  bad: 'text-destructive',
  quiet: 'text-muted',
};

/** The Mac's `WorkTable` widths: the number, From, When and State, with What taking what is left. Tailwind reads class
 * names whole, so the widths are written out here and a test holds them to `TODAY_TABLE`. */
const TABLE_COLUMNS = 'grid-cols-[28px_minmax(0,1fr)_170px_72px_118px]';

/** Where Activity opens, under Governance as the Mac places it. */
const ACTIVITY_ROUTE: Route = { destination: 'governance', tab: 'activity' };

/** `StateMark`'s glyph is caption sized and heavy, so it reads beside 12 point words. */
const STATE_GLYPH = 11;
const STATE_STROKE = 2.6;

/** The fingerprint on a choice that signs, as small as its keycap's letter. */
const SIGNED_GLYPH = 12;

/** A state as a mark in its colour beside its word, the Mac's `StateMark`, used on every work table. */
export function StateMark({ state }: { state: TodayState }) {
  const { icon: Icon, tone } = STATE_MARK[state];
  return (
    <span className="inline-flex min-w-0 items-center gap-1.5">
      <Icon size={STATE_GLYPH} strokeWidth={STATE_STROKE} className={`shrink-0 ${MARK_TEXT[tone]}`} aria-hidden />
      <span className="truncate text-meta font-medium text-foreground">{TODAY_STATE_LABEL[state]}</span>
    </span>
  );
}

/**
 * What Today showed, drawn on Home below `lead` as the console's home brief: waiting on you, working now, today, ready
 * to hand over and not covered. Every answer to a held call goes through `HeldCalls`, so an allow is signed with this
 * computer's key exactly as on the island, and is not sent when the signature is not given. Ported from the Mac's
 * `TodayDestination`.
 */
export function TodayPage({
  parts,
  width,
  go,
  lead,
  waitingFoot,
  trail,
}: {
  parts: SettingsParts;
  width: WidthClass;
  go: (route: Route) => void;
  /** The greeting and the getting started steps, above every block. */
  lead: ReactNode;
  /** What else waits on the person and lives outside Today's items, under Waiting on you. */
  waitingFoot: ReactNode;
  /** The counts and the sessions to carry on, below every block. */
  trail: ReactNode;
}) {
  const { calls, sessions, home, agents, activity, support, words, projects } = parts;
  useObserved(calls, home, agents, activity, support, projects);
  useSessions(parts);
  useHeldFeed(parts);
  const [now, setNow] = useState(Date.now);
  const [readAt, setReadAt] = useState(Date.now);
  const [hidden, setHidden] = useState<ReadonlySet<HomeBriefBlock>>(new Set());
  const [everyUrgent, setEveryUrgent] = useState(false);
  const [open, setOpen] = useState<string | undefined>(undefined);
  const [note, setNote] = useState<string | undefined>(undefined);
  const page = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const clock = setInterval(() => setNow(Date.now()), CLOCK_MS);
    return () => clearInterval(clock);
  }, []);
  const readActivity = () => {
    if (support.supports('activity') !== true) return;
    void activity.show({ since: new Date(startOfDay(Date.now())).toISOString() }).then(() => setReadAt(Date.now()));
  };
  useEffect(() => {
    void home.refresh().then(() => setReadAt(Date.now()));
    if (support.supports('agents') === true) void agents.refresh();
    readActivity();
    // The projects name where each held call and session happens, so a person with several sees where.
    if (support.supports('projects') === true && projects.projects === undefined) void projects.refresh();
    page.current?.focus();
  }, [support.supports('agents'), support.supports('activity')]);
  // A row arriving live is a name only, so the day is read again to show it whole.
  useEffect(() => parts.host.onLiveActivity?.(() => readActivity()), []);
  useEffect(() => parts.host.onHomeStale?.(() => void home.refreshSoon()), []);

  const waiting = calls.state.waiting.entries;
  const sources: TodaySources = {
    held: waiting.map(({ subject, card }) => ({
      subject,
      agent: card.agent,
      who: card.who,
      what: card.what,
      ...(card.why === undefined ? {} : { why: card.why }),
      ...(card.sessionId === undefined ? {} : { sessionId: card.sessionId }),
      ...(card.place === undefined ? {} : { place: card.place }),
    })),
    sessions: sessions.state.cards,
    activity: activity.rows,
    agents: agents.agents ?? [],
    owed: home.home?.needsYou ?? [],
    ...(home.home?.ready === undefined ? {} : { ready: home.home.ready }),
    projects: projects.projects ?? [],
  };
  const blocks = homeBrief(sources, now);
  const items = briefItems(blocks);
  const opened = items.find((item) => item.id === open);
  const needYou = blocks.find((each) => each.block === 'waiting')?.items ?? [];

  const cardOf = (item: TodayItem): HeldCard | undefined => waiting.find(({ subject }) => heldId(subject) === item.id)?.card;
  const busy = (item: TodayItem): boolean => {
    if (item.kind.kind === 'held') return heldBusy(calls.state);
    if (item.kind.kind === 'hand-over') return home.handingOver;
    if (item.kind.kind === 'unprotected') return home.protecting;
    return false;
  };
  const moveTo = (id: string | undefined) => {
    const block = blocks.find((each) => each.items.some((item) => item.id === id))?.block;
    // Moving onto a row folded away opens it, so the open item is always on screen.
    if (block !== undefined && hidden.has(block)) setHidden((now) => new Set([...now].filter((each) => each !== block)));
    if (block === 'waiting' && needYou.findIndex((each) => each.id === id) >= URGENT_SHOWN) setEveryUrgent(true);
    setOpen(id);
  };

  const decide = async (choice: TodayChoice, item: TodayItem) => {
    setNote(undefined);
    switch (choice.action.kind) {
      case 'answer': {
        const card = cardOf(item);
        if (card === undefined) return;
        // The item leaves once answered, so the one after it opens rather than nothing.
        const after = step(item.id, 1, items);
        // An edit is made on the island's own card alone, so it is never offered here.
        if (choice.action.answer === HOLD_ANSWER.EDIT) return;
        // Handed to the island, as the Mac's Today does, so an allow is signed there and how it ended is said on its card.
        handHeld(calls, card.subject, choice.action.answer);
        setOpen(after === item.id ? undefined : after);
        return;
      }
      case 'hand-over':
        if (home.home?.ready !== undefined) await home.handOver(home.home.ready, words.keyTitle);
        setNote(home.handOverNote);
        return;
      case 'protect':
        await home.protect();
        if (support.supports('agents') === true) await agents.refresh();
        setNote(home.protectFailed);
        return;
      case 'open-conversation':
        if (item.sessionId !== undefined) parts.host.openLive?.(item.sessionId);
        return;
      case 'find-in-app': {
        const card = sessions.state.cards.find((each) => each.sessionId === item.sessionId);
        const shown = await bringForward(card?.host);
        if (shown.reason !== undefined) setNote(TodayNotes.notForward(shown.reason));
        return;
      }
      case 'open-activity':
        go(ACTIVITY_ROUTE);
        return;
    }
  };

  const keys = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) return;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      moveTo(step(open, event.key === 'ArrowDown' ? 1 : -1, items));
      return;
    }
    if (event.metaKey || event.ctrlKey || event.altKey || event.key.length !== 1 || opened === undefined || busy(opened)) return;
    const choice = choiceFor(event.key, opened);
    if (choice === undefined) return;
    event.preventDefault();
    void decide(choice, opened);
  };

  const shownUrgent = everyUrgent ? needYou.length : Math.min(needYou.length, URGENT_SHOWN);
  return (
    <div ref={page} tabIndex={-1} onKeyDown={keys} className="flex min-h-0 outline-none">
      <div className="flex min-w-0 flex-1 flex-col gap-6">
        {lead}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-md border border-panel-edge bg-hover px-4 py-2.5 text-meta text-muted">
          <span className={needYou.length === 0 ? 'invisible' : ''}>
            <StateMark state={needYou.length === 0 ? 'done' : 'needs-you'} />
          </span>
          <span className="text-foreground">{stripLine(needYou.length, shownUrgent)}</span>
          {waitsLine(needYou) !== undefined && <span>{waitsLine(needYou)}</span>}
          <span className="flex-1" />
          <span className="font-code text-label text-faint">{syncedLine(readAt)}</span>
        </div>
        {note !== undefined && <p role="status" className="text-footnote text-muted">{note}</p>}
        {blocks.map(({ block, items: held }) => {
          const folded = hidden.has(block);
          const cut = block === 'waiting' && !everyUrgent && held.length > URGENT_SHOWN;
          const shown = cut ? held.slice(0, URGENT_SHOWN) : held;
          const today = home.home?.today;
          return (
            <section key={block} className="flex flex-col gap-2.5">
              <div className="flex min-h-7 items-center justify-between gap-3">
                <h2 className="text-base font-medium text-foreground">{held.length === 0 ? HOME_BRIEF_TITLE[block] : `${HOME_BRIEF_TITLE[block]} · ${held.length}`}</h2>
                <span className="flex items-center gap-2">
                  {block === 'today' && <GoLink onClick={() => go(ACTIVITY_ROUTE)}>{TodayPageLines.activity}</GoLink>}
                  {held.length > 0 && (
                    <Button onClick={() => setHidden((now) => (folded ? new Set([...now].filter((each) => each !== block)) : new Set([...now, block])))}>{folded ? TodayPageLines.show : TodayPageLines.hide}</Button>
                  )}
                </span>
              </div>
              {held.length === 0 ? (
                <p className="text-body-sm text-muted">{HOME_BRIEF_NONE[block]}</p>
              ) : (
                !folded && <Table items={shown} all={items} now={now} open={open} pick={moveTo} />
              )}
              {!folded && cut && <GoLink onClick={() => setEveryUrgent(true)}>{TodayPageLines.showAll(held.length)}</GoLink>}
              {block === 'today' && today !== undefined && <p className="text-footnote text-muted">{HomeLines.today(today)}</p>}
              {block === 'waiting' && waitingFoot}
            </section>
          );
        })}
        {trail}
      </div>
      {opened !== undefined && (
        <Inspector title={position(opened.id, items) ?? TodayNotes.details} width={width} close={() => setOpen(undefined)}>
          <Detail
            item={opened}
            card={cardOf(opened)}
            now={now}
            keyTitle={words.keyTitle}
            busy={busy(opened)}
            first={items[0]?.id === opened.id}
            last={items[items.length - 1]?.id === opened.id}
            move={(offset) => moveTo(step(opened.id, offset, items))}
            press={(choice) => void decide(choice, opened)}
          />
        </Inspector>
      )}
    </div>
  );
}

/** The live sessions, read while Today is open as Home and Agents read them. */
function useSessions({ sessions }: SettingsParts): void {
  const [, redraw] = useState(0);
  useEffect(() => {
    const stop = sessions.observe(() => redraw((count) => count + 1));
    sessions.start();
    return () => {
      stop();
      sessions.stop();
    };
  }, []);
}

/** The feed of what waits, so a call held while Today is open joins it at once, as the Approvals page keeps it. */
function useHeldFeed({ calls }: SettingsParts): void {
  useEffect(() => {
    let open = true;
    const loop = async () => {
      while (open) {
        await calls.watch();
        if (open) await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
      }
    };
    void loop();
    return () => {
      open = false;
    };
  }, []);
}

/** The numbered table: what, with its muted line under it, who it is from, how long ago, and its state. */
function Table({ items, all, now, open, pick }: { items: readonly TodayItem[]; all: readonly TodayItem[]; now: number; open: string | undefined; pick: (id: string) => void }) {
  return (
    <div className="overflow-hidden rounded-card border border-panel-edge bg-card">
      <div className={`grid ${TABLE_COLUMNS} h-[34px] items-center gap-3 border-b border-panel-edge px-4 text-label font-medium text-faint`} aria-hidden>
        {TodayPageLines.columns.map((title, index) => (
          <span key={index} className="truncate">
            {title}
          </span>
        ))}
      </div>
      <div className="divide-y divide-panel-edge">
        {items.map((item) => {
          const number = all.findIndex((each) => each.id === item.id) + 1;
          const line = under(item);
          const chosen = item.id === open;
          return (
            <Pressable
              key={item.id}
              aria-pressed={chosen}
              aria-label={TodayNotes.rowLabel(number, item.title, item.agentName, TODAY_STATE_LABEL[item.state])}
              onClick={() => pick(item.id)}
              className={`mx-focus grid w-full cursor-pointer ${TABLE_COLUMNS} items-center gap-3 px-4 py-3 text-left hover:bg-hover ${PRESS_DIP} ${chosen ? 'bg-active' : ''}`}
            >
              <span className="font-code text-label text-faint">{number}</span>
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="truncate text-body-sm font-medium text-foreground">{item.title}</span>
                {line !== undefined && <span className="truncate text-meta text-muted">{line}</span>}
              </span>
              <span className="flex min-w-0 items-center gap-1.5">
                {/* Written out, as the widths are, so the test holds the logo to TODAY_TABLE.logo. */}
                <BrandLogo agent={item.agent ?? 'memnox'} name={item.agentName} size={20} />
                <span className="truncate text-meta text-foreground">{item.agentName}</span>
              </span>
              <span className="font-code text-label text-muted">{age(item.since, now) ?? ''}</span>
              <span className="min-w-0">
                <StateMark state={item.state} />
              </span>
            </Pressable>
          );
        })}
      </div>
    </div>
  );
}

/** The open item: what it is, the facts, what was recommended, and the choices, each pressed by its letter. */
function Detail({
  item,
  card,
  now,
  keyTitle,
  busy,
  first,
  last,
  move,
  press,
}: {
  item: TodayItem;
  card: HeldCard | undefined;
  now: number;
  keyTitle: string;
  busy: boolean;
  first: boolean;
  last: boolean;
  move: (offset: number) => void;
  press: (choice: TodayChoice) => void;
}) {
  const facts: [string, ReactNode][] = [
    [TodayPageLines.from, <AgentName agent={item.agent ?? 'memnox'} name={item.agentName} />],
    [TodayPageLines.waiting, waited(item.since, now)],
  ];
  if (item.project !== undefined) facts.push([TodayPageLines.project, item.project]);
  if (item.detail !== undefined) facts.push([TodayPageLines.about, item.detail]);
  if (item.kind.kind === 'held' && card !== undefined) facts.push([TodayPageLines.signed, heldSigningLine(card.touchID, card.actionDigest, keyTitle)]);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-1.5">
        <StepButton label={TodayPageLines.above} disabled={first} onClick={() => move(-1)} up />
        <StepButton label={TodayPageLines.below} disabled={last} onClick={() => move(1)} />
        <span className="flex-1" />
        <span className="text-label text-faint">{TodayPageLines.keys}</span>
      </div>
      <h3 className="text-lg font-semibold break-words text-foreground select-text">{item.title}</h3>
      <span>
        <StateMark state={item.state} />
      </span>
      <dl className="grid grid-cols-[auto_1fr] items-baseline gap-x-4 gap-y-2 text-meta">
        {facts.map(([name, value]) => (
          <div key={name} className="contents">
            <dt className="text-muted">{name}</dt>
            <dd className="min-w-0 break-words text-foreground">{value}</dd>
          </div>
        ))}
      </dl>
      <Block title={TodayPageLines.recommendation}>
        <p className={`text-body-sm ${item.recommendation === undefined ? 'text-muted' : 'text-foreground'}`}>{item.recommendation ?? NO_RECOMMENDATION}</p>
      </Block>
      <Block title={TodayPageLines.decide}>
        {item.choices.length === 0 ? (
          <p className="text-body-sm text-muted">{NO_CHOICES}</p>
        ) : (
          <div className="flex flex-col gap-1.5">
            {item.choices.map((choice) => (
              <ChoiceRow key={choice.key} choice={choice} signed={signs(choice, card?.touchID)} keyTitle={keyTitle} disabled={busy} press={() => press(choice)} />
            ))}
          </div>
        )}
      </Block>
    </div>
  );
}

function Block({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <h4 className="font-code text-label font-medium tracking-[0.18em] text-faint">{title}</h4>
      {children}
    </section>
  );
}

function StepButton({ label, disabled, onClick, up = false }: { label: string; disabled: boolean; onClick: () => void; up?: boolean }) {
  return <IconButton icon={up ? ChevronUp : ChevronDown} label={label} disabled={disabled} onClick={onClick} />;
}

/** One choice: its letter on a key, its words, the key that signs where the allow is signed, and the recommendation marked. */
function ChoiceRow({ choice, signed, keyTitle, disabled, press }: { choice: TodayChoice; signed: boolean; keyTitle: string; disabled: boolean; press: () => void }) {
  return (
    <Pressable
      disabled={disabled}
      onClick={press}
      title={TodayPageLines.press(choice.key)}
      aria-label={TodayNotes.choiceLabel(choice.title, choice.recommended, signed ? keyTitle : undefined)}
      className={`mx-focus flex h-field cursor-pointer items-center gap-2.5 rounded-control border bg-card px-2.5 text-left hover:bg-hover disabled:cursor-default disabled:opacity-50 ${PRESS_DIP} ${choice.recommended ? 'border-primary' : 'border-panel-edge'}`}
    >
      <span className="grid size-[22px] place-items-center rounded-control border border-panel-edge bg-keycap font-code text-label font-medium text-muted">{choice.key}</span>
      <span className="text-body-sm font-medium text-foreground">{choice.title}</span>
      {signed && <Fingerprint size={SIGNED_GLYPH} className="text-muted" aria-hidden />}
      <span className="flex-1" />
      {choice.recommended && <StatusWord tone="good">{TodayPageLines.recommended}</StatusWord>}
    </Pressable>
  );
}
