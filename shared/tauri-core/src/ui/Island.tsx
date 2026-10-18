import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore, type ReactNode } from 'react';
import { HOLD_ANSWER } from '@memnox/core/wire';
import { LoaderCircle } from 'lucide-react';
import {
  agentColour,
  countsDown,
  dwellFor,
  finishedCard,
  headerPastOrb,
  idleCountdown,
  isGrowing,
  isOpenMode,
  ISLAND,
  ISLAND_TIMING,
  ISLAND_WINDOW,
  islandSize,
  islandTitle,
  orbSpot,
  RESTING,
  SATELLITE,
  settle,
  SHRINK,
  showsHeader,
  showsSatellites,
  SPRINGS,
  STAND_IN_NOTCH,
  type FinishedCard,
  type HeldAnswer,
  type HeldCalls,
  type HeldOutcome,
  type IslandMode,
  type NotchGeometry,
  type OrbState,
  type ProposalCards,
  type Setup,
  type Talking,
  type TalkState,
  type VoiceSettings,
} from '../core';
import { islandWindow, type HitArea } from './adapters/tauri-island-window';
import { CONTENT_INSET, Empty, Finished, HeldCall, ProposalCard } from './Cards';
import { loudness } from './island/loudness';
import { IslandButton, IslandCard, IslandTab, NotchShape, Satellite, UnderPill, useSprings, type Movement } from './kit';
import { Orb, type OrbHandle } from './Orb';
import { Settings } from './Settings';
import { Hearing, useConversation, VoicePills } from './Talk';

/** A working session as the closed island shows it: one logo beside the notch. */
export interface WorkingSession {
  readonly sessionId: string;
  readonly agent: string;
}

/** What only the preview page sets, so it can put the island in any mode without a daemon behind it. */
export interface IslandPreview {
  readonly opened?: boolean;
  readonly hovering?: boolean;
  readonly settings?: boolean;
  readonly talk?: TalkState;
  readonly finished?: FinishedCard;
  readonly countdown?: number;
}

/** The island's parts: the core's use cases, and the seams the later phases fill. */
export interface IslandParts {
  calls: HeldCalls;
  talking: Talking;
  cards: ProposalCards;
  setup: Setup;
  voiceSettings: VoiceSettings;
  /** Where the notch is; Windows and Linux take the stand in bar. */
  notch?: NotchGeometry;
  /** The sessions working now, which a later phase reads from the daemon's session list. */
  working?: readonly WorkingSession[];
  /** The grid satellite; drawn disabled until the launcher is built. */
  onLauncher?: () => void;
  /** The history satellite, and a dwell on the orb's side of the notch; the side panel is a later phase. */
  onSide?: () => void;
  /** The Settings satellite; until its own window lands, the island shows the Settings panel in place. */
  onSettings?: () => void;
  /** The mute satellite and whether the voice is muted; drawn disabled until a mute exists. */
  mute?: { on: boolean; toggle: () => void };
  /** Opens a finished session's own window; the Open button shows only with it. */
  onOpenSession?: (sessionId: string) => void;
  preview?: IslandPreview;
}

/** The modes that put the island away rather than answer something. */
const RESTING_MODES: readonly IslandMode[] = ['peek', 'compact', 'empty', 'overview', 'session'];

/** The talking modes share one content, so the island grows around the words instead of refading them. */
function contentId(mode: IslandMode, active: boolean): string {
  if (mode === 'conversation' || mode === 'draft' || mode === 'rule') return 'conversation';
  if (mode === 'answer' && active) return 'conversation';
  return mode;
}

/**
 * The island: a black shape that flows out of the screen's top edge, the one orb, and the content of
 * its mode, in a 740 by 672 window that never resizes. Ported from the Mac's `IslandView` and
 * `IslandPanel`: the mode is the core's `settle`, sizes and the orb's place are `islandSize` and
 * `orbSpot`, and every change of size moves the width, height, bottom radius and the orb together.
 */
