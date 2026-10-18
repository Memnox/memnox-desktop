import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { wentIn, type CardExcerpt, type ConversationLine, type DisplayHost, type SessionView, type SessionViewStep } from '@memnox/core/wire';
import { ChevronRight, Hand, ListCollapse, MessagesSquare, Users } from 'lucide-react';
import {
  ago,
  diffLines,
  fileName,
  folderOf,
  meaningful,
  repositoryName,
  statusLabel,
  statusTint,
  stepLine,
  totals,
  viewStatus,
  type DiffLine,
  type HeldCalls,
  type HeldCard,
  type Sessions,
  type Shown,
} from '../../core';
import { openWords } from '../../core/domain/floating-cards';
import { BrandLogo, SFSymbol } from '../kit';
import { tinted } from './parts';
import { CardButton, CardHeader, HeldStrip, PRESS_DOWN } from './window-kit';
import './sessions.css';

/**
 * The live window on one session, the web twin of the Mac's `LiveSession`: who and where with how it
 * stands, what it was asked and is doing now, and three tabs, the conversation, the changes with their
 * real diffs, and every step, read again every two seconds while it is open.
 */

/** Read this often while the window is open, as the Mac's live window reads. */
const REFRESH_MS = 2_000;
const META_SEPARATOR = '  ·  ';

type LiveTab = 'conversation' | 'changes' | 'activity';

/** The tab with the most to say: the conversation where there is one, else the changes, else the steps. */
function firstTab(view: SessionView): LiveTab {
  if ((view.conversation ?? []).length > 0) return 'conversation';
  if (view.files.length > 0) return 'changes';
  return 'activity';
}

export function LiveSession({
  sessionId,
  sessions,
  calls,
  onClose,
  onOpenFolder,
  onOpenApp,
  now: fixedNow,
  initial,
}: {
  sessionId: string;
  sessions: Sessions;
  calls?: HeldCalls;
  onClose: () => void;
  /** Where its folder is known, the footer opens it in the file manager. */
  onOpenFolder?: (path: string) => void;
  /** "Open in {app}": its own tab or editor brought forward through that tool's own controls, answered with why when it could not be. */
  onOpenApp?: (host: DisplayHost) => Promise<Shown>;
  now?: number;
  /** A view to start from, as the preview gives one with no daemon behind it. */
  initial?: SessionView;
}) {
  const [view, setView] = useState<SessionView | undefined>(initial);
  const [host, setHost] = useState<DisplayHost>();
  /** Why its app did not come forward, shown in the footer until another session is read. */
  const [notOpened, setNotOpened] = useState<string>();
  const folder = host?.cwd;
  const [tab, setTab] = useState<LiveTab>();
  const [now, setNow] = useState(fixedNow ?? Date.now());

  useEffect(() => {
    setTab(undefined);
    setNotOpened(undefined);
    if (initial !== undefined) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const read = async () => {
      const next = await sessions.view(sessionId);
      if (stopped) return;
      if (next !== undefined) setView(next);
      if (fixedNow === undefined) setNow(Date.now());
      timer = setTimeout(() => void read(), REFRESH_MS);
    };
    void read();
    void sessions.list().then((cards) => !stopped && setHost(cards.find((card) => card.sessionId === sessionId)?.host));
    return () => {
      stopped = true;
      if (timer !== undefined) clearTimeout(timer);
    };
  }, [sessionId, sessions, initial, fixedNow]);

  // Escape closes it, as the close button's cancel action does.
  useEffect(() => {
    const pressed = (event: KeyboardEvent) => event.key === 'Escape' && onClose();
    window.addEventListener('keydown', pressed);
    return () => window.removeEventListener('keydown', pressed);
  }, [onClose]);

  const held = useHeldFor(calls, sessionId);
  // Offered only where the runtime noted where it runs; the live window stays up either way.
  const openApp =
    onOpenApp === undefined || host === undefined || (host.app === undefined && host.cwd === undefined)
      ? undefined
      : () => {
          setNotOpened(undefined);
          void onOpenApp(host).then((shown) => setNotOpened(wentIn(shown.answer) ? undefined : sentence(shown.reason ?? 'its app would not come forward')));
        };

  if (view === undefined) {
    return (
      <Surface colour={statusTint('quiet')}>
        <CardHeader mark={<SFSymbol name="circle" size={14} />} title="Reading the session" onClose={onClose} />
      </Surface>
    );
  }
  const status = viewStatus(view);
  const colour = statusTint(status);
  const shown = tab ?? firstTab(view);
  const repository = repositoryName(view.repository);
  const since = ago(view.lastActive, now);
  const meta = [repository === undefined ? undefined : view.branch === undefined ? repository : `${repository} on ${view.branch}`, view.runningIn, since === undefined ? undefined : `active ${since}`]
    .filter((part): part is string => part !== undefined)
    .join(META_SEPARATOR);

  return (
    <Surface colour={colour}>
      <Part order={0}>
        <CardHeader
          mark={<BrandLogo agent={view.agent} name={view.agentName} size={28} />}
          title={view.agentName}
          subtitle={meta === '' ? undefined : meta}
          accessory={<StatePill colour={colour} label={statusLabel(status)} breathing={view.state === 'working'} />}
          onClose={onClose}
        />
      </Part>
      <Part order={1}>
        <Brief view={view} />
      </Part>
      <Part order={2}>
        <NowLine view={view} />
      </Part>
      <Part order={3}>
        <TabBar
          tab={shown}
          onPick={setTab}
          counts={{ conversation: view.conversation?.length ?? 0, changes: view.files.length, activity: view.steps.length }}
        />
      </Part>
      <Part order={4} grow>
        <div className="h-full overflow-y-auto rounded-island border border-ink/[0.035] bg-[var(--mx-section)] p-3 [scrollbar-width:thin]">
          {shown === 'conversation' && <Conversation lines={view.conversation ?? []} thinking={view.thinking} />}
          {shown === 'changes' && <Changes view={view} sessions={sessions} />}
          {shown === 'activity' && <Activity steps={view.steps} helpers={view.helpers} now={now} />}
        </div>
      </Part>
      {held !== undefined && calls !== undefined && (
        <div className="animate-[float-in_460ms_cubic-bezier(0.3,1.1,0.6,1)_both]">
          <HeldStrip calls={calls} card={held} />
        </div>
      )}
      <Part order={5}>
        <div className="flex items-center gap-2">
          {notOpened === undefined ? <span className="flex-1" /> : <span className="min-w-0 flex-1 truncate text-footnote text-muted" title={notOpened}>{notOpened}</span>}
          <CardButton title="Close" symbol="xmark" onPress={onClose} />
          {folder !== undefined && onOpenFolder !== undefined && <CardButton title="Open its folder" symbol="folder" primary={openApp === undefined} onPress={() => onOpenFolder(folder)} />}
          {openApp !== undefined && <CardButton title={openWords(host, 'Open session')} symbol="arrow.up.forward.app" primary onPress={openApp} />}
        </div>
      </Part>
    </Surface>
  );
}

