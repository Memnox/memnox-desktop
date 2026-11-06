import { MiddleCut } from './MiddleCut';

/**
 * Text on one line cut to the room it has, the whole of it one hover away. `middle` cuts it in the middle, as the
 * Mac cuts a path or a command so both its ends stay; otherwise it is cut at its end.
 */
export function TruncatedText({ text, middle = false, className }: { text: string; middle?: boolean; className?: string }) {
  if (middle) return <MiddleCut text={text} className={className} />;
  return (
    <span className={`truncate ${className ?? ''}`} title={text}>
      {text}
    </span>
  );
}
