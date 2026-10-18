import { useLayoutEffect, useRef, type ReactNode } from 'react';
import { SFSymbol } from '../kit';

/**
 * `QuestionBubble`: what the person asked, above the card that answers it: 15 medium white 92% on a
 * white 7% bubble of radius 18, 16 by 12, at most 76 tall and scrolled to its newest line. It arrives
 * from the top with a fade, and a phone's turn names the phone above it.
 */
export function QuestionBubble({ question, from }: { question: ReactNode; from?: string }) {
  const box = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const element = box.current;
    if (element !== null) element.scrollTop = element.scrollHeight;
  }, [question]);
  return (
    <div className="flex shrink-0 animate-pill-in flex-col gap-2">
      {from !== undefined && (
        <span className="flex items-center gap-1 text-caption font-medium text-white/[0.62]">
          <SFSymbol name="iphone" size={11} />
          <span className="truncate">{from}</span>
        </span>
      )}
      <div ref={box} className="max-h-[76px] overflow-y-auto rounded-[18px] bg-white/[0.07] px-4 py-3 text-headline font-medium text-white/[0.92] [scrollbar-width:none] select-text">
        {question}
      </div>
    </div>
  );
}

/**
 * `IslandConversation` around one card: the bubble above when there is a question, then exactly one
 * card below it, arriving from 0.97 scale anchored at its top. Fills the content inset of its mode.
 */
export function ConversationStack({ question, from, className, children }: { question?: string; from?: string; className?: string; children: ReactNode }) {
  const asked = question !== undefined && question.trim() !== '';
  return (
    <div className={`flex flex-col gap-2 ${className ?? ''}`}>
      {asked && <QuestionBubble question={question} from={from} />}
      <div className="flex min-h-0 flex-1 origin-top animate-card-in flex-col">{children}</div>
    </div>
  );
}
