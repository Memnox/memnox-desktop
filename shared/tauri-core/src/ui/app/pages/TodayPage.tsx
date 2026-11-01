import { CheckCircle2, ChevronDown, ChevronUp, Fingerprint, ListChecks, Sun, Undo2 } from 'lucide-react';
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import type { HeldOutcome } from '../../../core/application/held-calls';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import type { HeldCard } from '../../../core/domain/held-card';
import {
  age,
  choiceFor,
  done,
  handoffs,
  headline,
  heldId,
  log,
  NO_CHOICES,
  NO_RECOMMENDATION,
  openProjects,
  overview,
  position,
  sectionOf,
  sections,
  signs,
  startOfDay,
  step,
  stripLine,
  syncedLine,
  TODAY_SECTION_TITLE,
  TODAY_STATE_LABEL,
  TODAY_TAB_TITLE,
  TODAY_TABS,
  under,
  URGENT_SHOWN,
  waited,
  waitsLine,
  type TodayChoice,
  type TodayItem,
  type TodaySection,
  type TodaySources,
  type TodayState,
  type TodayTab,
} from '../../../core/domain/today-board';
import { BrandLogo } from '../../kit/logos';
import { KitButton, PageTitle } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { bringForward } from '../../sessions/open-session';
import { EmptyState, Inspector, StatusWord, type Tone } from '../widgets';
import { GoLink } from './HomePage';

/** The window reads the clock this often, so ages and the synced time stay true while it is open. */
const CLOCK_MS = 15_000;
/** How long the window waits before opening the live feed again after the daemon went away. */
const RECONNECT_MS = 2_000;

const STATE_TONE: Record<TodayState, Tone> = {
  'needs-you': 'attention',
  stopped: 'bad',
  working: 'good',
  'up-next': 'quiet',
  done: 'good',
};

/**
 * What needs the person today, most urgent first, read off what the window already holds: the calls waiting, the
 * sessions, what the agents did since midnight, the agents outside Memnox and what only the person can do. Every
 * answer to a held call goes through `HeldCalls`, so an allow is signed with this computer's key exactly as on the
 * island, and is not sent when the signature is not given. Ported from the Mac's `TodayDestination`.
 */
