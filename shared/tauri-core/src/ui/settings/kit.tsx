import { Check, ChevronLeft, ChevronRight, ChevronsUpDown, CircleAlert, CircleX, LoaderCircle, Search, type LucideIcon } from 'lucide-react';
import { useState, type ButtonHTMLAttributes, type ReactNode } from 'react';
import type { StepState } from '../../core/domain/step-state';
import { MEMNOX_MARK } from '../kit/logos';

/**
 * The pieces every Settings page and the first run are built from, each the web twin of one Swift view in
 * `Components/SettingsKit.swift`, `Components/Controls.swift` and `Onboarding/OnboardingKit.swift`, named as
 * the Mac names it. They read the adaptive palette, so Light, Dark and System repaint them.
 */

export type KitKind = 'primary' | 'secondary' | 'glass';

const KIT_BASE =
  'inline-flex h-7 shrink-0 cursor-pointer select-none items-center justify-center gap-1.5 whitespace-nowrap rounded-full px-3.5 text-body leading-none transition-[opacity,box-shadow,scale] duration-200 ease-out enabled:active:scale-[0.97] disabled:cursor-default';

const KIT_KIND: Record<KitKind, string> = {
  primary: 'bg-primary font-semibold text-white enabled:hover:opacity-[0.88] disabled:opacity-40',
  secondary:
    'border border-control-edge bg-secondary text-foreground enabled:hover:shadow-[inset_0_0_0_999px_var(--mx-ink-fill)] disabled:bg-[color-mix(in_srgb,var(--mx-secondary)_50%,transparent)] disabled:text-faint',
  glass: 'border border-white/[0.28] bg-white/10 text-white enabled:hover:shadow-[inset_0_0_0_999px_rgb(255_255_255/0.08)]',
};

export function kitButtonClass(kind: KitKind = 'secondary', wide = false): string {
  return `${KIT_BASE} ${KIT_KIND[kind]} ${wide ? 'w-full' : ''}`;
}

/** `KitButton`: a 28 tall capsule, 13 words, semibold when primary; a leading icon 12 semibold, 6 before the word. */
export function KitButton({
  kind = 'secondary',
  icon: Icon,
  trailing: Trailing,
  wide = false,
  children,
  className,
  ...rest
}: { kind?: KitKind; icon?: LucideIcon; trailing?: LucideIcon; wide?: boolean } & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button type="button" className={`${kitButtonClass(kind, wide)} ${className ?? ''}`} {...rest}>
      {Icon !== undefined && <Icon size={12} strokeWidth={2.6} aria-hidden />}
      {children}
      {Trailing !== undefined && <Trailing size={12} strokeWidth={2.6} aria-hidden />}
    </button>
  );
}

/** `Keycap`: 11 medium on a rounded key, at least 18 square. */
export function Keycap({ label }: { label: string }) {
  return (
    <span className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-[4px] border border-control-edge bg-keycap px-1.5 text-caption font-medium leading-none text-foreground">
      {label}
    </span>
  );
}

export function Keycaps({ keys, gap = 3 }: { keys: readonly string[]; gap?: number }) {
  return (
    <span className="inline-flex items-center" style={{ gap }}>
      {keys.map((key) => (
        <Keycap key={key} label={key} />
      ))}
    </span>
  );
}

/** A small spinner, the Mac's `ProgressView().controlSize(.small)`. */
export function Spinner({ size = 14 }: { size?: number }) {
  return <LoaderCircle size={size} className="shrink-0 animate-spin text-muted" aria-label="Working" />;
}

