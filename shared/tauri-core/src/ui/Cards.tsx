import { useState, useSyncExternalStore } from 'react';
import { invoke } from '@tauri-apps/api/core';
import type { RuleDraft, WorkDraft } from '@memnox/core/wire';
import { accountWarning, draftAudience, suggestedScope, type HeldOutcome, type ProposalCards } from '../core';

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
  const [note, setNote] = useState<string>();

  async function answer(scopeId: string | undefined) {
    setBusy(true);
    setNote(told(await cards.answerRule(subject, scopeId)));
    setBusy(false);
  }

  return (
    <article className="card">
      <p className="card-kind">A rule to put in force</p>
      <p className="what">{rule.summary}</p>
      <p className="why">{rule.reason}</p>
      <fieldset className="scopes">
        <legend>Where it holds</legend>
        {rule.scopes.map((each) => (
          <label key={each.id}>
            <input type="radio" name={`scope-${subject}`} checked={scope === each.id} onChange={() => setScope(each.id)} />
            {each.label}
          </label>
        ))}
      </fieldset>
      <nav className="answers answers--two">
        <button disabled={busy} onClick={() => void answer(undefined)}>
          Leave it out
        </button>
        <button className="primary" disabled={busy || scope === undefined} onClick={() => void answer(scope)}>
          Put in force
        </button>
      </nav>
      {note !== undefined && <p className="note">{note}</p>}
    </article>
  );
}

function WorkCard({ subject, work, cards }: { subject: string; work: WorkDraft; cards: ProposalCards }) {
  const drafted = work.body ?? '';
  const [body, setBody] = useState(drafted);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string>();
  const warning = accountWarning(work);

  async function answer(send: boolean) {
    setBusy(true);
    // Words go with the Send only when the person changed them, so the signature covers what really leaves.
    setNote(told(await cards.answerDraft(subject, send, send && body !== drafted ? body : undefined)));
    setBusy(false);
  }

  return (
    <article className="card">
      <p className="card-kind">
        {KIND_WORDS[work.kind]} to {draftAudience(work)}
      </p>
      {work.subject !== undefined && <p className="what">{work.subject}</p>}
      {warning !== undefined && <p className="note">{warning}</p>}
      {work.body !== undefined && (
        <textarea
          className="body"
          value={body}
          rows={4}
          onChange={(event) => setBody(event.target.value)}
          // The island never takes the keyboard on its own, so it asks for it while the draft is being rewritten.
          onPointerDown={() => void invoke('island_keyboard', { on: true })}
          onBlur={() => void invoke('island_keyboard', { on: false })}
        />
      )}
      {work.fields.length > 0 && (
        <dl className="fields">
          {work.fields.map((field) => (
            <div key={field.name}>
              <dt>{field.name}</dt>
              <dd>{field.value}</dd>
            </div>
          ))}
        </dl>
      )}
      <nav className="answers answers--two">
        <button disabled={busy} onClick={() => void answer(false)}>
          Close
        </button>
        <button className="primary" disabled={busy} onClick={() => void answer(true)}>
          Send
        </button>
      </nav>
      {note !== undefined && <p className="note">{note}</p>}
    </article>
  );
}
