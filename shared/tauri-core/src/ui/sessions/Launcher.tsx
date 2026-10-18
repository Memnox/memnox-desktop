import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { TILE } from '../../core';
import { notchPress, SFSymbol, type SFSymbolName } from '../kit';
import './sessions.css';

/**
 * `IslandLauncher`: everything Memnox does as a grid of tiles, five across, and the person's agents and
 * apps one tile away on the Tools page. Each tile is a `NotchTile` and arrives as `NotchArrival` staggers it.
 */

const CONTENT = 'absolute inset-x-2.5 bottom-2.5 top-9';

/** What a tile does, or undefined where this computer has no way to do it yet, which draws it disabled. */
export interface LauncherActions {
  talk?: () => void;
  sessions?: () => void;
  history?: () => void;
  tools?: () => void;
  sayRule?: () => void;
  mute?: () => void;
  whatHappened?: () => void;
  phones?: () => void;
  dictation?: () => void;
  settings?: () => void;
}

/** What the tiles say that changes: how many work, how many apps, whether the voice is muted. */
export interface LauncherFacts {
  readonly working: number;
  /** "N connected", "Reading" or "None yet", as the Tools tile's caption. */
  readonly toolsCaption: string;
  readonly muted: boolean;
  readonly historyOpen: boolean;
  /** The talk key and the rule chord, as this platform writes them. */
  readonly talkKey: string;
  readonly ruleKey: string;
}

/** One agent or app on the Tools page: its mark, its name and its status. */
export interface LauncherTool {
  readonly id: string;
  readonly title: string;
  readonly caption: string;
  readonly mark: ReactNode;
  readonly onPress?: () => void;
}

/** Sky for Talk, amber for a rule, red for muted; everything else white 85%. */
const TINT = { sky: '#8CC8FF', amber: '#FF9F0A', red: '#FF453A', plain: 'rgb(255 255 255 / 0.85)' } as const;

export function Launcher({
  page,
  facts,
  actions,
  tools = [],
  toolsNote,
}: {
  /** The grid of actions, or the Tools page of agents and apps. */
  page: 'actions' | 'tools';
  facts: LauncherFacts;
  actions: LauncherActions;
  tools?: readonly LauncherTool[];
  toolsNote?: string;
}) {
  const tiles: { title: string; caption: string; symbol: SFSymbolName; tint: string; lit?: boolean; onPress?: () => void }[] = [
    { title: 'Talk', caption: facts.talkKey, symbol: 'waveform', tint: TINT.sky, onPress: actions.talk },
    { title: 'Sessions', caption: facts.working === 0 ? 'None working' : `${facts.working} working`, symbol: 'square.stack.3d.up', tint: TINT.plain, onPress: actions.sessions },
    { title: 'History', caption: 'Recent answers', symbol: 'clock.arrow.circlepath', tint: TINT.plain, lit: facts.historyOpen, onPress: actions.history },
    { title: 'Tools', caption: facts.toolsCaption, symbol: 'square.grid.2x2', tint: TINT.plain, onPress: actions.tools },
    { title: 'Say a rule', caption: facts.ruleKey, symbol: 'shield.lefthalf.filled', tint: TINT.amber, onPress: actions.sayRule },
    {
      title: facts.muted ? 'Unmute' : 'Mute',
      caption: facts.muted ? 'Voice off' : 'Voice on',
      symbol: facts.muted ? 'speaker.slash' : 'speaker.wave.2',
      tint: facts.muted ? TINT.red : TINT.plain,
      lit: facts.muted,
      onPress: actions.mute,
    },
    { title: 'What happened', caption: 'Copy for support', symbol: 'doc.on.clipboard', tint: TINT.plain, onPress: actions.whatHappened },
    { title: 'Phones', caption: 'Pair or revoke', symbol: 'iphone', tint: TINT.plain, onPress: actions.phones },
    { title: 'Dictation', caption: 'Settings', symbol: 'keyboard', tint: TINT.plain, onPress: actions.dictation },
    { title: 'Settings', caption: 'Everything else', symbol: 'gearshape', tint: TINT.plain, onPress: actions.settings },
  ];
  // Keyed by page, so the stagger replays on every switch as the Mac re-keys it.
  return (
    <div key={page} className={`${CONTENT} overflow-y-auto [scrollbar-width:none]`}>
      <div className="grid" style={{ gridTemplateColumns: `repeat(${TILE.columns}, minmax(0, 1fr))`, gap: TILE.spacing }}>
        {page === 'actions'
          ? tiles.map((tile, order) => (
              <NotchTile key={tile.title} order={order} title={tile.title} caption={tile.caption} lit={tile.lit} onPress={tile.onPress} mark={<NotchSymbol name={tile.symbol} tint={tile.tint} />} />
            ))
          : tools.map((tool, order) => <NotchTile key={tool.id} order={order} title={tool.title} caption={tool.caption} mark={tool.mark} onPress={tool.onPress} />)}
      </div>
      {page === 'tools' && (toolsNote !== undefined || tools.length === 0) && (
        <p className="m-0 px-1 pt-2 text-footnote text-white/60">
          {toolsNote ?? 'No apps connected yet. Ask Memnox to do something in Gmail, Slack or GitHub and it opens the sign in for you.'}
        </p>
      )}
    </div>
  );
}

