import { Check, CheckCircle2, ChevronLeft, ChevronRight, CircleAlert, type LucideIcon } from 'lucide-react';
import { useState, type ReactNode } from 'react';
import { SettingsKitLines } from '../../core/domain/settings-kit-lines';
import type { StepState } from '../../core/domain/step-state';
import { MEMNOX_MARK, Pressable, Switch } from '../kit';

/**
 * The pieces every Settings page and the first run are built from, each the web twin of one Swift view in
 * `Components/SettingsKit.swift`, `Components/Controls.swift` and `Onboarding/OnboardingKit.swift`, named as
 * the Mac names it. They read the adaptive palette, so Light, Dark and System repaint them.
 */

/** `SettingsMetrics.tileSide`: every row's tile, and the Memnox tile that stands for it. */
const TILE_SIDE = 26;
/** The console's tile holds its symbol at half its side and the Memnox mark at 60%. */
const TILE_SYMBOL_SHARE = 0.5;
const TILE_MARK_SHARE = 0.6;
const TILE_SYMBOL_STROKE = 2;

/** `Kit.checkSide`: a step's status circle, its mark at 55% of it in bold. */
const CHECK_SIDE = 20;
const CHECK_SYMBOL_SHARE = 0.55;
const CHECK_SYMBOL_STROKE = 3.4;

/** A needs hint and a quiet line are caption sized, 11. */
const CAPTION_SIZE = 11;

/** `ShortcutField`'s keys stand 3 apart. */
const KEY_SPACING = 3;

/** The pairing code as both screens show it, 26 semibold. */
const DIGITS_SIZE = 26;

/** `NavigationCapsule.Layout.symbolSize`: its chevrons, 13 semibold. */
const CAPSULE_CHEVRON = 13;
const CAPSULE_CHEVRON_STROKE = 2.5;

/** How long Copied stands before the press reads Copy again, long enough to be seen and no longer. */
const COPIED_FOR_MS = 1_500;

/** `Keycap`: 11 medium on a rounded key, at least 18 square. */
export function Keycap({ label }: { label: string }) {
  return (
    <span className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-key border border-control-edge bg-keycap px-1.5 text-caption font-medium leading-none text-foreground">
      {label}
    </span>
  );
}

export function Keycaps({ keys, gap = KEY_SPACING }: { keys: readonly string[]; gap?: number }) {
  return (
    <span className="inline-flex items-center" style={{ gap }}>
      {keys.map((key) => (
        <Keycap key={key} label={key} />
      ))}
    </span>
  );
}

/** `IconTile`, as the console's stat icon: a square at radius 6 of the tint at 14%, its symbol in the tint. */
export function IconTile({ icon: Icon, tint = 'var(--color-primary)', size = TILE_SIDE }: { icon: LucideIcon; tint?: string; size?: number }) {
  return (
    <span
      className="grid shrink-0 place-items-center rounded-control"
      style={{ width: size, height: size, color: tint, backgroundColor: `color-mix(in oklab, ${tint} 14%, transparent)` }}
      aria-hidden
    >
      <Icon size={Math.round(size * TILE_SYMBOL_SHARE)} strokeWidth={TILE_SYMBOL_STROKE} />
    </span>
  );
}

/** `MemnoxTile`: the same tile holding the Memnox mark at 60% of its side. */
export function MemnoxTile({ size = TILE_SIDE }: { size?: number }) {
  return (
    <span className="grid shrink-0 place-items-center rounded-control bg-primary/[0.12]" style={{ width: size, height: size }} aria-hidden>
      <span
        className="block bg-primary"
        style={{ width: size * TILE_MARK_SHARE, height: size * TILE_MARK_SHARE, mask: `url("${MEMNOX_MARK}") center / contain no-repeat`, WebkitMask: `url("${MEMNOX_MARK}") center / contain no-repeat` }}
      />
    </span>
  );
}

