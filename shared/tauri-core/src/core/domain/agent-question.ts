import type { DaemonEvent } from '@memnox/core/wire';

/** The notice word for an agent's own question, as the runtime's `NOTICE_KIND` names it. */
const QUESTION = 'question';

export interface QuestionOption {
  readonly label: string;
  readonly description?: string;
}

export interface QuestionItem {
  readonly question: string;
  readonly header?: string;
  readonly options: readonly QuestionOption[];
  readonly multiSelect: boolean;
}

/**
 * An agent's question as the island asks it, ported from the Mac's `AgentQuestionCard`: which of its
 * questions is next, and what a pick sends. What is picked is kept by question text, from the daemon
 * and from taps here, so nothing is asked twice.
 */
export interface QuestionCard {
  readonly subject: string;
  readonly agent: string;
  readonly who: string;
  readonly questions: readonly QuestionItem[];
  readonly answers: Readonly<Record<string, string>>;
}

/** How the runtime's picker joins several picks into one answer. */
export const PICK_SEPARATOR = ', ';

/** The card for an agent's question with something to pick, undefined for any other event. */
export function questionCard(event: DaemonEvent): QuestionCard | undefined {
  if (event.notice !== QUESTION || event.questions === undefined || event.questions.length === 0) return undefined;
  return {
    subject: event.subject,
    agent: event.agent,
    who: event.agentName ?? event.agent,
    // Lenient past the question itself, so a daemon that leaves a field out still shows the choices it sent.
    questions: event.questions.map((item) => ({ question: item.question, header: item.header, options: item.options ?? [], multiSelect: item.multiSelect ?? false })),
    answers: { ...(event.answers ?? {}) },
  };
}

/** The first question nothing has answered yet, numbered from one as the daemon counts them. */
export function nextQuestion(card: QuestionCard): { number: number; item: QuestionItem } | undefined {
  const index = card.questions.findIndex((item) => card.answers[item.question] === undefined);
  const item = card.questions[index];
  return item === undefined ? undefined : { number: index + 1, item };
}

/** How far along, such as "2 of 3", only when there is more than one question. */
export function questionPosition(card: QuestionCard): string | undefined {
  const next = nextQuestion(card);
  if (card.questions.length <= 1 || next === undefined) return undefined;
  return `${next.number} of ${card.questions.length}`;
}

/** The one answer several picks make, in the order the agent listed them. */
export function joinedPicks(picked: ReadonlySet<string>, item: QuestionItem): string {
  return item.options
    .map((option) => option.label)
    .filter((label) => picked.has(label))
    .join(PICK_SEPARATOR);
}

/** The same card with one more answer taken, which moves it on to the next question. */
export function answering(card: QuestionCard, number: number, answer: string): QuestionCard {
  const item = card.questions[number - 1];
  if (item === undefined) return card;
  return { ...card, answers: { ...card.answers, [item.question]: answer } };
}

/** The choice a number key picks, one to nine, or undefined when the key names none. */
export function choiceForKey(item: QuestionItem, key: string): QuestionOption | undefined {
  if (!/^[1-9]$/.test(key)) return undefined;
  return item.options[Number(key) - 1];
}
