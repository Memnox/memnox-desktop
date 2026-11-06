import { Check, ChevronDown, ChevronsUpDown, CircleX, Search } from 'lucide-react';
import {
  forwardRef,
  useLayoutEffect,
  useRef,
  type ChangeEvent,
  type InputHTMLAttributes,
  type KeyboardEvent,
  type ReactNode,
  type TextareaHTMLAttributes,
} from 'react';
import { showingLine } from '../../core/domain/catalog';
import { KitLines } from '../../core/domain/kit-lines';

/**
 * `field` is the Mac's `KitField` in the console look: 36 tall at radius 6, 12 inside, the raised fill under a
 * hairline that turns blue with the soft ring while it has the keyboard. `bare` draws nothing, for a field inside a
 * frame that draws itself, such as a search's or the island's.
 */
export type FieldLook = 'field' | 'bare';

const FIELD_LOOK: Record<FieldLook, string> = {
  field: 'mx-field h-field rounded-control border border-control-edge bg-raised px-3 text-body-sm text-foreground outline-none placeholder:text-faint',
  bare: 'border-0 outline-none',
};

interface FieldLookProps {
  look?: FieldLook;
  /** A pattern, a path or a command, read in the console's code face, as `Memnox.Console.code`. */
  mono?: boolean;
  /** The full width of whatever holds it. */
  wide?: boolean;
}

function fieldClass({ look = 'field', mono = false, wide = false }: FieldLookProps): string {
  return `${FIELD_LOOK[look]} ${mono ? 'font-code' : ''} ${wide ? 'w-full' : ''}`;
}

export interface InputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'width'>, FieldLookProps {
  /** The words as they change, which is all most fields want of the change event. */
  onValue?: (value: string) => void;
  /** Return in the field, as the Mac's `onSubmit`. */
  onSubmit?: () => void;
  /** A fixed width in points, where the Mac gives the field one. */
  width?: number;
}

/** `KitField`, as the console's field: 36 tall at radius 6, a blue border and soft ring when focused. */
export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { look, mono, wide, onValue, onSubmit, onChange, onKeyDown, width, className, style, placeholder, type = 'text', ...rest },
  ref,
) {
  const changed = (event: ChangeEvent<HTMLInputElement>) => {
    onChange?.(event);
    onValue?.(event.target.value);
  };
  const keyed = (event: KeyboardEvent<HTMLInputElement>) => {
    onKeyDown?.(event);
    if (event.key === 'Enter') onSubmit?.();
  };
  return (
    <input
      ref={ref}
      type={type}
      className={`min-w-0 ${fieldClass({ look, mono, wide })} ${className ?? ''}`}
      style={width === undefined ? style : { ...style, width }}
      placeholder={placeholder}
      aria-label={rest['aria-label'] ?? placeholder}
      onChange={changed}
      onKeyDown={keyed}
      {...rest}
    />
  );
});

export interface TextareaProps extends Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'value'> {
  value: string;
  onValue?: (value: string) => void;
  /** `field` is the console's editor; `bare` draws nothing, for a frame that draws itself. */
  look?: FieldLook;
  mono?: boolean;
  /** Grows with what is typed, up to the height its class allows, so a long entry is read without a scroll bar. */
  grow?: boolean;
}

/** `ConsoleEditor`: 6 inside a bordered field at radius 6, its border blue with a soft ring while it is typed in. */
const EDITOR = 'mx-field w-full rounded-control border border-field-edge bg-field p-1.5 text-body-sm text-foreground outline-none placeholder:text-faint';

/** A field for more than a line, growing with its words where asked. */
export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea({ look = 'field', mono = false, onValue, onChange, grow = false, className, value, ...rest }, ref) {
  const own = useRef<HTMLTextAreaElement | null>(null);
  useLayoutEffect(() => {
    const area = own.current;
    if (!grow || area === null) return;
    area.style.height = 'auto';
    area.style.height = `${area.scrollHeight}px`;
    // Past the height its class caps it at, the words scroll rather than being cut.
    area.style.overflowY = area.scrollHeight > area.clientHeight ? 'auto' : 'hidden';
  }, [grow, value]);
  return (
    <textarea
      ref={(element) => {
        own.current = element;
        if (typeof ref === 'function') ref(element);
        else if (ref !== null) ref.current = element;
      }}
      className={`${look === 'field' ? EDITOR : FIELD_LOOK.bare} ${mono ? 'font-code' : ''} ${grow ? 'resize-none' : ''} ${className ?? ''}`}
      value={value}
      onChange={(event) => {
        onChange?.(event);
        onValue?.(event.target.value);
      }}
      {...rest}
    />
  );
});

