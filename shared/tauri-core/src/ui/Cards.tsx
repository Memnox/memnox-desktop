import { useState, useSyncExternalStore } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Check, MapPin, Send, TriangleAlert, X } from 'lucide-react';
import { button, note } from './ui';
import type { RuleDraft, WorkDraft } from '@memnox/core/wire';
import { accountWarning, draftAudience, suggestedScope, type HeldOutcome, type ProposalCards } from '../core';

/** Every card sits under a rule rather than in a box of its own, as cards do in memnox-client. */
const CARD = 'grid gap-1.5 border-t border-line pt-2.5';

/** What each kind of draft is called on its card. */
const KIND_WORDS: Record<WorkDraft['kind'], string> = {
  message: 'A message',
  comment: 'A comment',
  email: 'An email',
  issue: 'An issue',
  other: 'Something to send',
};

/** What a card says after a press, in the person's words. */
function told(outcome: HeldOutcome): string | undefined {
  if (outcome.kind === 'answered') return undefined;
  if (outcome.kind === 'answered-elsewhere') return outcome.earlier.line;
  if (outcome.kind === 'cancelled') return 'Nothing was sent, so it is still waiting.';
  return `That did not go through: ${outcome.why}`;
}

/** The newest proposal waiting on its card, read whole before the key is asked. */
export function Cards({ cards }: { cards: ProposalCards }) {
  const all = useSyncExternalStore(
    (changed) => cards.observe(changed),
    () => cards.cards,
  );
  const card = all[all.length - 1];
  if (card === undefined) return null;
  // Keyed by subject, so a new card never inherits the last one's choice or edits.
  return card.kind === 'rule' ? (
    <RuleCard key={card.subject} subject={card.subject} rule={card.rule} cards={cards} />
  ) : (
    <WorkCard key={card.subject} subject={card.subject} work={card.work} cards={cards} />
  );
}

function RuleCard({ subject, rule, cards }: { subject: string; rule: RuleDraft; cards: ProposalCards }) {
  const [scope, setScope] = useState(suggestedScope(rule)?.id);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string>();

  async function answer(scopeId: string | undefined) {
    setBusy(true);
    setSaid(told(await cards.answerRule(subject, scopeId)));
    setBusy(false);
  }

  return (
    <article className={CARD}>
      <p className="text-xs text-muted">A rule to put in force</p>
      <p className="text-[15px] font-semibold">{rule.summary}</p>
      <p className="text-muted">{rule.reason}</p>
      <fieldset className="m-0 grid gap-1 border-0 p-0">
        <legend className="flex items-center gap-1.5 p-0 text-xs text-muted">
          <MapPin size={12} /> Where it holds
        </legend>
        {rule.scopes.map((each) => (
          <label key={each.id} className="flex cursor-pointer items-center gap-2">
            <input
              type="radio"
              className="accent-primary"
              name={`scope-${subject}`}
              checked={scope === each.id}
              onChange={() => setScope(each.id)}
            />
            {each.label}
          </label>
        ))}
      </fieldset>
      <nav className="grid grid-cols-2 gap-2">
        <button className={button('quiet')} disabled={busy} onClick={() => void answer(undefined)}>
          <X size={14} /> Leave it out
        </button>
        <button className={button('primary')} disabled={busy || scope === undefined} onClick={() => void answer(scope)}>
          <Check size={14} /> Put in force
        </button>
      </nav>
      {said !== undefined && <p className={note}>{said}</p>}
    </article>
  );
}

function WorkCard({ subject, work, cards }: { subject: string; work: WorkDraft; cards: ProposalCards }) {
  const drafted = work.body ?? '';
  const [body, setBody] = useState(drafted);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string>();
  const warning = accountWarning(work);

  async function answer(send: boolean) {
    setBusy(true);
    // Words go with the Send only when the person changed them, so the signature covers what really leaves.
    setSaid(told(await cards.answerDraft(subject, send, send && body !== drafted ? body : undefined)));
    setBusy(false);
  }

  return (
    <article className={CARD}>
      <p className="text-xs text-muted">
        {KIND_WORDS[work.kind]} to {draftAudience(work)}
      </p>
      {work.subject !== undefined && <p className="text-[15px] font-semibold">{work.subject}</p>}
      {warning !== undefined && (
        <p className={note}>
          <TriangleAlert size={13} className="mt-px shrink-0" /> {warning}
        </p>
      )}
      {work.body !== undefined && (
        <textarea
          className="resize-y rounded-[10px] border border-line bg-transparent p-2 font-sans text-ink outline-none focus:border-primary"
          value={body}
          rows={4}
          onChange={(event) => setBody(event.target.value)}
          // The island never takes the keyboard on its own, so it asks for it while the draft is being rewritten.
          onPointerDown={() => void invoke('island_keyboard', { on: true })}
          onBlur={() => void invoke('island_keyboard', { on: false })}
        />
      )}
      {work.fields.length > 0 && (
        <dl className="m-0 grid gap-0.5 text-xs">
          {work.fields.map((field) => (
            <div key={field.name} className="flex gap-2">
              <dt className="text-muted">{field.name}</dt>
              <dd className="m-0 [overflow-wrap:anywhere]">{field.value}</dd>
            </div>
          ))}
        </dl>
      )}
      <nav className="grid grid-cols-2 gap-2">
        <button className={button('quiet')} disabled={busy} onClick={() => void answer(false)}>
          <X size={14} /> Close
        </button>
        <button className={button('primary')} disabled={busy} onClick={() => void answer(true)}>
          <Send size={14} /> Send
        </button>
      </nav>
      {said !== undefined && <p className={note}>{said}</p>}
    </article>
  );
}