export function Island({ calls, talking, cards, setup, voiceSettings, notch = STAND_IN_NOTCH, working = [], onLauncher, onSide, onSettings, mute, onOpenSession, preview: scripted }: IslandParts) {
  const previewing = scripted !== undefined;
  const preview = scripted ?? {};
  const held = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state,
  );
  const proposals = useSyncExternalStore(
    (changed) => cards.observe(changed),
    () => cards.cards,
  );
  const setupState = useSyncExternalStore(
    (changed) => setup.observe(changed),
    () => setup.state,
  );
  // The preview has no Rust behind it, so it never asks after the microphone.
  const conversation = useConversation(talking, { probe: !previewing });
  const talk = preview.talk ?? conversation.state;
  const active = preview.talk !== undefined ? preview.talk.phase !== 'idle' : conversation.active;

  const [opened, setOpened] = useState(preview.opened ?? false);
  const [settingsOpen, setSettingsOpen] = useState(preview.settings ?? false);
  const [pointerOver, setPointerOver] = useState(preview.hovering ?? false);
  const [finished, setFinished] = useState<FinishedCard | undefined>(preview.finished);
  const [countdown, setCountdown] = useState<number | undefined>(preview.countdown);
  const orb = useRef<OrbHandle>();
  const shape = useRef<HTMLDivElement>(null);
  const root = useRef<HTMLDivElement>(null);
  const below = useRef<HTMLDivElement>(null);
  const lastActivity = useRef(performance.now());
  const onLeft = useRef(false);

  // The latest proposal decides between the work and the rule screens; the newest is the one shown.
  const proposal = proposals[proposals.length - 1];
  const settled = settle({
    ...RESTING,
    held: held.waiting.shown !== undefined || held.settled !== undefined,
    draft: proposal?.kind === 'work',
    rule: proposal?.kind === 'rule',
    finished: finished !== undefined,
    talking: active,
    wordsHeard: (talk.heard ?? '') !== '' || (talk.phase === 'speaking' && talk.reply !== ''),
    opened: opened || settingsOpen,
    working: working.length,
  });
  // Until the Settings window lands, the panel opens in the island at the answer's size, in place of the resting screens.
  const interimSettings = settingsOpen && RESTING_MODES.includes(settled);
  const mode: IslandMode = interimSettings ? 'answer' : settled;
  const small = !isOpenMode(mode);
  const hovering = pointerOver && small;

  // Growing springs out and shrinking eases in, chosen by area as the Mac chooses; a hover alone uses its own spring.
  const previous = useRef(mode);
  const movement = useRef<Movement>({ kind: 'spring', spring: SPRINGS.grow });
  if (previous.current !== mode) {
    movement.current = isGrowing(previous.current, mode, notch) ? { kind: 'spring', spring: SPRINGS.grow } : { kind: 'curve', ...SHRINK };
    previous.current = mode;
  } else if (small) {
    movement.current = { kind: 'spring', spring: SPRINGS.hover };
  }
  const size = islandSize(mode, notch);
  const spot = orbSpot(mode, notch, hovering);
  const moved = useSprings(
    { width: size.width, height: size.height, radius: small ? ISLAND.closedBottomRadius : ISLAND.openBottomRadius, orbX: spot.x, orbY: spot.y, orbDiameter: spot.diameter },
    movement.current,
  );

  // A finished session stays up for a moment and the island hops, then it folds back.
  useEffect(
    () =>
      calls.observeEvents((event) => {
        const card = finishedCard(event);
        if (card !== undefined) setFinished(card);
      }),
    [calls],
  );
  useEffect(() => {
    if (finished === undefined || preview.finished !== undefined) return;
    hop(shape.current);
    const done = setTimeout(() => setFinished(undefined), ISLAND_TIMING.finishedFor);
    return () => clearTimeout(done);
  }, [finished, preview.finished]);

  function open() {
    lastActivity.current = performance.now();
    setOpened(true);
  }

  function close() {
    setOpened(false);
    setSettingsOpen(false);
    setCountdown(undefined);
  }

  function tapped() {
    void conversation.converse();
  }

  // Resting on the closed island opens it after the dwell; resting on the orb's side opens the side history instead.
  useEffect(() => {
    if (!hovering || active || preview.hovering !== undefined) return;
    const wait = setTimeout(() => (onLeft.current && onSide !== undefined ? onSide() : open()), dwellFor(mode));
    return () => clearTimeout(wait);
  }, [hovering, active, mode, onSide, preview.hovering]);

  // Open and untouched for a minute it puts itself away, counting the last ten seconds down as a shrinking line.
  useEffect(() => {
    if (!(opened || settingsOpen) || active || !countsDown(mode) || preview.countdown !== undefined) {
      if (preview.countdown === undefined) setCountdown(undefined);
      return;
    }
    const tick = setInterval(() => {
      const left = idleCountdown(performance.now() - lastActivity.current);
      if (left.closes) close();
      else setCountdown(left.fraction);
    }, 200);
    return () => clearInterval(tick);
  }, [opened, settingsOpen, active, mode, preview.countdown]);

  // The webview hears no pointer while the window lets clicks through, so Rust says when it left.
  useEffect(() => islandWindow.onPointer((over) => !over && setPointerOver(false)), []);

  const shapeWidth = moved.width + 2 * ISLAND.flare;
  const shapeLeft = (ISLAND_WINDOW.width - shapeWidth) / 2;
  const bodyLeft = shapeLeft + ISLAND.flare;
  const header = showsHeader(mode, active);
  const satellites = showsSatellites(mode, active);

  // Clicks pass through everywhere but the shape and 6 around it, the pills under it and the satellite columns.
  const [pillsBox, setPillsBox] = useState<HitArea>();
  useLayoutEffect(() => {
    const box = below.current?.getBoundingClientRect();
    const window = root.current?.getBoundingClientRect();
    const next = box === undefined || window === undefined || box.height === 0 ? undefined : { x: box.x - window.x, y: box.y - window.y, width: box.width, height: box.height };
    if (JSON.stringify(next) !== JSON.stringify(pillsBox)) setPillsBox(next);
  });
  const hitWidth = Math.max(moved.width, size.width) + 2 * ISLAND.flare;
  const hitHeight = Math.max(moved.height, size.height);
  const areas: HitArea[] = [
    { x: (ISLAND_WINDOW.width - hitWidth) / 2 - ISLAND.pointerSlop, y: 0, width: hitWidth + 2 * ISLAND.pointerSlop, height: hitHeight + ISLAND.pointerSlop },
  ];
  if (satellites) {
    const column = notch.height + SATELLITE.gapBelowNotch + SATELLITE.step + SATELLITE.diameter + SATELLITE.gapBelowNotch;
    areas.push({ x: (ISLAND_WINDOW.width - size.width) / 2 - SATELLITE.reach, y: 0, width: size.width + 2 * SATELLITE.reach, height: column });
  }
  if (pillsBox !== undefined) areas.push(pillsBox);
  const areasKey = JSON.stringify(areas.map((area) => [area.x, area.y, area.width, area.height].map(Math.round)));
  useEffect(() => islandWindow.setHitAreas(JSON.parse(areasKey).map(([x, y, width, height]: number[]) => ({ x, y, width, height }))), [areasKey]);

  function answered(choice: HeldAnswer, outcome: HeldOutcome) {
    if (outcome.kind === 'failed') shake(shape.current);
    if (outcome.kind === 'cancelled') return;
    orb.current?.react(outcome.kind === 'failed' ? 'stumble' : outcome.kind !== 'answered' ? 'settle' : choice === HOLD_ANSWER.DENY ? 'refused' : 'allowed');
  }

  function proposalAnswered(outcome: HeldOutcome) {
    if (outcome.kind === 'failed') {
      shake(shape.current);
      orb.current?.react('stumble');
    } else if (outcome.kind === 'answered') orb.current?.react('settle');
  }

  const waiting = held.waiting.count > 0;
  const orbState: OrbState = waiting ? 'needs-you' : talk.phase;
  const title = interimSettings ? 'Settings' : islandTitle(mode);

  const content: ReactNode = (() => {
    switch (mode) {
      case 'peek':
        return <TapTarget onTap={tapped} label="Talk to Memnox" />;
      case 'compact':
        return <Compact working={working} waitingOn={undefined} onTap={tapped} notch={notch} />;
      case 'voice':
        return <TapTarget onTap={tapped} label="Stop or keep listening" />;
      case 'hearing':
        return <Hearing state={talk} notch={notch} onTap={tapped} />;
      case 'held':
        return <HeldCall calls={calls} onPressed={(subject) => talking.answeredByHand(subject)} onAnswered={answered} />;
      case 'draft':
      case 'rule':
        return <ProposalCard cards={cards} onAnswered={proposalAnswered} />;
      case 'finished':
        return finished === undefined ? null : (
          <Finished
            card={finished}
            onOpen={onOpenSession === undefined || finished.sessionId === undefined ? undefined : () => onOpenSession(finished.sessionId ?? '')}
            onDone={() => setFinished(undefined)}
          />
        );
      case 'empty':
        return <Empty onTalk={tapped} talkDisabled={conversation.mic !== 'ready' && !previewing} />;
      case 'answer':
        return interimSettings ? (
          <IslandCard className={`${CONTENT_INSET} overflow-y-auto p-3.5 text-body text-white`}>
            <Settings voiceSettings={voiceSettings} setup={setup} />
          </IslandCard>
        ) : null;
      // Built by later phases: the sessions, a session up close, an agent's question, the launcher and a phone turn.
      case 'overview':
      case 'session':
      case 'question':
      case 'launcher':
      case 'conversation':
        return null;
    }
  })();

  return (
    <div
      ref={root}
      className="relative mx-auto overflow-hidden font-sans text-body text-white"
      data-theme="dark"
      style={{ width: ISLAND_WINDOW.width, height: ISLAND_WINDOW.height }}
      onPointerMove={() => (lastActivity.current = performance.now())}
      aria-live="polite"
    >
      <div
        ref={shape}
        className="absolute top-0"
        style={{ left: shapeLeft, width: shapeWidth, height: moved.height, transformOrigin: 'top center' }}
        onPointerEnter={() => setPointerOver(true)}
        onPointerLeave={() => setPointerOver(false)}
        onPointerMove={(event) => {
          const box = shape.current?.getBoundingClientRect();
          onLeft.current = box !== undefined && event.clientX < box.left + box.width / 2 - notch.width / 2;
        }}
      >
        <NotchShape className="absolute inset-0" width={shapeWidth} height={moved.height} flare={ISLAND.flare} bottomRadius={moved.radius} open={!small} />
        {/* The pointer counts as over the island 6 around its shape, as the Mac's slop does. */}
        <div className="absolute" style={{ left: -ISLAND.pointerSlop, top: 0, width: shapeWidth + 2 * ISLAND.pointerSlop, height: moved.height + ISLAND.pointerSlop }} />
        <div className="absolute top-0" style={{ left: ISLAND.flare, width: moved.width, height: moved.height }}>
          <div className="absolute inset-0 overflow-hidden" style={{ borderRadius: `0 0 ${moved.radius}px ${moved.radius}px` }}>
            <ContentSwap id={contentId(mode, active)}>{content}</ContentSwap>
            {header && (
              <IslandHeader
                title={title}
                count={working.length}
                pastOrb={headerPastOrb(mode)}
                notch={notch}
                back={interimSettings ? () => setSettingsOpen(false) : mode === 'session' || mode === 'answer' ? close : undefined}
              />
            )}
          </div>
          {/* One orb throughout, positioned rather than swapped, so it travels and grows with the island. */}
          <Orb x={moved.orbX} y={moved.orbY} diameter={moved.orbDiameter} state={orbState} waiting={waiting} loudness={() => loudness.value} handle={(handle) => (orb.current = handle)} />
          {countdown !== undefined && (
            <span
              className="pointer-events-none absolute h-0.5 -translate-x-1/2 rounded-full bg-white/35 transition-[width] duration-200 ease-linear"
              style={{ left: moved.width / 2, top: moved.height - 4 - 1, width: 160 * countdown }}
            />
          )}
        </div>
      </div>
      {satellites && (
        <Satellites
          notch={notch}
          left={bodyLeft}
          width={moved.width}
          launcherOn={mode === 'launcher'}
          onLauncher={onLauncher}
          onSide={onSide}
          onSettings={() => (onSettings !== undefined ? onSettings() : (setSettingsOpen(true), open()))}
          mute={mute}
        />
      )}
      <div className="pointer-events-none absolute inset-x-0 flex flex-col items-center" style={{ top: moved.height + ISLAND.pillGap }}>
        <div ref={below} className="pointer-events-auto flex max-w-[560px] flex-col items-center gap-1.5">
        {setupState.doing !== undefined && (
          <UnderPill symbol={<LoaderCircle size={11} strokeWidth={2.25} />} tone="neutral" spinning>
            {setupState.doing}
          </UnderPill>
        )}
        {setupState.failed !== undefined && (
          <UnderPill symbol="exclamationmark.triangle.fill" tone="red">
            <span className="truncate">{setupState.failed}</span>
            <IslandButton className="!px-2.5 !py-[3px] !text-caption" onClick={() => void setup.ensure()}>
              Check again
            </IslandButton>
          </UnderPill>
        )}
        {setupState.doing === undefined && setupState.failed === undefined && !held.connected && !previewing && (
          <UnderPill symbol="ellipsis" tone="neutral">
            Waiting for Memnox to start
          </UnderPill>
        )}
        {!previewing && <VoicePills conversation={conversation} />}
        </div>
      </div>
    </div>
  );
}

