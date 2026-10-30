import { Check, ChevronDown, ChevronLeft, ChevronRight, CircleAlert, CircleX, LoaderCircle, Search, type LucideIcon } from 'lucide-react';
import { useState, type ButtonHTMLAttributes, type ReactNode } from 'react';
import type { StepState } from '../../core/domain/step-state';
import { MEMNOX_MARK } from '../kit/logos';

/**
 * The pieces every Settings page and the first run are built from, each the web twin of one Swift view in
 * `Components/SettingsKit.swift`, `Components/Controls.swift` and `Onboarding/OnboardingKit.swift`, named as
 * the Mac names it. They read the adaptive palette, so Light, Dark and System repaint them.
 */

export type KitKind = 'primary' | 'secondary' | 'glass';

/** The console's button at its small size: 32 tall, radius 6, 13 medium, a soft blue ring when focused by key. */
const KIT_BASE =
  'inline-flex h-8 shrink-0 cursor-pointer select-none items-center justify-center gap-1.5 whitespace-nowrap rounded-lg px-3 text-body-sm font-medium leading-none outline-none transition-[opacity,background-color,border-color,box-shadow] duration-200 ease-out focus-visible:ring-[3px] focus-visible:ring-primary/30 disabled:cursor-default disabled:opacity-50';

const KIT_KIND: Record<KitKind, string> = {
  primary: 'bg-primary text-white shadow-[0_0_0_1px_var(--mx-ring,transparent)] enabled:hover:bg-primary/90',
  secondary: 'border border-control-edge bg-secondary text-foreground enabled:hover:border-[color-mix(in_oklab,var(--mx-foreground)_30%,transparent)] enabled:hover:bg-hover',
  glass: 'border border-white/[0.28] bg-white/10 text-white enabled:hover:shadow-[inset_0_0_0_999px_rgb(255_255_255/0.08)]',
};

export function kitButtonClass(kind: KitKind = 'secondary', wide = false): string {
  return `${KIT_BASE} ${KIT_KIND[kind]} ${wide ? 'w-full' : ''}`;
}

/** `KitButton`, in the console's shape: 32 tall at radius 6, 13 medium words, a leading icon 14, 6 before the word. */
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
      {Icon !== undefined && <Icon size={14} strokeWidth={2} aria-hidden />}
      {children}
      {Trailing !== undefined && <Trailing size={14} strokeWidth={2} aria-hidden />}
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

/** The console's switch: a squircle track blue when on and grey when off, its knob a tint of the blue on dark. */
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
      className={`mx-focus relative h-5 w-9 shrink-0 cursor-pointer rounded-[5px] transition-colors duration-200 disabled:cursor-default disabled:opacity-50 ${on ? 'bg-primary' : 'bg-[color-mix(in_oklab,var(--mx-muted)_40%,transparent)]'}`}
    >
      <span
        className={`absolute top-0.5 left-0.5 size-4 rounded-[4px] shadow-[0_1px_2px_rgba(0,0,0,.2)] transition-transform duration-200 ease-out ${on ? 'translate-x-4 bg-switch-knob' : 'bg-white'}`}
      />
    </button>
  );
}

/** `SearchField`, as the console's: a bordered field at radius 6 with a magnifier, and a clear button while there is text. */
export function SearchField({ value, placeholder, onChange }: { value: string; placeholder: string; onChange: (value: string) => void }) {
  return (
    <label className="mx-field-within flex h-9 items-center gap-2 rounded-lg border border-field-edge bg-field px-3">
      <Search size={14} className="shrink-0 text-muted" aria-hidden />
      <input
        className="min-w-0 flex-1 bg-transparent text-body-sm text-foreground outline-none placeholder:text-muted"
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

/** `KitField`, as the console's field: 36 tall at radius 6, white or the dark card, a blue border and soft ring when focused. */
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
      className={`mx-field h-9 min-w-0 rounded-lg border border-control-edge bg-raised px-3 text-body-sm text-foreground outline-none placeholder:text-muted focus:border-primary ${className ?? ''}`}
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

/** `IconTile`, as the console's stat icon: a square at radius 6 of the tint at 14%, its symbol in the tint. */
export function IconTile({ icon: Icon, tint = 'var(--color-primary)', size = 26 }: { icon: LucideIcon; tint?: string; size?: number }) {
  return (
    <span
      className="grid shrink-0 place-items-center rounded-lg"
      style={{ width: size, height: size, color: tint, backgroundColor: `color-mix(in oklab, ${tint} 14%, transparent)` }}
      aria-hidden
    >
      <Icon size={Math.round(size * 0.5)} strokeWidth={2} />
    </span>
  );
}

/** `MemnoxTile`: the same tile holding the Memnox mark at 60% of its side. */
export function MemnoxTile({ size = 26 }: { size?: number }) {
  return (
    <span className="grid shrink-0 place-items-center rounded-lg bg-primary/[0.12]" style={{ width: size, height: size }} aria-hidden>
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

/** `SettingsCard`, as the console's setting card: a bordered white card at radius 12, padding 20, a 16 medium heading. */
export function SettingsCard({ title, children, className }: { title?: string; children: ReactNode; className?: string }) {
  return (
    <section className={`flex flex-col gap-4 rounded-xl border border-panel-edge bg-card p-5 ${className ?? ''}`}>
      {title !== undefined && <h3 className="text-base font-medium text-foreground">{title}</h3>}
      {children}
    </section>
  );
}

/** `.surface()` inside Settings: radius 16 and the card fill with no padding of its own, rows carry it. */
export function Surface({ children, className }: { children: ReactNode; className?: string }) {
  return <section className={`overflow-hidden rounded-xl border border-panel-edge bg-card ${className ?? ''}`}>{children}</section>;
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
      className={`relative inline-flex h-8 shrink-0 cursor-pointer items-center justify-between gap-2 text-body-sm text-foreground ${plain ? '' : 'mx-field-within rounded-lg border border-control-edge bg-field px-3 hover:bg-hover'}`}
      style={width === undefined ? undefined : { width }}
    >
      <span className="truncate">{current}</span>
      <ChevronDown size={14} className="shrink-0 text-muted" aria-hidden />
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
