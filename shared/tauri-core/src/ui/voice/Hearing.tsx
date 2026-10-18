import { islandTop, type NotchGeometry } from '../../core';
import { SFSymbol, type SFSymbolName } from '../kit';
import { LiveWords } from './LiveWords';
import './voice.css';

/** Where the words sit below the content top, clear of the 84 orb above them, and how much room they take. */
const WORDS = { belowTop: 104, side: 28, height: 84 } as const;
/** The words' size, the title size the Mac lays them out at. */
const TITLE_SIZE = 17;
const CHIP_TRAILING = 18;

/** What the hearing screen shows: the words so far, and why it is listening when not to talk to Memnox. */
export interface HearingView {
  readonly live: string;
  readonly listening: boolean;
  readonly ruling: boolean;
  readonly dictating: string | undefined;
}

/**
 * `IslandHearing`: the orb above what the person is saying, 17 medium centred under it with a blue
 * caret breathing while it listens. Taking down a rule or dictating, a hint stands in until a word is
 * heard and a chip beside the notch says which. A tap anywhere ends or interrupts the turn.
 */
export function IslandHearing({ view, notch, onTap }: { view: HearingView; notch: NotchGeometry; onTap: () => void }) {
  const hint = view.live === '' ? (view.ruling ? 'Say the rule, then let go' : view.dictating) : undefined;
  return (
    <div className="absolute inset-0 cursor-pointer" onClick={onTap} role="button" aria-label="Stop listening">
      <div className="absolute flex items-end justify-center overflow-hidden" style={{ top: islandTop(notch) + WORDS.belowTop, left: WORDS.side, right: WORDS.side, height: WORDS.height }}>
        {hint !== undefined ? (
          // Dimmer than the words themselves, so a hint never reads as heard.
          <p className="m-0 line-clamp-2 text-center text-title font-medium text-white/[0.62]">{hint}</p>
        ) : (
          <LiveWords text={view.live} size={TITLE_SIZE} align="center" listening={view.listening} />
        )}
      </div>
      {(view.ruling || view.dictating !== undefined) && (
        <div className="absolute right-0 top-0 flex items-center" style={{ height: notch.height, paddingRight: CHIP_TRAILING }}>
          {view.ruling ? <RuleModeChip /> : <DictationModeChip />}
        </div>
      )}
    </div>
  );
}

function ModeChip({ symbol, label, colour, fill }: { symbol: SFSymbolName; label: string; colour: string; fill: string }) {
  return (
    <span className="memnox-chip inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-footnote font-semibold" style={{ color: colour, backgroundColor: fill }}>
      <SFSymbol name={symbol} size={12} weight="semibold" />
      {label}
    </span>
  );
}

/** Beside the notch while Control and Alt are held: amber, since the person is about to sign a rule. */
export function RuleModeChip() {
  return <ModeChip symbol="shield.lefthalf.filled" label="Rule" colour="#FFB747" fill="rgb(255 159 10 / 0.22)" />;
}

/** Beside the notch while dictating: words go into the app in front, not to Memnox. */
export function DictationModeChip() {
  return <ModeChip symbol="text.cursor" label="Dictating" colour="#6CA1F9" fill="rgb(59 130 247 / 0.18)" />;
}
