import { Ban, Check, CircleHelp, type LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { RULE_DIALOG } from '../../../core/domain/rule-dialog-lines';
import { DATA_CLASSIFICATIONS, fieldWords, RULES_FILE, toggledWord } from '../../../core/domain/rule-toml';
import { EFFECT_WORDS, type Effect } from '../../../core/domain/studio-lines';
import { KitButton } from '../../settings/kit';
import { CodeBlock } from '../code-block';

/** Each effect wears the console's glyph for it, the lucide stand in for the Mac's RuleSymbols.effect. */
export const EFFECT_ICONS: Record<Effect, LucideIcon> = { allow: Check, ask: CircleHelp, deny: Ban };

/** The console's field as the Mac's kitField draws it, in mono where it holds a pattern. */
export const RULE_FIELD = 'mx-field h-9 w-full min-w-0 rounded-lg border border-control-edge bg-raised px-3 text-body-sm text-foreground outline-none placeholder:text-muted focus:border-primary';
export const RULE_CODE_FIELD = `${RULE_FIELD} font-mono text-body`;

/**
 * A rule dialog's frame, as the Mac's RuleDialog: the title 18 semibold with its line under it, a hairline, the body
 * scrolling with 20 between its parts, a hairline, and Cancel and the confirm press sharing the foot. 560 wide, at most 720.
 */
export function RuleDialog({
  title,
  description,
  confirm = { idle: RULE_DIALOG.propose, busy: RULE_DIALOG.proposing },
  proposing,
  canPropose,
  close,
  propose,
  children,
}: {
  title: string;
  description: string;
  confirm?: { idle: string; busy: string };
  proposing: boolean;
  canPropose: boolean;
  close: () => void;
  propose: () => void;
  children: ReactNode;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 px-4 py-[8vh]"
      role="presentation"
      onMouseDown={close}
      onKeyDown={(event) => {
        if (event.key === 'Escape') close();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="flex max-h-[720px] w-full max-w-[560px] flex-col overflow-hidden rounded-xl border border-panel-edge bg-card shadow-[0_24px_60px_rgb(0_0_0/0.18)]"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <header className="flex shrink-0 flex-col gap-1 border-b border-panel-edge px-5 py-4">
          <span className="text-lg font-semibold text-foreground">{title}</span>
          <span className="text-footnote text-muted">{description}</span>
        </header>
        <div className="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto p-5">{children}</div>
        <footer className="flex shrink-0 items-center gap-2 border-t border-panel-edge px-5 py-3">
          <KitButton wide className="flex-1" onClick={close}>
            {RULE_DIALOG.cancel}
          </KitButton>
          <KitButton kind="primary" wide className="flex-1" disabled={!canPropose || proposing} onClick={propose}>
            {proposing ? confirm.busy : confirm.idle}
          </KitButton>
        </footer>
      </div>
    </div>
  );
}

/** A field's label in the console's weight, with the muted "(optional)" where it may stay empty. */
export function RuleLegend({ text, optional = false }: { text: string; optional?: boolean }) {
  return (
    <span className="flex items-center gap-1 text-body-sm font-medium" role="heading" aria-level={3}>
      <span className="text-foreground">{text}</span>
      {optional && <span className="text-muted">{RULE_DIALOG.optional}</span>}
    </span>
  );
}

/** The line under a field saying what it means, in the console's muted meta size. */
export function RuleHint({ text }: { text: string }) {
  return <p className="text-meta text-muted">{text}</p>;
}

/** One labelled field: its legend, the control, and the line saying what it means, 6 apart. */
export function RuleField({ label, optional = false, hint, children }: { label: string; optional?: boolean; hint?: string; children: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      <RuleLegend text={label} optional={optional} />
      {children}
      {hint !== undefined && <RuleHint text={hint} />}
    </div>
  );
}

/** The rule in the runtime's own file format under its legend, so what is proposed is never a guess. */
export function RulePreview({ code, title = RULE_DIALOG.preview, copy }: { code: string; title?: string; copy?: (text: string) => Promise<void> }) {
  return (
    <div className="flex flex-col gap-1.5">
      <RuleLegend text={title} />
      <CodeBlock code={code} label={RULES_FILE} maxHeight={320} {...(copy === undefined ? {} : { copy })} />
    </div>
  );
}

/** One effect as a described card, the chosen one outlined in the console's blue over a 5 percent wash. */
function RuleEffectCard({ effect, chosen, recommended, choose }: { effect: Effect; chosen: boolean; recommended: boolean; choose: () => void }) {
  const Icon = EFFECT_ICONS[effect];
  return (
    <button
      type="button"
      role="radio"
      aria-checked={chosen}
      onClick={choose}
      className={`mx-focus flex min-w-0 flex-1 cursor-pointer flex-col items-start gap-1 rounded-xl border p-3 text-left ${chosen ? 'border-primary bg-[color-mix(in_oklab,var(--color-primary)_5%,transparent)]' : 'border-panel-edge'}`}
    >
      <span className="flex w-full items-center gap-1.5 text-foreground">
        <Icon size={13} strokeWidth={2} aria-hidden />
        <span className="text-body-sm font-medium">{EFFECT_WORDS[effect].title}</span>
        {recommended && <span className="ml-auto pl-1.5 text-meta text-muted">{RULE_DIALOG.recommended}</span>}
      </span>
      <span className="text-meta text-muted">{EFFECT_WORDS[effect].says}</span>
    </button>
  );
}

/** The effects as a row of cards under their legend, one chosen. */
export function RuleEffectChoice({ chosen, choose, recommended }: { chosen: Effect; choose: (effect: Effect) => void; recommended?: Effect }) {
  return (
    <div className="flex flex-col gap-2">
      <RuleLegend text={RULE_DIALOG.whenTried} />
      <div role="radiogroup" aria-label={RULE_DIALOG.whenTried} className="flex items-stretch gap-2">
        {(Object.keys(EFFECT_WORDS) as Effect[]).map((each) => (
          <RuleEffectCard key={each} effect={each} chosen={chosen === each} recommended={each === recommended} choose={() => choose(each)} />
        ))}
      </div>
    </div>
  );
}

/** The console's filter chip as the Mac's FilterChip draws it there: 32 tall at radius 6, the chosen one washed blue. */
export function ConsoleChip({ title, chosen, choose }: { title: string; chosen: boolean; choose: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={chosen}
      onClick={choose}
      className={`mx-focus inline-flex h-8 shrink-0 cursor-pointer items-center rounded-md border px-3 text-body-sm transition-colors ${
        chosen
          ? 'border-[color-mix(in_oklab,var(--color-primary)_45%,transparent)] bg-[color-mix(in_oklab,var(--color-primary)_7%,transparent)] font-medium text-foreground'
          : 'border-panel-edge bg-card text-muted hover:bg-hover'
      }`}
    >
      {title}
    </button>
  );
}

/** The runtime's data words as round chips over the same comma separated text, so a press and a typed name are one field. */
export function DataClassChips({ text, setText }: { text: string; setText: (next: string) => void }) {
  const chosen = fieldWords(text) ?? [];
  return (
    <div className="flex flex-wrap gap-1.5" role="group" aria-label="Data it carries">
      {DATA_CLASSIFICATIONS.map((word) => {
        const on = chosen.includes(word);
        return (
          <button
            key={word}
            type="button"
            aria-pressed={on}
            onClick={() => setText(toggledWord(word, text))}
            className={`mx-focus inline-flex h-[30px] cursor-pointer items-center rounded-full border px-3 text-meta transition-colors ${
              on ? 'border-primary bg-[color-mix(in_oklab,var(--color-primary)_10%,transparent)] text-foreground' : 'border-border text-muted hover:bg-hover hover:text-foreground'
            }`}
          >
            {word}
          </button>
        );
      })}
    </div>
  );
}