/**
 * `StatusMark`: a 20 circle. Done is blue with a white tick; waiting a dashed ring of ink 50%; needs the
 * warm colour with a white mark.
 */
export function StatusMark({ state, size = CHECK_SIDE }: { state: StepState; size?: number }) {
  if (state.kind === 'done') {
    return (
      <span className="grid shrink-0 place-items-center rounded-full bg-primary text-white transition-transform duration-300" style={{ width: size, height: size }} aria-label={SettingsKitLines.done}>
        <Check size={size * CHECK_SYMBOL_SHARE} strokeWidth={CHECK_SYMBOL_STROKE} />
      </span>
    );
  }
  if (state.kind === 'needs') {
    return (
      <span className="grid shrink-0 place-items-center rounded-full bg-warm font-bold leading-none text-white" style={{ width: size, height: size, fontSize: size * CHECK_SYMBOL_SHARE }} aria-label={SettingsKitLines.needs}>
        {SettingsKitLines.needsMark}
      </span>
    );
  }
  return (
    <span className="block shrink-0 rounded-full" style={{ width: size, height: size, border: 'var(--mx-stroke-emphasis) dashed var(--mx-ink-tertiary)' }} aria-label={SettingsKitLines.notYet} />
  );
}

/** A needs hint under a row: a circled mark and the words, 11 medium at ink 92%. */
export function NeedsHint({ why, size = CAPTION_SIZE }: { why: string; size?: number }) {
  return (
    <p className="flex items-start gap-1 font-medium text-ink-primary" style={{ fontSize: size }}>
      <CircleAlert size={size} className="mt-px shrink-0" aria-hidden />
      <span className="select-text">{why}</span>
    </p>
  );
}

/** `KitCard.symbol`: the card's symbol at title size, in a column 20 wide. */
const KIT_SYMBOL = 17;

/**
 * `KitCard` from `OnboardingKit.swift`: one card at radius 16 and padding 16, its symbol, a 15 semibold title and a
 * 13 line at ink 62%, then its rows.
 */
export function KitCard({ icon: Icon, title, detail, children }: { icon?: LucideIcon; title?: string; detail?: string; children?: ReactNode }) {
  return (
    <section className="flex flex-col gap-4 rounded-setup bg-card p-4">
      {title !== undefined && (
        <div className="flex items-start gap-3">
          {Icon !== undefined && (
            <span className="flex w-5 shrink-0 justify-center text-ink-primary" aria-hidden>
              <Icon size={KIT_SYMBOL} strokeWidth={1.75} />
            </span>
          )}
          <div className="flex min-w-0 flex-col gap-0.5">
            <h3 className="text-headline font-semibold text-foreground">{title}</h3>
            {detail !== undefined && <p className="text-body text-ink-secondary">{detail}</p>}
          </div>
        </div>
      )}
      {children !== undefined && <div className="flex flex-col">{children}</div>}
    </section>
  );
}

/** `KitRow`: its tile, a 14 semibold title over a 12 line at ink 62%, then one control that keeps its width; 10 above and below. */
export function KitRow({ icon, title, detail, children }: { icon: LucideIcon; title: string; detail?: string; children?: ReactNode }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <IconTile icon={icon} />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-callout font-semibold text-foreground">{title}</span>
        {detail !== undefined && <span className="text-footnote text-ink-secondary">{detail}</span>}
      </div>
      {children !== undefined && <div className="ml-2 flex shrink-0 items-center gap-1.5">{children}</div>}
    </div>
  );
}

/** `KitDivider`: a hairline of ink 6% starting under the titles, the tile's side and 12 in. */
export function KitDivider() {
  return <div className="ml-[38px] h-px shrink-0 bg-ink-faint-fill" />;
}

/** The app tile's icon side and the check that marks the chosen one, as `AgentHomePicker` draws them. */
const APP_TILE_ICON = 36;
const APP_TILE_CHECK = 16;

