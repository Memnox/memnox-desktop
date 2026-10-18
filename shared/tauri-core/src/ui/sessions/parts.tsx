import type { SessionViewStep } from '@memnox/core/wire';
import { agentColour, agentInitial, isActive, statusTint, stepSymbol, stepTint, type SessionStatus } from '../../core';
import { agentLogoUrl, PulseDot, SFSymbol } from '../kit';

/**
 * The small pieces every session screen shares, each the web twin of one Swift view: `SessionLogo`,
 * `IslandStatusBadge`, the step icon and the line counts.
 */

/** The logo fills a little over half its disc, as the Mac's session list and detail draw it. */
const LOGO_SHARE = 0.56;
/** A deep navy, so an initial reads on the agent's own colour behind it. */
const INITIAL_INK = '#0B1A2E';

/**
 * `SessionLogo`: a circle in the agent's colour with its logo at 56% of the side, or its initial in deep
 * navy where it ships none. `ring` draws the black ring the compact logos overlap with.
 */
export function SessionLogo({ agent, name, size, ring, className }: { agent: string; name: string; size: number; ring?: number; className?: string }) {
  const url = agentLogoUrl(agent);
  const inner = size * LOGO_SHARE;
  return (
    <span
      className={`grid shrink-0 place-items-center rounded-full ${className ?? ''}`}
      style={{ width: size, height: size, backgroundColor: agentColour(agent), boxShadow: ring === undefined ? undefined : `0 0 0 ${ring}px #000` }}
      role="img"
      aria-label={name}
    >
      {url !== undefined ? (
        <img src={url} alt="" draggable={false} className="object-contain" style={{ width: inner, height: inner }} />
      ) : (
        <span className="font-display leading-none" style={{ fontSize: inner, color: INITIAL_INK }}>
          {agentInitial(name)}
        </span>
      )}
    </span>
  );
}

/** A colour lifted a quarter of the way toward white, for a label on its own tint. */
export function lifted(hex: string): string {
  return `color-mix(in srgb, ${hex} 75%, white)`;
}

/** A colour at this opacity, for a fill of a status or agent colour. */
export function tinted(hex: string, opacity: number): string {
  return `color-mix(in srgb, ${hex} ${opacity * 100}%, transparent)`;
}

/**
 * `IslandStatusBadge`: a 6 dot in the status colour, pulsing only while busy, and the label 10 semibold
 * in that colour lifted toward white, on a capsule of the colour at 16%.
 */
export function StatusBadge({ status, label }: { status: SessionStatus; label: string }) {
  const tint = statusTint(status);
  return (
    <span className="inline-flex shrink-0 items-center gap-1 whitespace-nowrap rounded-full px-1.5 py-0.5 text-micro font-semibold" style={{ backgroundColor: tinted(tint, 0.16), color: lifted(tint) }}>
      {isActive(status) ? <PulseDot colour={tint} size={6} /> : <span className="size-1.5 rounded-full" style={{ backgroundColor: tint }} />}
      {label}
    </span>
  );
}

/** A step's symbol, 11 medium in a 14 column, tinted by how it went and whether it is the current one. */
export function StepIcon({ step, current }: { step: SessionViewStep; current: boolean }) {
  return (
    <span className="grid w-3.5 shrink-0 place-items-center" style={{ color: stepTint(step, current) }}>
      <SFSymbol name={stepSymbol(step)} size={11} weight="medium" />
    </span>
  );
}

/** "+N" in green and "−N" in red, the minus sign rather than a hyphen, only when something was removed. */
export function Counts({ added, removed, className }: { added?: number; removed?: number; className?: string }) {
  return (
    <span className={`tabular inline-flex shrink-0 items-center gap-1 text-caption font-medium ${className ?? ''}`}>
      {added !== undefined && <span className="text-green">+{added}</span>}
      {removed !== undefined && removed > 0 && <span className="text-red">{'−'}{removed}</span>}
    </span>
  );
}

/** The mini spinner the Mac draws for a step still at work. */
export function MiniSpinner({ size = 10 }: { size?: number }) {
  return <span className="inline-block animate-spin rounded-full border-[1.5px] border-white/25 border-t-white/80" style={{ width: size, height: size }} aria-hidden />;
}
