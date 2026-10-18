import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { HOLD_ANSWER, RULE_SCOPE, type RuleDraft, type RuleScope, type WorkDraft } from '@memnox/core/wire';
import { agentColour, FROM_NOW_ON, suggestedScope, type FinishedCard, type HeldAnswer, type HeldCalls, type HeldCard, type HeldOutcome, type ProposalCards, type WaitingCalls } from '../core';
import { ANSWERING_ROW, GlyphButton, IslandButton, IslandCard, MiddleCut, PRESSABLE, PulseDot, SFSymbol, VEIL, veilOf, type SFSymbolName } from './kit';
import { note } from './ui';

/**
 * The island's cards, each the web twin of one Swift view in `Island/IslandCalls.swift`,
 * `IslandRule.swift`, `IslandWorkCard.swift` and `IslandSessionDetail.swift`. Each fills the content
 * inset of its mode: 36 from the top, 10 from the other sides.
 */

/** The content inset every open screen pads its card with, below the header row. */
export const CONTENT_INSET = 'absolute inset-x-2.5 bottom-2.5 top-9';

/** The text column the held and finished cards share, clear of the orb that sits over their left side. */
const CALL_COLUMN = 'flex h-full flex-col justify-center gap-2.5 pl-[98px] pr-[18px]';

/** The system monospaced face, which `.system(design: .monospaced)` always is, rather than DM Mono. */
const SYSTEM_MONO = "font-[ui-monospace,'SF_Mono','Cascadia_Mono','JetBrains_Mono',Consolas,monospace]";

/** What a card says after a failed press, in the person's words; the island shakes beside it. */
export function told(outcome: HeldOutcome): string | undefined {
  switch (outcome.kind) {
    case 'answered':
    case 'answered-elsewhere':
      return undefined;
    case 'cancelled':
      return 'Nothing was sent, so it is still waiting.';
    case 'failed':
      return `That did not go through: ${outcome.why}`;
  }
}

/** The answers on a held call, in the order the Mac lays them out. */
const ANSWER = { deny: HOLD_ANSWER.DENY, session: HOLD_ANSWER.SESSION, once: HOLD_ANSWER.ONCE, always: FROM_NOW_ON } as const;

/**
 * `IslandHeldCall`: who is waiting, the exact command, and the answers. The rim is amber while it waits
 * and green once it was settled elsewhere; the answers dim together while one is being signed.
 */
export function HeldCall({
  calls,
  onPressed,
  onAnswered,
}: {
  calls: HeldCalls;
  /** Before the answer goes, so the voice stops asking about a call answered by hand. */
  onPressed?: (subject: string) => void;
  /** Every press's outcome, for the orb's gesture and the island's shake. */
  onAnswered: (choice: HeldAnswer, outcome: HeldOutcome) => void;
}) {
  const state = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state,
  );
  const [said, setSaid] = useState<string>();
  const shown = state.waiting.shown;
  // Kept through the content fade after the queue let it go, so the leaving card is not blank.
  const last = useRef<HeldCard>();
  if (shown !== undefined) last.current = shown.card;
  const card = shown?.card ?? last.current;
  if (card === undefined) return null;
  const settled = state.settled?.subject === card.subject ? state.settled.note : undefined;
  const busy = state.answering || settled !== undefined;

  async function press(choice: HeldAnswer) {
    if (card === undefined) return;
    setSaid(undefined);
    onPressed?.(card.subject);
    const outcome = await calls.answer(card.subject, choice);
    setSaid(told(outcome));
    onAnswered(choice, outcome);
  }

  return (
    <IslandCard veil={settled === undefined ? VEIL.waiting : VEIL.settled} className={CONTENT_INSET}>
      <div className={CALL_COLUMN}>
        {state.waiting.header !== undefined && <QueueRow waiting={state.waiting} header={state.waiting.header} disabled={busy} step={(by) => calls.step(by)} />}
        <div className="flex min-w-0 items-center gap-2">
          <PulseDot colour={agentColour(card.agent)} />
          <span className="shrink-0 truncate text-callout font-semibold text-white">{card.who}</span>
          {settled !== undefined ? (
            <span className="flex min-w-0 items-center gap-1.5 text-body text-green">
              <SFSymbol name="checkmark.circle.fill" size={13} />
              <span className="truncate">{settled}</span>
            </span>
          ) : (
            <span className="min-w-0 truncate text-body text-white/[0.62]">{card.why ?? 'is waiting on you'}</span>
          )}
        </div>
        {/* Cut in the middle to fit, so the whole command is one hover away before anything is allowed. */}
        <MiddleCut text={card.what} className={`max-w-full self-start overflow-hidden rounded-command border border-white/[0.08] bg-white/[0.06] px-3 py-2 ${SYSTEM_MONO} text-body text-white`} />
        <div className={`flex items-center gap-2 ${busy ? ANSWERING_ROW : ''}`} aria-disabled={busy}>
          <IslandButton inRow disabled={busy} onClick={() => void press(ANSWER.deny)}>
            Deny
          </IslandButton>
          <IslandButton inRow disabled={busy} symbol={card.touchID ? 'touchid' : undefined} onClick={() => void press(ANSWER.session)}>
            Allow this session
          </IslandButton>
          <IslandButton kind="primary" inRow disabled={busy} symbol={card.touchID ? 'touchid' : undefined} onClick={() => void press(ANSWER.once)}>
            Allow once
          </IslandButton>
          {/* The answer that leaves a rule behind waits behind More, as on every other door. */}
          <MoreAnswers disabled={busy} items={[{ label: 'Allow from now on', symbol: 'touchid', choose: () => void press(ANSWER.always) }]} />
        </div>
        {said !== undefined && (
          <p className={`${note} -mt-1 mb-0`}>
            <SFSymbol name="exclamationmark.triangle.fill" size={11} /> {said}
          </p>
        )}
      </div>
    </IslandCard>
  );
}