/** A reason as a sentence on its own: capitalised, with a full stop. */
function sentence(reason: string): string {
  const text = reason.trim();
  return text === '' ? text : `${text[0]?.toUpperCase() ?? ''}${text.slice(1)}${/[.!?]$/.test(text) ? '' : '.'}`;
}

/** The first call waiting on this session, docked above the footer. */
function useHeldFor(calls: HeldCalls | undefined, sessionId: string): HeldCard | undefined {
  const [card, setCard] = useState<HeldCard>();
  useEffect(() => {
    if (calls === undefined) return;
    const read = () => setCard(calls.state.waiting.entries.map((entry) => entry.card).find((each) => each.sessionId === sessionId));
    read();
    return calls.observe(read);
  }, [calls, sessionId]);
  return card;
}

/** The window's surface: radius 28 on the page colour, ink 7% rim, and a 3 tall band across the top in its status colour. */
function Surface({ colour, children }: { colour: string; children: ReactNode }) {
  return (
    <div className="relative flex h-screen w-screen animate-[live-in_600ms_cubic-bezier(0.34,1.3,0.64,1)_both] flex-col gap-3.5 overflow-hidden rounded-[28px] border border-ink/[0.07] bg-[var(--mx-page)] p-[22px] font-sans text-foreground">
      <span className="absolute inset-x-0 top-0 h-[3px] transition-colors duration-500" style={{ backgroundColor: colour }} />
      {children}
    </div>
  );
}

/** Each part rises into place a beat after the one above it, as the Mac's `Reveal` staggers them. */
function Part({ order, grow = false, children }: { order: number; grow?: boolean; children: ReactNode }) {
  return (
    <div className={`motion-arrive animate-[live-part-in_550ms_cubic-bezier(0.3,1.15,0.6,1)_both] ${grow ? 'min-h-0 flex-1' : 'shrink-0'}`} style={{ animationDelay: `${180 + order * 70}ms` }}>
      {children}
    </div>
  );
}