/** Shakes the island side to side, for something refused or failed, as `ShakeEffect` does. */
function shake(element: HTMLElement | null) {
  if (element === null || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const frames = Array.from({ length: 25 }, (_, step) => {
    const p = step / 24;
    return { translate: `${Math.sin(p * Math.PI * 6) * 9 * (1 - p)}px 0` };
  });
  element.animate(frames, { duration: 420, easing: 'linear' });
}

/** A little swell and back hung from the top edge, for something that arrived, as `HopEffect` does. */
function hop(element: HTMLElement | null) {
  if (element === null || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  element.animate([{ scale: '1' }, { scale: '1.05' }, { scale: '1' }], { duration: 500, easing: 'ease-in-out' });
}

/** The whole body as one tap, which starts listening or stops it. */
function TapTarget({ onTap, label }: { onTap: () => void; label: string }) {
  return <button type="button" className="absolute inset-0 cursor-pointer bg-transparent" onClick={onTap} aria-label={label} />;
}

/**
 * The content of the mode, leaving and arriving as `islandContent` does: the old content goes over
 * 0.16 s to a blur, and the new one waits that long, then comes in from the same over 0.3 s.
 */
function ContentSwap({ id, children }: { id: string; children: ReactNode }) {
  const [leaving, setLeaving] = useState<{ id: string; node: ReactNode } | undefined>();
  const shown = useRef({ id, node: children });
  // Before the ref below takes this render's content, so the content of the mode that left is still in it.
  useLayoutEffect(() => {
    if (shown.current.id !== id) setLeaving(shown.current);
  }, [id]);
  useLayoutEffect(() => {
    shown.current = { id, node: children };
  });
  useEffect(() => {
    if (leaving === undefined) return;
    const done = setTimeout(() => setLeaving(undefined), 160);
    return () => clearTimeout(done);
  }, [leaving]);
  return (
    <>
      {leaving !== undefined && leaving.id !== id && (
        <div key={`leaving-${leaving.id}`} className="pointer-events-none absolute inset-0 animate-content-out">
          {leaving.node}
        </div>
      )}
      <div key={id} className="absolute inset-0 animate-content-in">
        {children}
      </div>
    </>
  );
}

/**
 * The row along the notch while the island is open: the page's title on the left and how many work on
 * the right, 24 tall, fading in once the island has mostly opened.
 */
function IslandHeader({ title, count, pastOrb, notch, back }: { title: string; count: number; pastOrb: boolean; notch: NotchGeometry; back?: () => void }) {
  return (
    <div className="absolute inset-x-0 top-0 flex animate-header-in items-center gap-1.5" style={{ height: notch.height, paddingLeft: pastOrb ? 46 : 18 }}>
      {back !== undefined && <IslandTab symbol="chevron.left" label="Back" onPress={back} />}
      <span key={title} className="animate-[content-in_350ms_cubic-bezier(0.25,1.1,0.4,1)_both] truncate text-headline font-semibold text-white" role="heading" aria-level={1}>
        {title}
      </span>
      <span className="flex-1" style={{ minWidth: notch.width + 16 }} />
      {/* Nothing at all when nothing works, since "0 working" reads like a fault. */}
      <span className="tabular pr-[18px] text-button font-medium text-white/55" style={{ opacity: count === 0 ? 0 : 1 }} aria-hidden={count === 0}>
        {count === 1 ? '1 working' : `${count} working`}
      </span>
    </div>
  );
}

/**
 * The round buttons either side of the open island: the grid and the history on the left, Settings
 * and the voice on the right, each column sliding out from behind the island, the second a beat later.
 */
function Satellites({
  notch,
  left,
  width,
  launcherOn,
  onLauncher,
  onSide,
  onSettings,
  mute,
}: {
  notch: NotchGeometry;
  left: number;
  width: number;
  launcherOn: boolean;
  onLauncher?: () => void;
  onSide?: () => void;
  onSettings: () => void;
  mute?: { on: boolean; toggle: () => void };
}) {
  const top = notch.height + SATELLITE.gapBelowNotch;
  const gap = SATELLITE.step - SATELLITE.diameter;
  return (
    <div className="animate-satellites-in">
      <div className="absolute flex flex-col" style={{ top, left: left - SATELLITE.gap - SATELLITE.diameter, gap }}>
        <span className="animate-satellite-left">
          <Satellite symbol="square.grid.2x2" label="Everything Memnox does" on={launcherOn} onPress={onLauncher} />
        </span>
        <span className="animate-satellite-left [animation-delay:50ms]">
          <Satellite symbol="clock.arrow.circlepath" label="History, sessions and what needs you" onPress={onSide} />
        </span>
      </div>
      <div className="absolute flex flex-col" style={{ top, left: left + width + SATELLITE.gap, gap }}>
        <span className="animate-satellite-right">
          <Satellite symbol="gearshape" label="Settings" onPress={onSettings} />
        </span>
        <span className="animate-satellite-right [animation-delay:50ms]">
          <Satellite symbol={mute?.on === true ? 'speaker.slash' : 'speaker.wave.2'} label={mute?.on === true ? 'Unmute the voice' : 'Mute the voice'} on={mute?.on === true} onPress={mute?.toggle} />
        </span>
      </div>
    </div>
  );
}

/** How many logos fit beside the notch before they crowd it. */
const SHOWN_LOGOS = 3;

/**
 * Beside the notch with sessions working: up to three logos on the right, 16 each, overlapping by 5
 * and ringed in black so they stay apart. The agent's colour and initial stand in for its logo until
 * the session list brings the logos themselves; a waiting session's logo hops.
 */
function Compact({ working, waitingOn, onTap, notch }: { working: readonly WorkingSession[]; waitingOn: string | undefined; onTap: () => void; notch: NotchGeometry }) {
  const count = working.length;
  return (
    <button type="button" className="absolute inset-x-0 top-0 flex cursor-pointer items-center justify-end bg-transparent pr-3" style={{ height: notch.height }} onClick={onTap} aria-label={count === 1 ? '1 agent working' : `${count} agents working`}>
      <span className="flex items-center">
        {working.slice(0, SHOWN_LOGOS).map((session, index) => (
          <span
            key={session.sessionId}
            className={`grid size-4 animate-[card-in_400ms_cubic-bezier(0.3,1.2,0.6,1)_both] place-items-center rounded-full text-[8px] font-bold text-black ${session.sessionId === waitingOn ? 'animate-bounce' : ''}`}
            style={{ backgroundColor: agentColour(session.agent), boxShadow: '0 0 0 1.5px #000', marginLeft: index === 0 ? 0 : -5 }}
            aria-hidden
          >
            {session.agent.replace(/^agt_/, '').charAt(0).toUpperCase()}
          </span>
        ))}
      </span>
    </button>
  );
}
