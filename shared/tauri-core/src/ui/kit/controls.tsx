import type { ReactNode } from 'react';
import { notchPress, PRESSABLE } from './press';
import { SFSymbol, type SFSymbolName } from './symbols';

/**
 * A round button beside the open island: a 44 circle of black with a 0.75 px rim of white 16% (55%
 * while it is where you are), its symbol 17 medium white, pressing as the notch presses. Without an
 * action it is drawn disabled, which is how a page a later phase builds waits for its seam.
 */
export function Satellite({ symbol, label, on = false, onPress }: { symbol: SFSymbolName; label: string; on?: boolean; onPress?: () => void }) {
  return (
    <button
      type="button"
      className={`${notchPress(true)} grid size-11 place-items-center rounded-full bg-black text-white`}
      style={{ boxShadow: `inset 0 0 0 0.75px rgb(255 255 255 / ${on ? 0.55 : 0.16})` }}
      onClick={onPress}
      disabled={onPress === undefined}
      title={label}
      aria-label={label}
      aria-pressed={on}
    >
      {/* Keyed, so mute and unmute swap with a fade as the Mac morphs one speaker into the other. */}
      <span key={symbol} className="grid animate-[fade-in_200ms_ease-out]">
        <SFSymbol name={symbol} size={17} weight="medium" />
      </span>
    </button>
  );
}

/** `IslandTab`: a 30 by 24 capsule in the header holding one symbol, 12 semibold at white 62%, white on a 12% fill when on. */
export function IslandTab({ symbol, label, on = false, onPress }: { symbol: SFSymbolName; label: string; on?: boolean; onPress: () => void }) {
  return (
    <button
      type="button"
      className={`${PRESSABLE} grid h-6 w-[30px] place-items-center rounded-full ${on ? 'bg-white/[0.12] text-white' : 'text-white/[0.62]'}`}
      onClick={onPress}
      title={label}
      aria-label={label}
      aria-pressed={on}
    >
      <SFSymbol name={symbol} size={12} weight="semibold" />
    </button>
  );
}

/** A glyph that presses and nothing else, such as the queue's chevrons: 13 at the row's own colour. */
export function GlyphButton({ symbol, label, disabled, onPress }: { symbol: SFSymbolName; label: string; disabled?: boolean; onPress: () => void }) {
  return (
    <button type="button" className={`${PRESSABLE} grid place-items-center text-white disabled:opacity-40`} onClick={onPress} disabled={disabled} title={label} aria-label={label}>
      <SFSymbol name={symbol} size={13} weight="regular" />
    </button>
  );
}

/** What colours a pill under the island takes: its symbol, and the rim at half of it. */
export type PillTone = 'amber' | 'red' | 'neutral';

const PILL_TONE: Record<PillTone, { symbol: string; rim: string }> = {
  amber: { symbol: 'text-amber', rim: 'rgb(255 159 10 / 0.5)' },
  red: { symbol: 'text-red', rim: 'rgb(255 69 58 / 0.5)' },
  neutral: { symbol: 'text-white/[0.62]', rim: 'rgb(255 255 255 / 0.14)' },
};

/**
 * A pill hanging under the island, `IslandPhonePill`'s look: a black capsule with a 1 px rim, 12 by 5,
 * an 11 semibold symbol and 11 medium white words on one line. Phone driving, setup and the voice
 * install all hang here, so whatever keeps the island from answering is seen in every mode.
 */
export function UnderPill({ symbol, tone = 'amber', children, spinning = false }: { symbol?: SFSymbolName | ReactNode; tone?: PillTone; children: ReactNode; spinning?: boolean }) {
  const look = PILL_TONE[tone];
  return (
    <div className="inline-flex max-w-full animate-pill-in items-center gap-1 rounded-full bg-black px-3 py-[5px]" style={{ boxShadow: `inset 0 0 0 1px ${look.rim}` }}>
      {symbol !== undefined && (
        <span className={`grid shrink-0 ${look.symbol} ${spinning ? 'animate-spin' : ''}`}>
          {typeof symbol === 'string' ? <SFSymbol name={symbol as SFSymbolName} size={11} weight="semibold" /> : symbol}
        </span>
      )}
      <span className="flex min-w-0 items-center gap-2 truncate text-caption font-medium text-white">{children}</span>
    </div>
  );
}