/** `StatePill`: a 7 dot, breathing while it works, and the label 11 medium, in the status colour on 14% of it. */
function StatePill({ colour, label, breathing }: { colour: string; label: string; breathing: boolean }) {
  return (
    <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full px-[9px] py-[3px] text-caption font-medium" style={{ color: colour, backgroundColor: tinted(colour, 0.14) }}>
      <span className={`size-[7px] rounded-full ${breathing ? 'animate-[state-breathe_1.8s_ease-in-out_infinite]' : ''}`} style={{ backgroundColor: colour }} />
      {label}
    </span>
  );
}

/** What it was asked, the follow up it is on now, and whether a call waits on the person. */
function Brief({ view }: { view: SessionView }) {
  const task = view.task;
  const followUp = view.lastAsk !== undefined && view.lastAsk !== task ? view.lastAsk : undefined;
  return (
    <div className="flex flex-col gap-2.5">
      {task !== undefined && (
        <div className="flex flex-col gap-1">
          <span className="text-micro font-semibold uppercase tracking-[0.8px] text-ink/45">Asked</span>
          <p className="m-0 line-clamp-3 text-callout font-medium text-foreground">{task}</p>
        </div>
      )}
      {followUp !== undefined && (
        <div className="flex gap-2.5">
          <span className="w-0.5 shrink-0 rounded-full bg-primary" />
          <div className="flex flex-col gap-1">
            <span className="flex items-center gap-1 text-micro font-semibold text-primary">
              <SFSymbol name="arrow.turn.down.right" size={10} weight="semibold" />
              Follow-up, on it now
            </span>
            <p className="m-0 line-clamp-3 text-body text-foreground/[0.92]">{followUp}</p>
          </div>
        </div>
      )}
      {view.waitingOnYou > 0 && (
        <span className="flex items-center gap-1.5 text-footnote font-semibold text-warm">
          <Hand size={12} strokeWidth={2.25} fill="currentColor" />
          {view.waitingOnYou === 1 ? 'One call is waiting on you' : `${view.waitingOnYou} calls are waiting on you`}
        </span>
      )}
    </div>
  );
}

/** `LiveNow`: the one line that says what it is doing this moment. */
function NowLine({ view }: { view: SessionView }) {
  const latest = view.steps[view.steps.length - 1];
  const line =
    view.paused !== undefined ? `Paused: ${view.paused}` : view.thinking ? 'Thinking through its answer' : latest !== undefined ? stepLine(latest) : 'Nothing recorded yet';
  return (
    <div className="flex items-center gap-2 rounded-island border border-ink/[0.035] bg-[var(--mx-section)] px-3.5 py-[11px]">
      <span className="grid shrink-0 text-primary">
        <SFSymbol name={view.thinking ? 'sparkles' : 'arrow.right.circle'} size={13} />
      </span>
      <span className="truncate text-body font-medium text-foreground">{line}</span>
    </div>
  );
}

const TABS: { id: LiveTab; title: string; icon: ReactNode }[] = [
  { id: 'conversation', title: 'Conversation', icon: <MessagesSquare size={12} strokeWidth={2} /> },
  { id: 'changes', title: 'Changes', icon: <SFSymbol name="plusminus" size={12} /> },
  { id: 'activity', title: 'Activity', icon: <ListCollapse size={12} strokeWidth={2} /> },
];

/** `LiveTabBar`: one capsule track of ink 6%, the picked tab on a capsule of ink 12% sliding between them. */
function TabBar({ tab, onPick, counts }: { tab: LiveTab; onPick: (tab: LiveTab) => void; counts: Record<LiveTab, number> }) {
  const index = TABS.findIndex((each) => each.id === tab);
  return (
    <div className="relative flex h-[30px] rounded-full bg-ink/[0.06] p-[3px]">
      <span
        className="absolute inset-y-[3px] rounded-full bg-ink/[0.12] transition-[left] duration-[350ms] ease-snappy"
        style={{ width: `calc((100% - 6px) / ${TABS.length})`, left: `calc(3px + ${index} * (100% - 6px) / ${TABS.length})` }}
      />
      {TABS.map((each) => (
        <button
          key={each.id}
          type="button"
          className={`relative z-10 flex flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-full text-footnote ${each.id === tab ? 'font-semibold text-foreground' : 'font-medium text-muted'}`}
          onClick={() => onPick(each.id)}
          aria-pressed={each.id === tab}
        >
          {each.icon}
          {each.title}
          <span className="tabular text-ink/50">{counts[each.id]}</span>
        </button>
      ))}
    </div>
  );
}

