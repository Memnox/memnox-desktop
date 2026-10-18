import type { PhoneExchange } from '../../core/domain/phone-conversation';
import { CONTENT_INSET } from '../Cards';
import { AnswerCard, IslandConversation } from './Conversation';

/** A paired phone's turn on the island: what was said there in the bubble under its name, and the answer below. */
export function PhoneTurn({ turn }: { turn: PhoneExchange }) {
  return (
    <IslandConversation question={turn.exchange.question} from={turn.label} className={CONTENT_INSET}>
      <AnswerCard exchange={turn.exchange} />
    </IslandConversation>
  );
}