/** One choice of a select. */
export interface SelectOption<T extends string> {
  readonly value: T;
  readonly label: string;
}

/**
 * How a select is drawn, each a Mac face: `menu` is `SelectFace` in the console (the choice and one chevron down),
 * `field` is `ConsoleSelect` (the choice across the field, the double chevron at its end), `plain` is the menu's
 * words with no frame, and `popup` is the small pop up of the voice pages, 28 tall on an ink fill.
 */
export type SelectLook = 'menu' | 'field' | 'plain' | 'popup';

const SELECT_LOOK: Record<SelectLook, string> = {
  menu: 'mx-field-within h-control gap-2 rounded-control border border-control-edge bg-field px-3 text-body-sm text-foreground transition-colors duration-(--mx-duration-quick) ease-out hover:bg-hover',
  field: 'mx-field-within h-control gap-1.5 rounded-control border border-control-edge bg-field px-3 text-body-sm text-foreground transition-colors duration-(--mx-duration-quick) ease-out hover:bg-hover',
  plain: 'h-control gap-2 text-body-sm text-foreground',
  popup: 'h-7 rounded-[9px] border border-ink-fill bg-ink-faint-fill px-3',
};

/** `SelectFace`'s chevron is caption sized and medium; `ConsoleSelect`'s double chevron micro and semibold. */
const MENU_CHEVRON = 11;
const MENU_CHEVRON_STROKE = 2;
const FIELD_CHEVRON = 10;
const FIELD_CHEVRON_STROKE = 2.5;

/** The choice drawn as the Mac draws it, opening the system's own list from a select laid over it. */
export function Select<T extends string>({
  value,
  options,
  onChange,
  label,
  width,
  look = 'menu',
  wide = false,
  none,
}: {
  value: T;
  options: readonly SelectOption<T>[];
  onChange: (value: T) => void;
  label: string;
  width?: number;
  look?: SelectLook;
  /** The full width of whatever holds it, as a form's select is. */
  wide?: boolean;
  /** A first choice standing for none, as "No profile" or "Any agent", whose value is empty. */
  none?: string;
}) {
  const all: readonly SelectOption<string>[] = none === undefined ? options : [{ value: '', label: none }, ...options];
  const current = all.find((option) => option.value === value)?.label ?? all[0]?.label ?? '';
  const chevron =
    look === 'popup' || look === 'field' ? (
      <ChevronsUpDown size={FIELD_CHEVRON} strokeWidth={FIELD_CHEVRON_STROKE} className="shrink-0 text-muted" aria-hidden />
    ) : (
      <ChevronDown size={MENU_CHEVRON} strokeWidth={MENU_CHEVRON_STROKE} className="shrink-0 text-muted" aria-hidden />
    );
  return (
    <label
      className={`relative inline-flex shrink-0 cursor-pointer items-center justify-between ${SELECT_LOOK[look]} ${wide ? 'w-full' : ''}`}
      style={width === undefined ? undefined : { width }}
      title={label}
    >
      <span className={`truncate ${look === 'popup' ? 'text-callout text-foreground' : ''}`}>{current}</span>
      {chevron}
      <SelectOverlay value={value} options={all} label={label} onValue={(next) => onChange(next as T)} />
    </label>
  );
}

/**
 * The system's own list, unseen and laid over whatever its parent draws, so a glyph or a custom face opens it. The
 * parent must be positioned. `blank` adds an empty first choice, for a list that only offers words to a field.
 */
export function SelectOverlay({ value, options, label, onValue, blank = false }: { value: string; options: readonly SelectOption<string>[]; label: string; onValue: (value: string) => void; blank?: boolean }) {
  return (
    <select className="absolute inset-0 cursor-pointer opacity-0" value={value} aria-label={label} onChange={(event) => onValue(event.target.value)}>
      {blank && <option value="" />}
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  );
}

/** `CheckboxFace`'s square, its corner and the tick in it. */
const CHECKBOX_TICK = 9;
const CHECKBOX_TICK_STROKE = 3.5;