/** The person's lines on the right in blue, the agent's as text, a tool as one quiet mono line. */
function Conversation({ lines, thinking }: { lines: readonly ConversationLine[]; thinking: boolean }) {
  if (lines.length === 0) {
    return <p className="m-0 text-body text-muted">This agent keeps no transcript Memnox can read, so its steps and changes tell the story.</p>;
  }
  let asked = false;
  return (
    <div className="flex select-text flex-col gap-3">
      {lines.map((line, index) => {
        if (line.who === 'person') {
          const label = asked ? 'Follow-up' : 'You asked';
          asked = true;
          return (
            <div key={index} className="flex flex-col items-end gap-1 pl-14">
              <span className={`text-micro font-semibold ${label === 'You asked' ? 'text-muted' : 'text-primary'}`}>{label}</span>
              <span className="rounded-[14px] px-2.5 py-1.5 text-body text-foreground" style={{ backgroundColor: 'rgb(59 130 247 / 0.28)' }}>
                {line.text}
              </span>
            </div>
          );
        }
        if (line.who === 'tool') {
          return (
            <span key={index} className="flex min-w-0 items-center gap-1.5 pl-1 font-mono text-caption text-muted">
              <SFSymbol name="gearshape" size={11} />
              <span className="truncate">{line.text}</span>
            </span>
          );
        }
        return (
          <p key={index} className="m-0 whitespace-pre-wrap text-body leading-[19px] text-foreground/[0.92]">
            {line.text}
          </p>
        );
      })}
      {thinking && <span className="animate-caret text-footnote text-muted">Thinking{'…'}</span>}
    </div>
  );
}

/** Every file it changed with its counts; a file opens into its real diff, read from the daemon when opened. */
function Changes({ view, sessions }: { view: SessionView; sessions: Sessions }) {
  const sum = totals(view.files);
  const [open, setOpen] = useState<string>();
  if (view.files.length === 0) return <p className="m-0 text-body text-muted">No files changed yet.</p>;
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-2 px-1 pb-1">
        <span className="text-footnote font-semibold text-foreground">{view.files.length === 1 ? '1 file changed' : `${view.files.length} files changed`}</span>
        <span className="flex-1" />
        <span className="font-mono text-caption font-semibold text-success">+{sum.added}</span>
        <span className={`font-mono text-caption font-semibold ${sum.removed > 0 ? 'text-destructive' : 'text-muted'}`}>
          {'−'}
          {sum.removed}
        </span>
      </div>
      {view.files.map((file) => (
        <FileRow key={file.path} path={file.path} added={file.added} removed={file.removed} open={open === file.path} onToggle={() => setOpen(open === file.path ? undefined : file.path)} sessionId={view.sessionId} sessions={sessions} />
      ))}
    </div>
  );
}

function FileRow({
  path,
  added,
  removed,
  open,
  onToggle,
  sessionId,
  sessions,
}: {
  path: string;
  added?: number;
  removed?: number;
  open: boolean;
  onToggle: () => void;
  sessionId: string;
  sessions: Sessions;
}) {
  const [diff, setDiff] = useState<CardExcerpt | null>();
  useEffect(() => {
    if (!open || diff !== undefined) return;
    void sessions.diff(sessionId, path).then((read) => setDiff(read ?? null));
  }, [open, diff, sessions, sessionId, path]);
  return (
    <div className={`rounded-[10px] ${open ? 'bg-ink/[0.05]' : ''}`}>
      <button type="button" className={`${PRESS_DOWN} flex h-8 w-full min-w-0 items-center gap-2 rounded-[10px] px-2 text-left hover:bg-ink/[0.04]`} onClick={onToggle} title={path}>
        <ChevronRight size={10} strokeWidth={3} className={`shrink-0 text-muted transition-transform duration-200 ${open ? 'rotate-90' : ''}`} />
        <span className="grid shrink-0 text-muted">
          <SFSymbol name="doc.text" size={11} />
        </span>
        <span className="shrink-0 truncate text-footnote font-semibold text-foreground">{fileName(path)}</span>
        <span className="min-w-0 flex-1 truncate text-caption text-muted" style={{ direction: 'rtl', textAlign: 'left' }}>
          <bdi>{folderOf(path)}</bdi>
        </span>
        {added !== undefined && <span className="font-mono text-caption font-semibold text-success">+{added}</span>}
        {removed !== undefined && removed > 0 && (
          <span className="font-mono text-caption font-semibold text-destructive">
            {'−'}
            {removed}
          </span>
        )}
      </button>
      {open && (
        <div className="px-2 pb-2">
          {diff === undefined ? (
            <span className="text-caption text-muted">Reading the diff{'…'}</span>
          ) : diff === null ? (
            <span className="text-caption text-muted">No diff is known for this file.</span>
          ) : (
            <Diff lines={diffLines(diff.lines)} />
          )}
        </div>
      )}
    </div>
  );
}

