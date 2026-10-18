import { useRef } from 'react';
import type { Exchange, TalkState } from '../../core';

/** The id of the turn under way, which is never kept, so it can never be mistaken for one in the history. */
const LIVE_ID = 'live';

/**
 * The voice's turn as an `Exchange`, so the conversation screen draws the question and its streamed answer
 * with the same card the history uses. It is stamped when the question was heard and when the reply stopped
 * arriving, and undefined while nothing has been asked.
 */
export function useLiveExchange(talk: TalkState): Exchange | undefined {
  const asked = useRef<{ heard: string; at: number; answeredAt?: number }>();
  const heard = talk.heard?.trim() ?? '';
  if (heard === '') return undefined;
  if (asked.current?.heard !== heard) asked.current = { heard, at: Date.now() };
  const arriving = talk.phase === 'thinking' || talk.phase === 'speaking';
  if (arriving) asked.current.answeredAt = undefined;
  else if (asked.current.answeredAt === undefined) asked.current.answeredAt = Date.now();
  return {
    id: LIVE_ID,
    question: heard,
    answer: talk.reply,
    askedAt: asked.current.at,
    ...(asked.current.answeredAt === undefined ? {} : { answeredAt: asked.current.answeredAt }),
    ...(talk.failure === undefined ? {} : { failure: talk.failure }),
  };
}