export function TodayPage({ parts, width, go }: { parts: SettingsParts; width: WidthClass; go: (route: Route) => void }) {
  const { calls, sessions, home, agents, activity, support, words } = parts;
  useObserved(calls, home, agents, activity, support);
  useSessions(parts);
  useHeldFeed(parts);
  const [now, setNow] = useState(Date.now);
  const [readAt, setReadAt] = useState(Date.now);
  const [tab, setTab] = useState<TodayTab>('overview');
  const [hidden, setHidden] = useState<ReadonlySet<TodaySection>>(new Set());
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
    page.current?.focus();
  }, [support.supports('agents'), support.supports('activity')]);
  // A row arriving live is a name only, so the day is read again to show it whole.
  useEffect(() => parts.host.onLiveActivity?.(() => readActivity()), []);
  useEffect(() => parts.host.onHomeStale?.(() => void home.refreshSoon()), []);

  const waiting = calls.state.waiting.entries;
  const sources: TodaySources = {
    held: waiting.map(({ subject, card }) => ({ subject, agent: card.agent, who: card.who, what: card.what, ...(card.why === undefined ? {} : { why: card.why }), ...(card.sessionId === undefined ? {} : { sessionId: card.sessionId }) })),
    sessions: sessions.state.cards,
    activity: activity.rows,
    agents: agents.agents ?? [],
    owed: home.home?.needsYou ?? [],
    ...(home.home?.ready === undefined ? {} : { ready: home.home.ready }),
  };
  const board = overview(sources, now);
  const lists: Record<TodayTab, TodayItem[]> = { overview: board, done: done(activity.rows, now), handoffs: handoffs(sources), log: log(activity.rows, now) };
  const items = lists[tab];
  const opened = items.find((item) => item.id === open);
  const needYou = board.filter((item) => sectionOf(item) === 'needs-you');
  const nextCount = board.filter((item) => sectionOf(item) === 'next').length;

  const cardOf = (item: TodayItem): HeldCard | undefined => waiting.find(({ subject }) => heldId(subject) === item.id)?.card;
  const busy = (item: TodayItem): boolean => {
    if (item.kind.kind === 'held') return calls.state.answering;
    if (item.kind.kind === 'hand-over') return home.handingOver;
    if (item.kind.kind === 'unprotected') return home.protecting;
    return false;
  };
  const moveTo = (id: string | undefined) => {
    const item = items.find((each) => each.id === id);
    const section = item === undefined ? undefined : sectionOf(item);
    // Moving onto a row folded away opens it, so the open item is always on screen.
    if (section !== undefined && hidden.has(section)) setHidden((now) => new Set([...now].filter((each) => each !== section)));
    if (section === 'needs-you' && needYou.findIndex((each) => each.id === id) >= URGENT_SHOWN) setEveryUrgent(true);
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
        // The same path the island's buttons take, so an allow is signed or is not sent.
        const outcome = await calls.answer(card.subject, choice.action.answer);
        if (outcome.kind === 'answered' || outcome.kind === 'answered-elsewhere') setOpen(after === item.id ? undefined : after);
        setNote(outcomeNote(outcome));
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
        if (shown.reason !== undefined) setNote(`Memnox could not bring it forward: ${shown.reason}.`);
        return;
      }
      case 'open-activity':
        go({ destination: 'governance', tab: 'activity' });
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
      <div className="flex min-w-0 flex-1 flex-col gap-5">
        <PageTitle title="Today" subtitle={headline(now, needYou.length, nextCount, openProjects(sessions.state.cards))} />
        <CountTabs chosen={tab} counts={lists} choose={(next) => (setTab(next), setOpen(undefined))} />
        {tab === 'overview' && (
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl border border-panel-edge bg-card px-4 py-2.5 text-body-sm text-muted">
            <span className={needYou.length === 0 ? 'invisible' : ''}>
              <StatusWord tone={needYou.length === 0 ? 'good' : 'attention'}>{needYou.length === 0 ? TODAY_STATE_LABEL.done : TODAY_STATE_LABEL['needs-you']}</StatusWord>
            </span>
            <span className="text-foreground">{stripLine(needYou.length, shownUrgent)}</span>
            {waitsLine(needYou) !== undefined && <span>{waitsLine(needYou)}</span>}
            <span className="flex-1" />
            <span className="font-code text-label text-faint">{syncedLine(readAt)}</span>
          </div>
        )}
        {note !== undefined && <p role="status" className="text-footnote text-muted">{note}</p>}
        {items.length === 0 ? (
          <Empty tab={tab} activity={support.supports('activity') === true} />
        ) : tab === 'overview' ? (
          sections(items).map(({ section, items: held }) => {
            const folded = hidden.has(section);
            const cut = section === 'needs-you' && !everyUrgent && held.length > URGENT_SHOWN;
            const shown = cut ? held.slice(0, URGENT_SHOWN) : held;
            return (
              <section key={section} className="flex flex-col gap-2.5">
                <div className="flex min-h-7 items-center justify-between gap-3">
                  <h2 className="text-base font-medium text-foreground">{`${TODAY_SECTION_TITLE[section]} · ${held.length}`}</h2>
                  <KitButton onClick={() => setHidden((now) => (folded ? new Set([...now].filter((each) => each !== section)) : new Set([...now, section])))}>{folded ? 'Show' : 'Hide'}</KitButton>
                </div>
                {!folded && <Table items={shown} all={items} now={now} open={open} pick={moveTo} />}
                {!folded && cut && <GoLink onClick={() => setEveryUrgent(true)}>{`Show all ${held.length}`}</GoLink>}
              </section>
            );
          })
        ) : (
          <Table items={items} all={items} now={now} open={open} pick={moveTo} />
        )}
      </div>
      {opened !== undefined && (
        <Inspector title={position(opened.id, items) ?? 'Details'} width={width} close={() => setOpen(undefined)}>
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

/** The tabs across Today, each with how many it holds, as the console's counted tabs are. */
function CountTabs({ chosen, counts, choose }: { chosen: TodayTab; counts: Record<TodayTab, readonly TodayItem[]>; choose: (tab: TodayTab) => void }) {
  return (
    <div role="tablist" aria-label="Today" className="flex flex-wrap gap-1 border-b border-panel-edge">
      {TODAY_TABS.map((tab) => {
        const on = tab === chosen;
        return (
          <button
            key={tab}
            type="button"
            role="tab"
            aria-selected={on}
            onClick={() => choose(tab)}
            className={`mx-focus -mb-px flex h-9 cursor-pointer items-center gap-2 border-b-2 px-3 text-body-sm ${on ? 'border-primary font-medium text-foreground' : 'border-transparent text-muted hover:text-foreground'}`}
          >
            {TODAY_TAB_TITLE[tab]}
            <span className="rounded-full bg-hover px-1.5 text-label font-medium tabular-nums text-muted">{counts[tab].length}</span>
          </button>
        );
      })}
    </div>
  );
}

/** The numbered table: what, with its muted line under it, who it is from, how long ago, and its state. */
function Table({ items, all, now, open, pick }: { items: readonly TodayItem[]; all: readonly TodayItem[]; now: number; open: string | undefined; pick: (id: string) => void }) {
  return (
    <div className="overflow-hidden rounded-xl border border-panel-edge bg-card">
      <div className="grid grid-cols-[2rem_minmax(0,1fr)_9rem_4.5rem_6.5rem] gap-3 border-b border-panel-edge px-4 py-2 text-label font-medium tracking-[0.14em] text-faint uppercase max-[639px]:hidden">
        <span />
        <span>What</span>
        <span>From</span>
        <span>When</span>
        <span>State</span>
      </div>
      <div className="divide-y divide-panel-edge">
        {items.map((item) => {
          const number = all.findIndex((each) => each.id === item.id) + 1;
          const line = under(item);
          const chosen = item.id === open;
          return (
            <button
              key={item.id}
              type="button"
              aria-pressed={chosen}
              aria-label={`${number}. ${item.title}, from ${item.agentName}, ${TODAY_STATE_LABEL[item.state]}`}
              onClick={() => pick(item.id)}
              className={`mx-focus grid w-full cursor-pointer grid-cols-[2rem_minmax(0,1fr)_9rem_4.5rem_6.5rem] items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-hover max-[639px]:grid-cols-[2rem_minmax(0,1fr)] ${chosen ? 'bg-active' : ''}`}
            >
              <span className="font-code text-label text-faint">{number}</span>
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="truncate text-body-sm font-medium text-foreground">{item.title}</span>
                {line !== undefined && <span className="truncate text-meta text-muted">{line}</span>}
              </span>
              <span className="flex min-w-0 items-center gap-1.5 max-[639px]:hidden">
                <BrandLogo agent={item.agent ?? 'memnox'} name={item.agentName} size={18} />
                <span className="truncate text-meta text-foreground">{item.agentName}</span>
              </span>
              <span className="font-code text-label text-muted max-[639px]:hidden">{age(item.since, now) ?? ''}</span>
              <span className="max-[639px]:hidden">
                <StatusWord tone={STATE_TONE[item.state]}>{TODAY_STATE_LABEL[item.state]}</StatusWord>
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function Empty({ tab, activity }: { tab: TodayTab; activity: boolean }) {
  switch (tab) {
    case 'overview':
      return <EmptyState icon={Sun} title="Nothing needs you today" body="When an agent asks first, stops, or hands back to you, it waits here, the most urgent first." />;
    case 'done':
      return <EmptyState icon={CheckCircle2} title="Nothing done yet today" body="What your agents run today shows here as it goes through, newest first." />;
    case 'handoffs':
      return <EmptyState icon={Undo2} title="Nothing handed back" body="A session that finished its turn and waits on you shows here, with the way back into it." />;
    case 'log':
      return (
        <EmptyState
          icon={ListChecks}
          title="Nothing in today's record"
          body={activity ? 'Every action your agents take today is written here with what your rules decided.' : "This computer's runtime does not answer activity yet, so today's record cannot be read."}
        />
      );
  }
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
  const facts: [string, string][] = [
    ['From', item.agentName],
    ['Waiting', waited(item.since, now)],
  ];
  if (item.detail !== undefined) facts.push(['About', item.detail]);
  if (item.kind.kind === 'held' && card !== undefined) facts.push(['Signed', signedLine(card, keyTitle)]);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-1.5">
        <StepButton label="The item above" disabled={first} onClick={() => move(-1)} up />
        <StepButton label="The item below" disabled={last} onClick={() => move(1)} />
        <span className="flex-1" />
        <span className="text-label text-faint">Up and Down move, a letter decides, Escape closes</span>
      </div>
      <h3 className="text-lg font-semibold break-words text-foreground select-text">{item.title}</h3>
      <span>
        <StatusWord tone={STATE_TONE[item.state]}>{TODAY_STATE_LABEL[item.state]}</StatusWord>
      </span>
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-body-sm">
        {facts.map(([name, value]) => (
          <div key={name} className="contents">
            <dt className="text-muted">{name}</dt>
            <dd className="min-w-0 break-words text-foreground">{value}</dd>
          </div>
        ))}
      </dl>
      <Block title="RECOMMENDATION">
        <p className={`text-body-sm ${item.recommendation === undefined ? 'text-muted' : 'text-foreground'}`}>{item.recommendation ?? NO_RECOMMENDATION}</p>
      </Block>
      <Block title="DECIDE">
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
  const Icon = up ? ChevronUp : ChevronDown;
  return (
    <button type="button" aria-label={label} title={label} disabled={disabled} onClick={onClick} className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover disabled:cursor-default disabled:opacity-35">
      <Icon size={14} strokeWidth={2.4} />
    </button>
  );
}

/** One choice: its letter on a key, its words, the key that signs where the allow is signed, and the recommendation marked. */
function ChoiceRow({ choice, signed, keyTitle, disabled, press }: { choice: TodayChoice; signed: boolean; keyTitle: string; disabled: boolean; press: () => void }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={press}
      title={`Press ${choice.key}`}
      aria-label={`${choice.title}${choice.recommended ? ', recommended' : ''}${signed ? `, signed with ${keyTitle}` : ''}`}
      className={`mx-focus flex h-9 cursor-pointer items-center gap-2.5 rounded-md border bg-card px-2.5 text-left hover:bg-hover disabled:cursor-default disabled:opacity-50 ${choice.recommended ? 'border-primary' : 'border-panel-edge'}`}
    >
      <span className="grid size-[22px] place-items-center rounded-md border border-panel-edge bg-keycap font-code text-label font-medium text-muted">{choice.key}</span>
      <span className="text-body-sm font-medium text-foreground">{choice.title}</span>
      {signed && <Fingerprint size={14} className="text-muted" aria-hidden />}
      <span className="flex-1" />
      {choice.recommended && <StatusWord tone="good">Recommended</StatusWord>}
    </button>
  );
}

/** How a yes to this call is signed, as the Approvals page says it. */
function signedLine(card: HeldCard, keyTitle: string): string {
  if (!card.touchID) return 'Inside its own repository, so a yes needs no signature';
  if (card.actionDigest === undefined) return `A yes is signed with ${keyTitle}`;
  return `A yes is signed with ${keyTitle} over exactly this call, so one changed since is refused`;
}

function outcomeNote(outcome: HeldOutcome): string {
  switch (outcome.kind) {
    case 'answered':
      return 'Answered.';
    case 'answered-elsewhere':
      return 'Somebody answered this first, and that answer stands.';
    case 'cancelled':
      return 'Nothing was sent, so it still waits.';
    case 'failed':
      return outcome.why;
  }
}