/** A file's diff: rows 17 tall in 11 mono, both line numbers in 34 wide gutters, added green and removed red at 16%. */
function Diff({ lines }: { lines: readonly DiffLine[] }) {
  return (
    <div className="max-h-[300px] select-text overflow-auto rounded-[8px] bg-ink/[0.03] py-1 font-mono text-caption">
      {lines.map((line, index) =>
        line.kind === 'hunk' ? (
          <div key={index} className="flex h-[17px] items-center px-2 text-primary" style={{ backgroundColor: 'rgb(59 130 247 / 0.06)' }}>
            {line.text === '' ? '⋯' : line.text}
          </div>
        ) : (
          <div
            key={index}
            className="flex h-[17px] items-center whitespace-pre"
            style={{ backgroundColor: line.kind === 'added' ? 'rgb(48 209 88 / 0.16)' : line.kind === 'removed' ? 'rgb(255 69 58 / 0.16)' : undefined }}
          >
            <span className="w-[34px] shrink-0 pr-1 text-right text-ink/35">{line.old ?? ''}</span>
            <span className="w-[34px] shrink-0 pr-1 text-right text-ink/35">{line.new ?? ''}</span>
            <span className="text-foreground">{line.text}</span>
          </div>
        ),
      )}
    </div>
  );
}

/** Every step it took, the latest at the top, and what its helpers are doing. */
function Activity({ steps, helpers, now }: { steps: readonly SessionViewStep[]; helpers: readonly string[]; now: number }) {
  const shown = useMemo(() => [...meaningful(steps)].reverse(), [steps]);
  return (
    <div className="flex flex-col gap-3">
      {helpers.length > 0 && (
        <div className="flex flex-col gap-1">
          <span className="text-footnote font-semibold text-foreground">{helpers.length === 1 ? '1 helper' : `${helpers.length} helpers`}</span>
          {helpers.map((helper, index) => (
            <span key={index} className="flex items-center gap-1.5 text-footnote text-foreground/[0.88]">
              <Users size={12} strokeWidth={2} className="shrink-0 text-muted" />
              <span className="truncate">{helper}</span>
            </span>
          ))}
        </div>
      )}
      <div className="flex flex-col gap-[5px]">
        {shown.length === 0 && <span className="text-body text-muted">Nothing recorded yet.</span>}
        {shown.map((step, index) => (
          <StepRow key={`${step.at}-${index}`} step={step} now={now} />
        ))}
      </div>
    </div>
  );
}

/** One step: its symbol in a 14 column, the line in 12 mono, and how long ago, warm when refused and red when it failed. */
export function StepRow({ step, now }: { step: SessionViewStep; now: number }) {
  const tone = step.refused === true ? 'text-warm' : step.failed === true ? 'text-destructive' : 'text-foreground/[0.88]';
  const symbol = step.surface === 'shell' ? 'terminal' : step.surface === 'filesystem' ? 'doc.text' : step.surface === 'network' ? 'globe' : step.surface === 'mcp' ? 'puzzlepiece.extension' : step.surface === 'git' ? 'arrow.triangle.branch' : 'circle.fill';
  return (
    <div className={`flex min-w-0 items-center gap-2 ${tone}`} title={step.text}>
      <span className="grid w-3.5 shrink-0 place-items-center">
        <SFSymbol name={symbol} size={symbol === 'circle.fill' ? 6 : 11} />
      </span>
      <span className="min-w-0 flex-1 truncate font-mono text-footnote">{stepLine(step)}</span>
      <span className="shrink-0 text-caption text-muted">{ago(step.at, now)}</span>
    </div>
  );
}