/** `MemnoxSwitch`: a 34 by 20 track, blue when on, ink 14% when off, with a 16 white knob that springs across. */
export function Switch({ on, label, onChange, disabled = false }: { on: boolean; label: string; onChange: (on: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={(event) => {
        event.stopPropagation();
        onChange(!on);
      }}
      className={`relative h-5 w-[34px] shrink-0 cursor-pointer rounded-full transition-colors duration-200 disabled:cursor-default ${on ? 'bg-primary' : 'bg-ink-edge'}`}
    >
      <span
        className={`absolute top-0.5 left-0.5 size-4 rounded-full bg-white shadow-[0_1px_1px_rgba(0,0,0,.25)] transition-transform duration-[250ms] ease-[cubic-bezier(.34,1.3,.64,1)] ${on ? 'translate-x-[14px]' : ''}`}
      />
    </button>
  );
}

/** `SearchField`: a capsule of the field fill with a magnifier, and a clear button while there is text. */
export function SearchField({ value, placeholder, onChange }: { value: string; placeholder: string; onChange: (value: string) => void }) {
  return (
    <label className="flex h-7 items-center gap-1.5 rounded-full border border-field-edge bg-field px-[9px]">
      <Search size={13} className="shrink-0 text-muted" aria-hidden />
      <input
        className="min-w-0 flex-1 bg-transparent text-body text-foreground outline-none placeholder:text-muted"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        aria-label={placeholder}
      />
      {value !== '' && (
        <button type="button" className="grid cursor-pointer text-muted" onClick={() => onChange('')} aria-label="Clear">
          <CircleX size={13} fill="currentColor" className="text-muted [&>path]:stroke-background" />
        </button>
      )}
    </label>
  );
}

/** `KitField`: at least 28 tall, radius 7, the raised fill, a 1 px blue edge while focused and never thicker. */
export function KitField({
  value,
  placeholder,
  onChange,
  onSubmit,
  width,
  className,
  autoFocus,
}: {
  value: string;
  placeholder: string;
  onChange: (value: string) => void;
  onSubmit?: () => void;
  width?: number;
  className?: string;
  autoFocus?: boolean;
}) {
  return (
    <input
      className={`h-7 min-w-0 rounded-[7px] border border-control-edge bg-raised px-2.5 text-body text-foreground outline-none placeholder:text-muted focus:border-primary ${className ?? ''}`}
      style={width === undefined ? undefined : { width }}
      value={value}
      placeholder={placeholder}
      autoFocus={autoFocus}
      onChange={(event) => onChange(event.target.value)}
      onKeyDown={(event) => {
        if (event.key === 'Enter') onSubmit?.();
      }}
      aria-label={placeholder}
    />
  );
}

/** `IconTile`: a 26 square at radius 7 of the tint at 12%, its symbol 12 semibold in the tint. */
export function IconTile({ icon: Icon, tint = 'var(--color-primary)', size = 26 }: { icon: LucideIcon; tint?: string; size?: number }) {
  return (
    <span
      className="grid shrink-0 place-items-center rounded-[7px]"
      style={{ width: size, height: size, color: tint, backgroundColor: `color-mix(in srgb, ${tint} 12%, transparent)` }}
      aria-hidden
    >
      <Icon size={12} strokeWidth={2.4} />
    </span>
  );
}

/** `MemnoxTile`: the same tile holding the Memnox mark at 60% of its side. */
export function MemnoxTile({ size = 26 }: { size?: number }) {
  return (
    <span className="grid shrink-0 place-items-center rounded-[7px] bg-primary/[0.12]" style={{ width: size, height: size }} aria-hidden>
      <span
        className="block bg-primary"
        style={{ width: size * 0.6, height: size * 0.6, mask: `url("${MEMNOX_MARK}") center / contain no-repeat`, WebkitMask: `url("${MEMNOX_MARK}") center / contain no-repeat` }}
      />
    </span>
  );
}

/**
 * `StatusMark`: a 20 circle. Done is blue with a white tick; waiting a dashed ring of ink 50%; needs the
 * warm colour with a white mark.
 */
export function StatusMark({ state, size = 20 }: { state: StepState; size?: number }) {
  if (state.kind === 'done') {
    return (
      <span className="grid shrink-0 place-items-center rounded-full bg-primary text-white transition-transform duration-300" style={{ width: size, height: size }} aria-label="Done">
        <Check size={size * 0.55} strokeWidth={3.4} />
      </span>
    );
  }
  if (state.kind === 'needs') {
    return (
      <span className="grid shrink-0 place-items-center rounded-full bg-warm text-[11px] font-bold leading-none text-white" style={{ width: size, height: size }} aria-label="Needs you">
        !
      </span>
    );
  }
  return (
    <span className="block shrink-0 rounded-full" style={{ width: size, height: size, border: '1.5px dashed var(--mx-ink-tertiary)' }} aria-label="Not yet" />
  );
}

/** A needs hint under a row: a circled mark and the words, 11 medium at ink 92%. */
export function NeedsHint({ why, size = 11 }: { why: string; size?: number }) {
  return (
    <p className="flex items-start gap-1 font-medium text-ink-primary" style={{ fontSize: size }}>
      <CircleAlert size={size} className="mt-px shrink-0" aria-hidden />
      <span className="select-text">{why}</span>
    </p>
  );
}

/** `SettingsCard`: padding 16, radius 16, the card fill, an optional 15 semibold heading, 13 between items. */
export function SettingsCard({ title, children, className }: { title?: string; children: ReactNode; className?: string }) {
  return (
    <section className={`flex flex-col gap-[13px] rounded-2xl bg-card p-4 ${className ?? ''}`}>
      {title !== undefined && <h3 className="text-headline font-semibold text-foreground">{title}</h3>}
      {children}
    </section>
  );
}

/** `.surface()` inside Settings: radius 16 and the card fill with no padding of its own, rows carry it. */
export function Surface({ children, className }: { children: ReactNode; className?: string }) {
  return <section className={`overflow-hidden rounded-2xl bg-card ${className ?? ''}`}>{children}</section>;
}

/** `SettingsSection`: a 15 semibold title, something at its end on the baseline, then 10 to the card. */
export function SettingsSection({ title, trailing, children }: { title: string; trailing?: ReactNode; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between px-0.5">
        <h3 className="text-headline font-semibold text-foreground">{title}</h3>
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
        <span className={titleClass ?? 'text-body text-foreground'}>{title}</span>
        {caption !== undefined && <span className="text-footnote text-muted">{caption}</span>}
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
      <button type="button" className={`${half} ${canBack ? 'text-foreground' : 'text-faint'}`} disabled={!canBack} onClick={back} title="Back" aria-label="Back">
        <ChevronLeft size={15} strokeWidth={2.5} />
      </button>
      <button type="button" className={`${half} ${canForward ? 'text-foreground' : 'text-faint'}`} disabled={!canForward} onClick={forward} title="Forward" aria-label="Forward">
        <ChevronRight size={15} strokeWidth={2.5} />
      </button>
    </div>
  );
}

/** `SelectMenu`: a capsule showing the choice with an up and down chevron, opening the system's own list. */
export function SelectMenu<T extends string>({
  value,
  options,
  onChange,
  label,
  width,
  plain = false,
}: {
  value: T;
  options: readonly { value: T; label: string; divider?: boolean }[];
  onChange: (value: T) => void;
  label: string;
  width?: number;
  plain?: boolean;
}) {
  const current = options.find((option) => option.value === value)?.label ?? '';
  return (
    <label
      className={`relative inline-flex h-7 shrink-0 cursor-pointer items-center justify-between gap-1.5 text-body text-foreground ${plain ? '' : 'rounded-full border border-control-edge bg-secondary px-3.5 hover:shadow-[inset_0_0_0_999px_var(--mx-hover)]'}`}
      style={width === undefined ? undefined : { width }}
    >
      <span className="truncate">{current}</span>
      <ChevronsUpDown size={10} strokeWidth={2.5} className="shrink-0 text-muted" aria-hidden />
      <select className="absolute inset-0 cursor-pointer opacity-0" value={value} aria-label={label} onChange={(event) => onChange(event.target.value as T)}>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}

/** A page's own column title: 19 bold over its line 13 muted. */
export function PageTitle({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <header className="flex flex-col gap-1">
      <h1 className="text-[19px] font-bold text-foreground">{title}</h1>
      <p className="text-body text-muted">{subtitle}</p>
    </header>
  );
}

/** A line of ink 62% at 11, as the Mac words a quiet note under a control. */
export function QuietLine({ children, size = 11 }: { children: ReactNode; size?: number }) {
  return (
    <p className="text-ink-secondary" style={{ fontSize: size }}>
      {children}
    </p>
  );
}

/** Six digits as both screens show them: 26 semibold mono, tracking 2, in ink. */
export function Digits({ code, size = 26 }: { code: string; size?: number }) {
  return (
    <span className="select-text font-mono font-semibold tracking-[2px] text-ink" style={{ fontSize: size }}>
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
        setTimeout(() => setCopied(false), 1_500);
      });
    },
  ];
}
