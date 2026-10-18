import { useEffect, useSyncExternalStore } from 'react';
import type { AgentQuestions, HeldOutcome } from '../../core';
import { choiceForKey, nextQuestion, questionPosition, type QuestionItem, type QuestionOption } from '../../core/domain/agent-question';
import { ANSWERING_ROW, IslandButton, IslandCard, PRESSABLE, SFSymbol, VEIL } from '../kit';
import { SessionLogo } from './parts';

const CONTENT_INSET = 'absolute inset-x-2.5 bottom-2.5 top-9';

/**
 * `IslandQuestion`: an agent's own question, its logo and name with the topic, the question, and one
 * numbered button per choice, so a hand or a number key answers while the voice reads it. A question
 * that takes several ticks its choices and sends them with Done.
 */
export function Question({ questions, onAnswered }: { questions: AgentQuestions; onAnswered: (outcome: HeldOutcome) => void }) {
  const state = useSyncExternalStore(
    (changed) => questions.observe(changed),
    () => questions.state,
  );
  const card = state.card;
  const next = card === undefined ? undefined : nextQuestion(card);

  function choose(option: QuestionOption, item: QuestionItem) {
    if (item.multiSelect) questions.toggle(option.label);
    else void questions.pick(option.label).then(onAnswered);
  }

  // Keys 1 to 9 with no modifier answer the first nine choices, whenever the island has the keyboard.
  useEffect(() => {
    if (next === undefined) return;
    const pressed = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const option = choiceForKey(next.item, event.key);
      if (option === undefined) return;
      event.preventDefault();
      choose(option, next.item);
    };
    window.addEventListener('keydown', pressed);
    return () => window.removeEventListener('keydown', pressed);
  });

  if (card === undefined || next === undefined) return null;
  const item = next.item;
  const position = questionPosition(card);
  return (
    <IslandCard veil={VEIL.waiting} className={CONTENT_INSET}>
      <div className="flex h-full min-h-0 flex-col gap-3 p-4">
        <div className="flex min-w-0 items-center gap-2.5">
          <SessionLogo agent={card.agent} name={card.who} size={34} />
          <div className="flex min-w-0 flex-col gap-0.5">
            <span className="truncate text-body font-semibold text-white">{card.who}</span>
            {state.error !== undefined ? (
              <span className="flex min-w-0 items-center gap-1.5 text-caption text-red">
                <SFSymbol name="exclamationmark.triangle.fill" size={11} />
                <span className="truncate">{state.error}</span>
              </span>
            ) : (
              <span className="text-caption text-white/[0.62]">is asking you</span>
            )}
          </div>
          <span className="min-w-1.5 flex-1" />
          {item.header !== undefined && (
            <span className="max-w-[160px] shrink-0 truncate rounded-full bg-amber/16 px-2 py-1 text-caption font-semibold text-amber">{item.header}</span>
          )}
          {position !== undefined && <span className="tabular shrink-0 text-footnote text-white/[0.62]">{position}</span>}
        </div>
        <p className="m-0 line-clamp-3 text-callout font-semibold text-white" title={item.question}>
          {item.question}
        </p>
        <div className={`flex min-h-0 flex-1 flex-col gap-1.5 overflow-y-auto [scrollbar-width:none] ${state.answering ? ANSWERING_ROW : ''}`}>
          {item.options.map((option, index) => (
            <Choice key={option.label} option={option} index={index} multi={item.multiSelect} ticked={state.ticked.has(option.label)} onPress={() => choose(option, item)} />
          ))}
        </div>
        <div className="flex min-w-0 items-center gap-2">
          <IslandButton symbol="macwindow" onClick={() => questions.dismiss()}>
            Answer on screen
          </IslandButton>
          {item.multiSelect && (
            <IslandButton kind="primary" disabled={state.ticked.size === 0 || state.answering} onClick={() => void questions.done().then(onAnswered)}>
              Done
            </IslandButton>
          )}
          <span className="min-w-1.5 flex-1" />
          <span className="truncate text-caption text-white/50">{item.multiSelect ? 'Tick what applies, then Done' : 'Pick one, or say your answer'}</span>
        </div>
      </div>
    </IslandCard>
  );
}

/** One choice: its number or its tick, the label and what it means, white 6% or 16% with an amber rim when ticked. */
function Choice({ option, index, multi, ticked, onPress }: { option: QuestionOption; index: number; multi: boolean; ticked: boolean; onPress: () => void }) {
  const key = index < 9 ? String(index + 1) : undefined;
  return (
    <button
      type="button"
      className={`${PRESSABLE} flex w-full shrink-0 items-start gap-2.5 rounded-card border px-3 py-2.5 text-left ${ticked ? 'border-amber bg-white/16' : 'border-white/[0.08] bg-white/[0.06]'}`}
      onClick={onPress}
      title={key === undefined ? option.label : `Press ${key}`}
      aria-pressed={multi ? ticked : undefined}
    >
      <span className="grid size-[22px] shrink-0 place-items-center">
        {multi ? (
          <span className={ticked ? 'text-amber' : 'text-white/[0.62]'}>
            <SFSymbol name={ticked ? 'checkmark.circle.fill' : 'circle'} size={15} />
          </span>
        ) : (
          <span className="tabular grid size-[22px] place-items-center rounded-control bg-white/10 text-caption font-semibold text-white/[0.92]">{index + 1}</span>
        )}
      </span>
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-body font-medium text-white">{option.label}</span>
        {option.description !== undefined && (
          <span className="line-clamp-2 text-footnote text-white/[0.62]" title={option.description}>
            {option.description}
          </span>
        )}
      </span>
    </button>
  );
}