/** How many wait and where, with the way to step through them, so a second call is never hidden behind the first. */
function QueueRow({ waiting, header, disabled, step }: { waiting: WaitingCalls<HeldCard>; header: string; disabled: boolean; step: (by: number) => void }) {
  return (
    <div className="flex items-center gap-1.5 text-white">
      <span className="min-w-0 truncate text-footnote font-medium text-amber">{header}</span>
      <span className="min-w-1.5 flex-1" />
      <GlyphButton symbol="chevron.left" label="An older call" disabled={disabled || !waiting.canStepOlder} onPress={() => step(1)} />
      {waiting.positionText !== undefined && <span className="tabular whitespace-nowrap text-footnote text-white/[0.62]">{waiting.positionText}</span>}
      <GlyphButton symbol="chevron.right" label="A newer call" disabled={disabled || !waiting.canStepNewer} onPress={() => step(-1)} />
    </div>
  );
}

/**
 * A borderless menu showing only an ellipsis, as `.menuStyle(.borderlessButton)` with its indicator
 * hidden. It opens upward over the card, since the island's window ends just below the held card.
 */
function MoreAnswers({ items, disabled }: { items: { label: string; symbol?: SFSymbolName; choose: () => void }[]; disabled: boolean }) {
  const [open, setOpen] = useState(false);
  const holder = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const away = (event: PointerEvent) => {
      if (!holder.current?.contains(event.target as Node)) setOpen(false);
    };
    const escape = (event: KeyboardEvent) => event.key === 'Escape' && setOpen(false);
    window.addEventListener('pointerdown', away);
    window.addEventListener('keydown', escape);
    return () => {
      window.removeEventListener('pointerdown', away);
      window.removeEventListener('keydown', escape);
    };
  }, [open]);
  return (
    <div ref={holder} className="relative">
      <button type="button" className={`${PRESSABLE} grid h-[29px] place-items-center px-1 text-white`} disabled={disabled} onClick={() => setOpen(!open)} aria-label="More answers" aria-expanded={open}>
        <SFSymbol name="ellipsis" size={13} />
      </button>
      {open && (
        <div role="menu" className="absolute bottom-full right-0 z-10 mb-1 min-w-max animate-[fade-in_120ms_ease-out] rounded-control border border-white/[0.14] bg-[#2a2a2c]/95 p-[5px] shadow-[0_8px_24px_rgb(0_0_0/0.5)] backdrop-blur-xl">
          {items.map((item) => (
            <button
              key={item.label}
              role="menuitem"
              type="button"
              className="flex w-full cursor-pointer items-center gap-1.5 rounded-key px-2 py-[3px] text-left text-body text-white hover:bg-primary"
              onClick={() => {
                setOpen(false);
                item.choose();
              }}
            >
              {item.symbol !== undefined && <SFSymbol name={item.symbol} size={13} />}
              {item.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** `IslandFinished`: who finished and what they did, with a way back to it. It stays 5.2 s and the island hops. */
export function Finished({ card, onOpen, onDone }: { card: FinishedCard; onOpen?: () => void; onDone: () => void }) {
  return (
    <IslandCard veil={VEIL.finished} className={CONTENT_INSET}>
      <div className={CALL_COLUMN}>
        <div className="flex min-w-0 items-center gap-2">
          <span className="grid text-green">
            <SFSymbol name="checkmark.circle.fill" size={13} />
          </span>
          <span className="truncate text-callout font-semibold text-white">{card.who}</span>
          <span className="text-body text-white/[0.62]">finished</span>
        </div>
        <p className="m-0 line-clamp-2 text-body text-island-soft">{card.summary}</p>
        <div className="flex items-center gap-2">
          {card.sessionId !== undefined && onOpen !== undefined && <IslandButton onClick={onOpen}>Open</IslandButton>}
          <IslandButton kind="primary" onClick={onDone}>
            OK
          </IslandButton>
        </div>
      </div>
    </IslandCard>
  );
}

/** `IslandEmpty`: opened with nothing running, and the one thing to do from here. */
export function Empty({ onTalk, talkDisabled = false }: { onTalk: () => void; talkDisabled?: boolean }) {
  return (
    <IslandCard veil={VEIL.empty} className={CONTENT_INSET}>
      <div className="flex h-full flex-col items-start justify-center gap-3 pl-[112px]">
        <p className="m-0 text-headline font-medium text-white">Nothing is running right now.</p>
        <IslandButton kind="primary" symbol="waveform" symbolSize={12.5} disabled={talkDisabled} onClick={onTalk}>
          Talk to Memnox
        </IslandButton>
      </div>
    </IslandCard>
  );
}

/** The newest proposal waiting on its card, read whole before the key is asked. */
export function ProposalCard({ cards, onAnswered }: { cards: ProposalCards; onAnswered: (outcome: HeldOutcome) => void }) {
  const all = useSyncExternalStore(
    (changed) => cards.observe(changed),
    () => cards.cards,
  );
  const card = all[all.length - 1];
  if (card === undefined) return null;
  // Keyed by subject, so a new card never inherits the last one's choice or edits.
  return card.kind === 'rule' ? (
    <RuleCard key={card.subject} subject={card.subject} rule={card.rule} cards={cards} onAnswered={onAnswered} />
  ) : (
    <WorkCard key={card.subject} subject={card.subject} work={card.work} cards={cards} onAnswered={onAnswered} />
  );
}

/** Each effect's tint, its lifted label colour and its word, as `IslandRuleCard` colours them. */
const EFFECT: Record<string, { tint: string; lifted: string; word: string }> = {
  deny: { tint: '#FF453A', lifted: '#FF746B', word: 'Deny' },
  ask: { tint: '#FF9F0A', lifted: '#FFB747', word: 'Ask first' },
  allow: { tint: '#30D158', lifted: '#64DD82', word: 'Allow' },
};
const UNKNOWN_EFFECT = { tint: '#6366F1', lifted: '#8A8CF5' };

/** "on this computer", "in shop" or "for the team", the way the button says where a rule holds. */
function placeWords(scope: RuleScope): string {
  if (scope.kind === RULE_SCOPE.REPOSITORY) return `in ${scope.label}`;
  if (scope.kind === RULE_SCOPE.TEAM) return 'for the team';
  return 'on this computer';
}

/** The signing button's words: a team rule is proposed rather than enforced, since a second admin decides. */
function enforceWords(scope: RuleScope): string {
  return scope.kind === RULE_SCOPE.TEAM ? 'Propose for the team' : `Enforce ${placeWords(scope)}`;
}

const sentence = (text: string): string => text.charAt(0).toUpperCase() + text.slice(1);

/** `IslandRuleCard`: what the rule does, why, where it could hold, and the signed answer. */
function RuleCard({ subject, rule, cards, onAnswered }: { subject: string; rule: RuleDraft; cards: ProposalCards; onAnswered: (outcome: HeldOutcome) => void }) {
  const [scope, setScope] = useState(suggestedScope(rule)?.id);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string>();
  const effect = EFFECT[rule.effect];
  const tint = effect?.tint ?? UNKNOWN_EFFECT.tint;
  const picked = rule.scopes.find((each) => each.id === scope);

  async function answer(scopeId: string | undefined) {
    setBusy(scopeId !== undefined);
    const outcome = await cards.answerRule(subject, scopeId);
    setSaid(told(outcome));
    setBusy(false);
    onAnswered(outcome);
  }

  const details: [string, string, boolean][] = [['Action', rule.action, true]];
  if (rule.branches !== undefined && rule.branches.length > 0) details.push(['Branches', rule.branches.join(', '), true]);
  if (rule.targets !== undefined && rule.targets.length > 0) details.push(['Paths', rule.targets.join(', '), true]);
  details.push(['Why', rule.reason, false]);

  return (
    <IslandCard veil={veilOf(tint, 0.3)} className={`${CONTENT_INSET} flex animate-card-in flex-col gap-2.5 p-3.5`}>
      <div className="flex items-center gap-2">
        <span className="grid" style={{ color: tint }}>
          <SFSymbol name="shield.lefthalf.filled" size={13} />
        </span>
        <span className="text-callout font-semibold text-white">New rule</span>
        <span className="flex-1" />
        <span className="rounded-full px-2.5 py-1 text-footnote font-semibold" style={{ color: effect?.lifted ?? UNKNOWN_EFFECT.lifted, backgroundColor: veilOf(tint, 0.2) }}>
          {effect?.word ?? rule.effect}
        </span>
      </div>
      <p className="m-0 line-clamp-2 text-headline font-semibold text-white">{sentence(rule.summary)}</p>
      <dl className="m-0 grid grid-cols-[70px_1fr] gap-x-2 gap-y-1 text-button">
        {details.map(([label, value, code]) => (
          <div key={label} className="contents">
            <dt className="text-white/[0.62]">{label}</dt>
            <dd className={`m-0 line-clamp-2 text-island-soft ${code ? SYSTEM_MONO : ''}`}>{value}</dd>
          </div>
        ))}
      </dl>
      <p className="m-0 text-footnote font-semibold text-white/50">Where should it hold?</p>
      <div className="grid max-h-[138px] gap-1 overflow-y-auto" role="radiogroup" aria-label="Where should it hold?">
        {rule.scopes.map((each) => (
          <PlaceRow key={each.id} scope={each} picked={scope === each.id} pick={() => setScope(each.id)} />
        ))}
      </div>
      <span className="flex-1" />
      <div className={`flex items-center gap-2 ${busy ? ANSWERING_ROW : ''}`}>
        <IslandButton inRow disabled={busy} onClick={() => void answer(undefined)}>
          Not now
        </IslandButton>
        <span className="flex-1" />
        <IslandButton kind="primary" symbol="touchid" disabled={busy || picked === undefined} onClick={() => void answer(scope)}>
          <span className="truncate">{picked === undefined ? 'Enforce' : enforceWords(picked)}</span>
        </IslandButton>
      </div>
      {said !== undefined && <p className={`${note} m-0`}>{said}</p>}
    </IslandCard>
  );
}

/** What each kind of place a rule holds is drawn with, and what holding there means. */
function placeLook(scope: RuleScope): { symbol: SFSymbolName; detail: string } {
  if (scope.kind === RULE_SCOPE.TEAM) return { symbol: 'person.3', detail: 'Every agent the team runs, cloud ones too, once an admin approves' };
  if (scope.kind === RULE_SCOPE.REPOSITORY && scope.folder !== undefined) return { symbol: 'folder', detail: `Only agents in ${scope.folder}` };
  if (scope.kind === RULE_SCOPE.REPOSITORY) return { symbol: 'folder', detail: `Only agents in ${scope.label}` };
  return { symbol: 'desktopcomputer', detail: 'Every agent, in every folder' };
}

/** One place a rule can hold, picked with a blue ring and a filled check. */
function PlaceRow({ scope, picked, pick }: { scope: RuleScope; picked: boolean; pick: () => void }) {
  const look = placeLook(scope);
  return (
    <button
      type="button"
      role="radio"
      aria-checked={picked}
      onClick={pick}
      className={`${PRESSABLE} flex items-center gap-2.5 rounded-card border px-2.5 py-[7px] text-left ${picked ? 'border-primary/55 bg-white/[0.14]' : 'border-transparent hover:bg-white/[0.06]'}`}
    >
      <span className="grid w-[18px] shrink-0 place-items-center text-white/[0.62]">
        <SFSymbol name={look.symbol} size={13} />
      </span>
      <span className="grid min-w-0 flex-1 gap-0.5">
        <span className="text-body font-semibold text-white">{scope.label}</span>
        <span className="min-w-0 overflow-hidden">
          <MiddleCut text={look.detail} className="block text-caption text-quiet" />
        </span>
      </span>
      <span className={`grid ${picked ? 'text-primary' : 'text-white/50'}`}>
        <SFSymbol name={picked ? 'checkmark.circle.fill' : 'circle'} size={13} />
      </span>
    </button>
  );
}

/** Each tool's colour and the word on its own send button, as `ToolBrand` has them. */
const TOOL_BRAND: Record<string, { colour: string; send: string; name: string }> = {
  slack: { colour: '#4A154B', send: 'Send', name: 'Slack' },
  github: { colour: '#238636', send: 'Comment', name: 'GitHub' },
  linear: { colour: '#5E6AD2', send: 'Comment', name: 'Linear' },
  gmail: { colour: '#EA4335', send: 'Send', name: 'Gmail' },
  googledocs: { colour: '#4285F4', send: 'Save', name: 'Google Docs' },
  notion: { colour: '#2F3437', send: 'Save', name: 'Notion' },
};
/** A tool with no look of its own is drawn in the Memnox blue, so it is never mistaken for one that has. */
const FALLBACK_BRAND = { colour: '#1E86EE', send: 'Send' };

const KIND_WORD: Record<WorkDraft['kind'], string> = {
  message: 'Message',
  comment: 'Comment',
  email: 'Email',
  issue: 'Issue',
  other: 'Action',
};

function brandOf(toolkit: string): { colour: string; send: string; name: string } {
  const known = TOOL_BRAND[toolkit];
  if (known !== undefined) return known;
  return { ...FALLBACK_BRAND, name: toolkit.charAt(0).toUpperCase() + toolkit.slice(1) };
}

/** `ToolMark`: the tool's tile, 22 square at radius 5.7, in its brand colour with its initial standing in for its logo. */
function ToolMark({ toolkit, side = 22 }: { toolkit: string; side?: number }) {
  const brand = brandOf(toolkit);
  return (
    <span className="grid shrink-0 place-items-center text-[11px] font-bold text-white" style={{ width: side, height: side, borderRadius: side * 0.26, backgroundColor: brand.colour }} aria-hidden>
      {brand.name.charAt(0)}
    </span>
  );
}

/**
 * `IslandWorkCard`: something about to go out in the person's name, whole, with the words theirs to
 * rewrite. The logo and the Send pill carry the brand, so the rim stays the plain one.
 */
function WorkCard({ subject, work, cards, onAnswered }: { subject: string; work: WorkDraft; cards: ProposalCards; onAnswered: (outcome: HeldOutcome) => void }) {
  const drafted = work.body ?? '';
  const [body, setBody] = useState(drafted);
  const [sending, setSending] = useState(false);
  const [said, setSaid] = useState<string>();
  const brand = brandOf(work.toolkit);
  const empty = work.body !== undefined && body.trim() === '';
  const changed = work.body !== undefined && body !== drafted;
  const footnote = sending ? 'Waiting for your fingerprint' : empty ? 'Write something to send.' : changed ? 'Your words go out as you wrote them.' : 'Nothing goes out until you send it.';
  const who = work.account?.name ?? work.account?.handle;

  async function answer(send: boolean) {
    setSending(send);
    // Words go with the Send only when the person changed them, so the signature covers what really leaves.
    const outcome = await cards.answerDraft(subject, send, send && changed ? body : undefined);
    setSaid(told(outcome));
    setSending(false);
    onAnswered(outcome);
  }

  return (
    <IslandCard
      className={`${CONTENT_INSET} flex animate-card-in flex-col gap-2.5 p-3.5`}
      // Control and Enter sends from the box, as Command Return does on the Mac.
      onKeyDown={(event) => {
        if (event.key === 'Enter' && event.ctrlKey && !empty && !sending) void answer(true);
      }}
    >
      <div className="flex items-center gap-2">
        <ToolMark toolkit={work.toolkit} />
        <span className="truncate text-callout font-semibold text-white">
          {KIND_WORD[work.kind]} on {brand.name}
        </span>
        <span className="flex-1" />
        <button type="button" className={`${PRESSABLE} grid size-6 place-items-center rounded-full bg-white/10 text-white/[0.92]`} disabled={sending} onClick={() => void answer(false)} title="Close without sending" aria-label="Close without sending">
          <SFSymbol name="xmark" size={12} weight="bold" />
        </button>
      </div>
      <div className="flex items-center gap-1.5 text-caption font-medium">
        <span className="text-footnote font-medium text-white/[0.92]">{who === undefined ? 'As you' : `As ${who}`}</span>
        {work.account?.check === 'matched' ? (
          <span className="grid text-green" aria-label="your account">
            <SFSymbol name="checkmark.seal.fill" size={11} />
          </span>
        ) : (
          <span className="flex items-center gap-1 text-amber">
            <SFSymbol name="exclamationmark.triangle.fill" size={11} /> not tied to you, check the name
          </span>
        )}
      </div>
      <hr className="m-0 h-px shrink-0 border-0 bg-white/[0.07]" />
      <div className="grid min-h-0 flex-1 content-start gap-2.5 overflow-y-auto">
        {work.to !== undefined && work.to.length > 0 && (
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-body text-white/[0.62]">To</span>
            {work.to.slice(0, 3).map((each) => (
              <span key={each} className="rounded-full bg-white/10 px-2.5 py-1 text-body font-medium text-white">
                {each}
              </span>
            ))}
            {work.to.length > 3 && <span className="text-body text-white/[0.62]">and {work.to.length - 3} more</span>}
          </div>
        )}
        {work.where !== undefined && (
          <p className={`m-0 flex items-center gap-1.5 ${SYSTEM_MONO} text-footnote font-medium text-white/[0.62]`}>
            <SFSymbol name="arrow.turn.down.right" size={12} /> {work.where}
          </p>
        )}
        {work.subject !== undefined && <p className="m-0 text-callout font-semibold text-white">{work.subject}</p>}
        {work.body !== undefined && (
          <textarea
            className="max-h-[180px] min-h-[72px] w-full resize-none rounded-lg border-0 bg-white/10 p-1.5 font-sans text-callout leading-[21px] text-white outline-none"
            value={body}
            onChange={(event) => setBody(event.target.value)}
            // The island never takes the keyboard on its own, so it asks for it while the draft is being rewritten.
            onPointerDown={() => void invoke('island_keyboard', { on: true }).catch(() => undefined)}
            onBlur={() => void invoke('island_keyboard', { on: false }).catch(() => undefined)}
          />
        )}
        {work.fields.length > 0 && (
          <div className="grid gap-1">
            <p className="m-0 text-caption font-semibold text-white/[0.62]">Also sends</p>
            <dl className={`m-0 grid grid-cols-[96px_1fr] gap-x-2 gap-y-0.5 ${SYSTEM_MONO} text-caption`}>
              {work.fields.map((field) => (
                <div key={field.name} className="contents">
                  <dt className="truncate text-white/[0.62]">{field.name}</dt>
                  <dd className="m-0 text-white/[0.92] [overflow-wrap:anywhere]">{field.value}</dd>
                </div>
              ))}
            </dl>
          </div>
        )}
      </div>
      <div className={`flex items-center gap-2 ${sending ? ANSWERING_ROW : ''}`}>
        <span key={said ?? footnote} className="line-clamp-2 animate-[fade-in_200ms_ease-out] text-caption text-white/[0.62]">
          {said ?? footnote}
        </span>
        <span className="flex-1" />
        <button
          type="button"
          className={`${PRESSABLE} inline-flex shrink-0 items-center gap-1.5 rounded-full px-4 py-2 text-callout font-semibold text-white disabled:opacity-40`}
          style={{ backgroundColor: brand.colour, boxShadow: 'inset 0 0 0 1px rgb(255 255 255 / 0.14)' }}
          disabled={empty || sending}
          onClick={() => void answer(true)}
          title={empty ? 'Write something to send' : 'Send with your fingerprint'}
        >
          <SFSymbol name="touchid" size={14} />
          {brand.send}
        </button>
      </div>
    </IslandCard>
  );
}
