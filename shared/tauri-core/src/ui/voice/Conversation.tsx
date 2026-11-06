import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { answerClock, isAnswering, type Exchange } from '../../core';
import { MarkdownText } from '../cards/MarkdownText';
import { QuestionBubble } from '../cards/QuestionBubble';
import { IslandButton, IslandCard, Pressable, SFSymbol, ShimmerText, VEIL } from '../kit';
import './voice.css';
import { ConversationLines } from '../../core/domain/island-lines';

/** What was read back after an action this answer took, the evidence beside what it says. */
export interface Proof {
  readonly text: string;
  /** A screenshot taken after it landed, as a URL the webview can show. */
  readonly image?: string;
}

/** Long enough to read "Copied", short enough that the button is itself again by the next look. */
const COPIED_FOR_MS = 1_500;

/**
 * `IslandConversation`: a turn on screen, the question in a bubble and under it exactly one card,
 * arriving from 0.97 anchored at its top. A phone's turn names the phone above it.
 */
export function IslandConversation({ question, from, className, children }: { question?: string; from?: string; className?: string; children: ReactNode }) {
  return (
    <div className={`flex flex-col gap-2 ${className ?? ''}`}>
      {question !== undefined && question.trim() !== '' && <QuestionBubble question={question} from={from} />}
      <div className="flex min-h-0 flex-1 origin-top animate-card-in flex-col">{children}</div>
    </div>
  );
}

/**
 * `AnswerCard`: who answered and how long it took, the reply laid out as written, the evidence for
 * what it did, and ways to open it up. A faint blue rim while it is still arriving.
 */
export function AnswerCard({
  exchange,
  proofs = [],
  onOpen,
}: {
  exchange: Exchange;
  proofs?: readonly Proof[];
  /** Opens the answer in its own window. */
  onOpen?: () => void;
}) {
  const answering = isAnswering(exchange);
  const empty = exchange.answer.trim() === '';
  const [copied, setCopied] = useState(false);
  const now = useSecondTick(answering);
  const scroll = useRef<HTMLDivElement>(null);
  // Anchored at the bottom while it arrives and at the top once done, as `defaultScrollAnchor` is.
  useLayoutEffect(() => {
    const element = scroll.current;
    if (element !== null) element.scrollTop = answering ? element.scrollHeight : 0;
  }, [exchange.answer, answering]);
  useEffect(() => {
    if (!copied) return;
    const back = setTimeout(() => setCopied(false), COPIED_FOR_MS);
    return () => clearTimeout(back);
  }, [copied]);

  function copy() {
    void navigator.clipboard?.writeText(exchange.answer).then(() => setCopied(true), () => undefined);
  }

  return (
    <IslandCard veil={answering ? VEIL.answering : undefined} className="flex min-h-0 flex-1 flex-col gap-2.5 p-3.5">
      <div className="flex items-center gap-2">
        <span className="size-3.5 shrink-0 rounded-full bg-primary" aria-hidden />
        <span className="text-body font-semibold text-white/[0.92]">{ConversationLines.memnox}</span>
        <span className="min-w-2 flex-1" />
        {answering ? (
          <ShimmerText>{ConversationLines.working}</ShimmerText>
        ) : (
          <span className="flex items-center gap-1 text-footnote font-semibold text-green">
            <SFSymbol name="checkmark.circle.fill" size={12} weight="semibold" />
            {ConversationLines.done}
          </span>
        )}
        <span className="tabular text-footnote font-medium text-white/50">{answerClock((exchange.answeredAt ?? now) - exchange.askedAt)}</span>
      </div>
      {empty ? (
        <div className="min-h-0 flex-1">
          <ShimmerText>{ConversationLines.thinking}</ShimmerText>
        </div>
      ) : (
        <div ref={scroll} className="memnox-answer-fade min-h-0 flex-1 overflow-y-auto [scrollbar-width:none]">
          <MarkdownText source={exchange.answer} />
        </div>
      )}
      {proofs.map((proof, index) => (
        <ProofRow key={index} proof={proof} />
      ))}
      <div className="flex items-center gap-2 text-button font-medium">
        <span className="flex-1" />
        <IslandButton symbol={copied ? 'checkmark' : 'doc.on.doc'} disabled={empty} onClick={copy}>
          {copied ? ConversationLines.copied : ConversationLines.copy}
        </IslandButton>
        <IslandButton kind="primary" symbol="arrow.up.forward.square" disabled={empty || onOpen === undefined} onClick={onOpen}>
          {ConversationLines.openAnswer}
        </IslandButton>
      </div>
    </IslandCard>
  );
}

/** `ProofRow`: what was read back after an action landed, beside the screenshot it left, opened on a click. */
export function ProofRow({ proof, onOpenImage }: { proof: Proof; onOpenImage?: (image: string) => void }) {
  return (
    <div className="flex items-start gap-2">
      {proof.image !== undefined ? (
        <Pressable
          className="shrink-0 cursor-pointer rounded-md bg-transparent p-0"
          title={ConversationLines.screenshot}
          onClick={() => proof.image !== undefined && onOpenImage?.(proof.image)}
        >
          <img src={proof.image} alt="" className="h-11 w-auto rounded-md object-contain" />
        </Pressable>
      ) : (
        <span className="shrink-0 text-green">
          <SFSymbol name="eye.circle.fill" size={13} />
        </span>
      )}
      <p className="m-0 line-clamp-3 min-w-0 flex-1 text-footnote font-medium text-white/[0.62]">{proof.text}</p>
    </div>
  );
}

/** The clock a running step reads, once a second as its seconds count. */
const SECOND_MS = 1_000;

/** The time now, renewed every second while `ticking`, so the stopwatch moves as the answer arrives. */
function useSecondTick(ticking: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!ticking) return;
    const tick = setInterval(() => setNow(Date.now()), SECOND_MS);
    return () => clearInterval(tick);
  }, [ticking]);
  return now;
}
