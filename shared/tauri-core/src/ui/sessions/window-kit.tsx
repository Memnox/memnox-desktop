import { useState, useSyncExternalStore, type ReactNode } from 'react';
import { HOLD_ANSWER } from '@memnox/core/wire';
import type { HeldCalls, HeldCard } from '../../core';
import { BrandLogo, IslandButton, SFSymbol, type SFSymbolName } from '../kit';

/**
 * The pieces the session windows share, outside the island: these follow the system's light or dark as
 * the Mac's windows do, where the island is always dark. Each is the twin of one Swift view.
 */

/** PressDown: scale 0.94 while held on spring(0.2, 0.6), the only sign a borderless panel gives that a click landed. */
export const PRESS_DOWN = 'cursor-pointer select-none transition-[scale] duration-[220ms] ease-press active:scale-[0.94] disabled:cursor-default disabled:active:scale-100';

/**
 * `CardButton`: the floating cards' pill, 12.5 medium, 14 by 8. Primary is #F5F6F8 at 92% (100% hovered)
 * with near black words; secondary is ink 9% (15% hovered). Hover eases over 0.12 s; disabled dims to 0.4.
 */
export function CardButton({ title, symbol, primary = false, disabled, onPress }: { title: string; symbol?: SFSymbolName; primary?: boolean; disabled?: boolean; onPress: () => void }) {
  const look = primary ? 'bg-[#F5F6F8]/[0.92] text-[#0B0C0E] hover:bg-[#F5F6F8]' : 'bg-ink/[0.09] text-ink hover:bg-ink/15';
  return (
    <button
      type="button"
      className={`${PRESS_DOWN} inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 py-2 text-button font-medium transition-colors duration-[120ms] ease-out disabled:opacity-40 ${look}`}
      disabled={disabled}
      onClick={onPress}
    >
      {symbol !== undefined && <SFSymbol name={symbol} size={12.5} weight="medium" />}
      {title}
    </button>
  );
}

/** `CloseButton`: an 11 semibold cross, muted until hovered, in a 26 circle that fills ink 12% on hover. */
export function CloseButton({ onPress, label = 'Close' }: { onPress: () => void; label?: string }) {
  return (
    <button
      type="button"
      className={`${PRESS_DOWN} grid size-[26px] shrink-0 place-items-center rounded-full text-muted transition-colors duration-[120ms] ease-out hover:bg-ink/[0.12] hover:text-foreground`}
      onClick={onPress}
      title={label}
      aria-label={label}
    >
      <SFSymbol name="xmark" size={11} weight="semibold" />
    </button>
  );
}

/**
 * `FilterChip`: a 24 tall capsule, 10 across, the title 11 and an optional count 10 semibold. Chosen is
 * the primary fill with its dark words; otherwise ink 6% with a 1 px rim of ink 14%.
 */
export function FilterChip({ title, chosen, count, onPress }: { title: string; chosen: boolean; count?: number; onPress: () => void }) {
  return (
    <button
      type="button"
      className={`${PRESS_DOWN} inline-flex h-6 shrink-0 items-center gap-1 rounded-full px-2.5 text-caption transition-colors duration-200 ${
        chosen ? 'bg-primary-fill font-semibold text-primary-text' : 'border border-ink/[0.14] bg-ink/[0.06] font-medium text-ink'
      }`}
      onClick={onPress}
      aria-pressed={chosen}
    >
      {title}
      {count !== undefined && <span className={`tabular text-micro font-semibold ${chosen ? 'opacity-[0.92]' : 'opacity-50'}`}>{count}</span>}
    </button>
  );
}

/** `Keycap`: one key, 11 medium, at least 18 square, radius 4 on the keycap fill. */
export function Keycap({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-key border border-control-edge bg-keycap px-1.5 text-caption font-medium text-foreground">{children}</span>
  );
}

/**
 * `CardHeader`: the mark, the title in the display face 22 semibold with its subtitle 12 muted under it,
 * then an accessory and the close button. The whole row drags the window, as the Mac's moves by its background.
 */
export function CardHeader({ mark, title, subtitle, accessory, onClose }: { mark: ReactNode; title: string; subtitle?: string; accessory?: ReactNode; onClose?: () => void }) {
  return (
    <div className="flex min-w-0 items-center gap-2.5" data-tauri-drag-region>
      <span className="grid size-7 shrink-0 place-items-center">{mark}</span>
      <div className="pointer-events-none flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="line-clamp-2 font-display text-[22px] font-semibold leading-tight text-foreground">{title}</span>
        {subtitle !== undefined && <span className="truncate text-footnote text-muted">{subtitle}</span>}
      </div>
      {accessory}
      {onClose !== undefined && <CloseButton onPress={onClose} />}
    </div>
  );
}

/** `LiveSection`: an uppercased title 10 semibold over its content on the section fill, radius 16. */
export function LiveSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-[7px]">
      <h3 className="m-0 pl-1 text-micro font-semibold uppercase tracking-[0.8px] text-ink/40">{title}</h3>
      <div className="w-full rounded-island border border-ink/[0.035] bg-[var(--mx-section)] p-3">{children}</div>
    </section>
  );
}

/**
 * `HeldStrip`: a call waiting on the person, answered where it is read, through the same signed path as
 * the island: who asks and why, the command, then Deny beside Allow once, which asks for the key when the
 * call reaches outside its session.
 */
export function HeldStrip({ calls, card }: { calls: HeldCalls; card: HeldCard }) {
  const state = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state,
  );
  const [said, setSaid] = useState<string>();
  const answering = state.answering && state.pressed === card.subject;
  async function press(answer: typeof HOLD_ANSWER.DENY | typeof HOLD_ANSWER.ONCE) {
    const outcome = await calls.answer(card.subject, answer);
    setSaid(outcome.kind === 'failed' ? outcome.why : outcome.kind === 'cancelled' ? 'Nothing was sent, so it is still waiting.' : undefined);
  }
  return (
    <div className="flex flex-col gap-2.5 rounded-island border bg-surface p-3" style={{ borderColor: 'rgb(255 159 10 / 0.62)' }}>
      <div className="flex min-w-0 items-center gap-2">
        <BrandLogo agent={card.agent} name={card.who} size={22} />
        <span className="shrink-0 text-body font-semibold text-ink">{card.who}</span>
        <span className="truncate text-body text-ink-secondary">{card.why ?? 'is waiting on you'}</span>
      </div>
      <code className="line-clamp-2 w-full break-all rounded-[8px] bg-ink-faint-fill p-2 font-[ui-monospace,Consolas,monospace] text-footnote text-ink" title={card.what}>
        {card.what}
      </code>
      <div className={`flex items-center gap-2 ${answering ? 'pointer-events-none opacity-[0.55]' : ''}`}>
        <IslandButton inRow onClick={() => void press(HOLD_ANSWER.DENY)} className="!bg-ink/[0.09] !text-ink">
          Deny
        </IslandButton>
        <IslandButton inRow kind="primary" symbol={card.touchID ? 'touchid' : undefined} onClick={() => void press(HOLD_ANSWER.ONCE)}>
          Allow once
        </IslandButton>
      </div>
      {said !== undefined && <span className="text-footnote text-destructive">{said}</span>}
    </div>
  );
}