/**
 * One app in `AgentHomePicker`: its icon 36 over its 12 semibold name, on a fill of ink 6% at radius 14, edged 2 in the
 * Memnox blue with a check at its corner once chosen.
 */
export function AppTile({ icon, name, chosen, hint, choose }: { icon: LucideIcon; name: string; chosen: boolean; hint: string; choose: () => void }) {
  return (
    <Pressable
      aria-pressed={chosen}
      aria-label={name}
      title={hint}
      onClick={choose}
      className={`mx-focus relative flex cursor-pointer flex-col items-center gap-1.5 rounded-tile bg-ink-faint-fill px-2 py-2 transition-transform duration-(--mx-duration-quick) active:scale-[0.97] ${chosen ? 'ring-2 ring-primary ring-inset' : ''}`}
    >
      <IconTile icon={icon} size={APP_TILE_ICON} />
      <span className="max-w-full truncate text-footnote font-semibold text-ink-primary">{name}</span>
      {chosen && (
        <span className="absolute top-1.5 right-1.5 text-primary" aria-hidden>
          <CheckCircle2 size={APP_TILE_CHECK} strokeWidth={2.25} />
        </span>
      )}
    </Pressable>
  );
}

/** `AgentHomePicker`'s grid: tiles at least 96 wide, 8 apart, 10 above and below. */
export function AppTileGrid({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-[repeat(auto-fill,minmax(96px,1fr))] gap-2 py-2.5">{children}</div>;
}

/** `SettingsCard`, as the console's setting card: a bordered white card at radius 12, padding 20, a 16 medium heading. */
export function SettingsCard({ title, children, className }: { title?: string; children: ReactNode; className?: string }) {
  return (
    <section className={`flex flex-col gap-4 rounded-card border border-panel-edge bg-card p-5 ${className ?? ''}`}>
      {title !== undefined && <h3 className="text-base font-medium text-foreground">{title}</h3>}
      {children}
    </section>
  );
}

/** `.surface()` inside Settings: radius 16 and the card fill with no padding of its own, rows carry it. */
export function Surface({ children, className }: { children: ReactNode; className?: string }) {
  return <section className={`overflow-hidden rounded-card border border-panel-edge bg-card ${className ?? ''}`}>{children}</section>;
}

/** `SettingsSection`: a 15 semibold title, something at its end on the baseline, then 10 to the card. */
export function SettingsSection({ title, trailing, children }: { title: string; trailing?: ReactNode; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between px-0.5">
        <h3 className="text-base font-medium text-foreground">{title}</h3>
        {trailing}
      </div>
      {children}
    </section>
  );
}

/** `SettingsRow`: a tile, 12, the title 13 over its caption 12 muted, then the accessory at the end. */
export function SettingsRow({
  icon,
  tile,
  tint,
  title,
  caption,
  children,
  titleClass,
}: {
  icon?: LucideIcon;
  tile?: ReactNode;
  tint?: string;
  title: ReactNode;
  caption?: ReactNode;
  children?: ReactNode;
  titleClass?: string;
}) {
  return (
    <div className="flex items-center gap-3">
      {tile ?? (icon !== undefined && <IconTile icon={icon} tint={tint} />)}
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className={titleClass ?? 'text-body-sm font-medium text-foreground'}>{title}</span>
        {caption !== undefined && <span className="text-meta leading-relaxed text-muted">{caption}</span>}
      </div>
      {children !== undefined && <div className="ml-3 flex shrink-0 items-center gap-1.5">{children}</div>}
    </div>
  );
}

/** `SwitchRow`: a SettingsRow whose switch the whole row flips, lit under the pointer. */
export function SwitchRow({
  icon,
  title,
  caption,
  on,
  onChange,
  disabled = false,
}: {
  icon: LucideIcon;
  title: string;
  caption: string;
  on: boolean;
  onChange: (on: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div
      className={`${HOVER_LIGHT} ${disabled ? 'pointer-events-none opacity-45' : 'cursor-pointer'}`}
      onClick={() => {
        if (!disabled) onChange(!on);
      }}
    >
      <SettingsRow icon={icon} title={title} caption={caption}>
        <Switch on={on} label={title} onChange={onChange} disabled={disabled} />
      </SettingsRow>
    </div>
  );
}

/** `SettingsDivider`: 1 px of the border colour, starting under the titles (38 in) or full width. */
export function SettingsDivider({ full = false }: { full?: boolean }) {
  return <div className={`h-px shrink-0 bg-border ${full ? '' : 'ml-[38px]'}`} />;
}

/** `HoverLight`: a rounded hover fill reaching 8 past the row on either side. */
export const HOVER_LIGHT =
  "relative before:pointer-events-none before:absolute before:inset-y-0 before:-inset-x-2 before:rounded-lg before:bg-hover before:opacity-0 before:transition-opacity before:duration-200 before:content-[''] hover:before:opacity-100";

/** `NavigationCapsule`: Back and Forward in one 69 by 32 capsule. */
export function NavigationCapsule({ canBack, canForward, back, forward }: { canBack: boolean; canForward: boolean; back: () => void; forward: () => void }) {
  const half = 'grid h-full flex-1 cursor-pointer place-items-center disabled:cursor-default';
  return (
    <div className="flex h-8 w-[69px] shrink-0 rounded-full border border-capsule-edge bg-capsule shadow-[0_1px_2px_rgba(0,0,0,.06)]">
      <Pressable className={`${half} ${canBack ? 'text-foreground' : 'text-faint'}`} disabled={!canBack} onClick={back} title={SettingsKitLines.back} aria-label={SettingsKitLines.back}>
        <ChevronLeft size={CAPSULE_CHEVRON} strokeWidth={CAPSULE_CHEVRON_STROKE} />
      </Pressable>
      <Pressable className={`${half} ${canForward ? 'text-foreground' : 'text-faint'}`} disabled={!canForward} onClick={forward} title={SettingsKitLines.forward} aria-label={SettingsKitLines.forward}>
        <ChevronRight size={CAPSULE_CHEVRON} strokeWidth={CAPSULE_CHEVRON_STROKE} />
      </Pressable>
    </div>
  );
}

/** A page's heading, as the console's page header: a 24 semibold title over its line 13 muted. */
export function PageTitle({ title, subtitle, eyebrow }: { title: string; subtitle: string; eyebrow?: string }) {
  return (
    <header className="flex flex-col">
      {eyebrow !== undefined && <p className="text-meta text-muted">{eyebrow}</p>}
      <h1 className={`text-2xl font-semibold tracking-[-0.02em] text-foreground ${eyebrow === undefined ? '' : 'mt-1'}`}>{title}</h1>
      <p className="mt-1.5 max-w-2xl text-body-sm leading-relaxed text-muted">{subtitle}</p>
    </header>
  );
}

/** A line of ink 62% at 11, as the Mac words a quiet note under a control. */
export function QuietLine({ children, size = CAPTION_SIZE }: { children: ReactNode; size?: number }) {
  return (
    <p className="text-ink-secondary" style={{ fontSize: size }}>
      {children}
    </p>
  );
}

/** Six digits as both screens show them: 26 semibold mono, tracking 2, in ink. */
export function Digits({ code, size = DIGITS_SIZE }: { code: string; size?: number }) {
  return (
    <span className="select-text font-code font-semibold tracking-[2px] text-ink" style={{ fontSize: size }}>
      {code}
    </span>
  );
}

/** Copies once and says so for a moment, for Copy link and Copy. */
export function useCopied(copy: (text: string) => Promise<void>): [boolean, (text: string) => void] {
  const [copied, setCopied] = useState(false);
  return [
    copied,
    (text: string) => {
      void copy(text).then(() => {
        setCopied(true);
        setTimeout(() => setCopied(false), COPIED_FOR_MS);
      });
    },
  ];
}