/** `NotchSymbol`: an SF Symbol at 22 medium in its 25 frame, white 85% unless tinted. */
export function NotchSymbol({ name, tint = TINT.plain }: { name: SFSymbolName; tint?: string }) {
  return (
    <span className="grid size-[25px] place-items-center" style={{ color: tint }}>
      {/* Keyed, so mute and unmute swap with a 150 ms fade as the Mac replaces one speaker with the other. */}
      <span key={name} className="grid animate-[fade-in_150ms_ease-out]">
        <SFSymbol name={name} size={22} weight="medium" />
      </span>
    </span>
  );
}

/**
 * `NotchTile`: 92 by 86, the mark over an 11 medium title and a 10 medium rounded caption at white 60%,
 * on white 4.5% (12% lit) with a rim of white 4% (55% lit), radius 16. It never scales; it washes white
 * 9% under the pointer, and its mark bounces on each click.
 */
export function NotchTile({ title, caption, mark, lit = false, order, onPress }: { title: string; caption?: string; mark: ReactNode; lit?: boolean; order: number; onPress?: () => void }) {
  const [bounces, setBounces] = useState(0);
  return (
    <button
      type="button"
      className={`${notchPress(false)} motion-arrive flex min-w-0 animate-[notch-in_400ms_cubic-bezier(0.3,1.3,0.6,1)_both] flex-col items-center justify-center gap-1.5 border px-1.5`}
      style={{
        height: TILE.height,
        borderRadius: TILE.radius,
        backgroundColor: `rgb(255 255 255 / ${lit ? 0.12 : 0.045})`,
        borderColor: `rgb(255 255 255 / ${lit ? 0.55 : 0.04})`,
        animationDelay: `${80 + order * 25}ms`,
      }}
      onClick={() => {
        setBounces((count) => count + 1);
        onPress?.();
      }}
      disabled={onPress === undefined}
      title={title}
      aria-pressed={lit}
    >
      <span key={bounces} className={`grid size-[25px] place-items-center ${bounces > 0 ? 'animate-[symbol-bounce_300ms_ease-out]' : ''}`}>
        {mark}
      </span>
      <FitLine text={title} className="text-caption font-medium text-white" />
      {caption !== undefined && <FitLine text={caption} className="font-rounded text-micro font-medium text-white/60" />}
    </button>
  );
}

/** The least a tile's line shrinks to before it truncates, as `minimumScaleFactor(0.85)` lets it. */
const SMALLEST_SCALE = 0.85;

/** One line that shrinks to fit its tile, down to 85%, and only then truncates. */
function FitLine({ text, className }: { text: string; className: string }) {
  const line = useRef<HTMLSpanElement>(null);
  const [size, setSize] = useState<number>();
  useLayoutEffect(() => {
    const element = line.current;
    if (element === null) return;
    element.style.fontSize = '';
    const base = parseFloat(getComputedStyle(element).fontSize);
    const room = element.clientWidth;
    const needed = element.scrollWidth;
    setSize(needed > room && needed > 0 ? base * Math.max(SMALLEST_SCALE, room / needed) : undefined);
  }, [text]);
  return (
    <span ref={line} className={`w-full truncate text-center leading-tight ${className}`} style={size === undefined ? undefined : { fontSize: size }}>
      {text}
    </span>
  );
}