/**
 * `CheckboxStyle`: a 14 square at radius 4, the brand blue with a white tick when on, the field fill under the rim
 * when off, its words 13 after it, 6 apart. The whole row presses.
 */
export function Checkbox({
  checked,
  onToggle,
  disabled,
  label,
  title,
  children,
}: {
  checked: boolean;
  onToggle: () => void;
  disabled?: boolean;
  /** Needed only where no words beside it name it. */
  label?: string;
  title?: string;
  /** The words after the square, or a logo and the words. */
  children?: ReactNode;
}) {
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={checked}
      aria-label={label}
      title={title}
      disabled={disabled}
      onClick={onToggle}
      className="mx-focus inline-flex cursor-pointer items-center gap-1.5 text-left text-body-sm text-foreground disabled:cursor-default disabled:opacity-50"
    >
      <span className={`grid size-3.5 shrink-0 place-items-center rounded-key ${checked ? 'bg-primary text-white' : 'border border-rim bg-field'}`} aria-hidden>
        {checked && <Check size={CHECKBOX_TICK} strokeWidth={CHECKBOX_TICK_STROKE} />}
      </span>
      {children}
    </button>
  );
}

/** A round choice as the system draws it, for one of a few that exclude each other. */
export function Radio({ name, checked, onPick, disabled, className }: { name: string; checked: boolean; onPick: () => void; disabled?: boolean; className?: string }) {
  return <input type="radio" name={name} checked={checked} disabled={disabled} className={className} onChange={onPick} />;
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

/** The magnifier and the clear mark in a search field, a little smaller than a button's glyph. */
const SEARCH_GLYPH = 14;
const CLEAR_GLYPH = 13;

/**
 * `SearchField`, as the console's: a bordered field at radius 6 with a magnifier, and a clear button while there is
 * text. With `count` it says beside it how much of the pool is on screen, as "N of M".
 */
export function SearchInput({ value, placeholder, onChange, count }: { value: string; placeholder: string; onChange: (value: string) => void; count?: { shown: number; total: number } }) {
  const field = (
    <label className="mx-field-within flex h-field items-center gap-2 rounded-control border border-field-edge bg-field px-3">
      <Search size={SEARCH_GLYPH} className="shrink-0 text-muted" aria-hidden />
      <Input look="bare" className="flex-1 text-body-sm text-foreground placeholder:text-muted" value={value} placeholder={placeholder} onValue={onChange} />
      {value !== '' && (
        <button type="button" className="grid cursor-pointer text-muted" onClick={() => onChange('')} aria-label={KitLines.clear}>
          <CircleX size={CLEAR_GLYPH} fill="currentColor" className="text-muted [&>path]:stroke-background" />
        </button>
      )}
    </label>
  );
  if (count === undefined) return field;
  return (
    <div className="flex items-center gap-3">
      <div className="min-w-0 flex-1">{field}</div>
      <p className="shrink-0 font-mono text-label tabular-nums text-muted" aria-live="polite">
        {showingLine(count.shown, count.total)}
      </p>
    </div>
  );
}

/** A field with its label over it, and what helps or what went wrong under it. */
export function Field({ label, help, error, children }: { label: string; help?: ReactNode; error?: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      {children}
      {help !== undefined && <span className="text-footnote text-muted">{help}</span>}
      {error !== undefined && (
        <span role="alert" className="text-footnote text-destructive">
          {error}
        </span>
      )}
    </label>
  );
}

/** The system's file chooser, unseen: opened by the label around it or by `click()` on its ref. */
export const FilePicker = forwardRef<HTMLInputElement, { accept: string; onFile: (file: File | undefined) => void; className?: string }>(function FilePicker({ accept, onFile, className = 'hidden' }, ref) {
  return (
    <input
      ref={ref}
      type="file"
      accept={accept}
      className={className}
      onChange={(event) => onFile(event.target.files?.[0])}
    />
  );
});

/** A slider over a range of numbers, tinted the brand blue. */
export function Slider({ value, min, max, step, label, disabled, onValue, className }: { value: number; min: number; max: number; step: number; label: string; disabled?: boolean; onValue: (value: number) => void; className?: string }) {
  return (
    <input
      type="range"
      aria-label={label}
      min={min}
      max={max}
      step={step}
      value={value}
      disabled={disabled}
      onChange={(event) => onValue(Number(event.target.value))}
      className={`accent-[var(--color-primary)] disabled:opacity-40 ${className ?? ''}`}
    />
  );
}
