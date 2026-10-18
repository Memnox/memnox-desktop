import './voice.css';

/** The gaps between words and between lines, and the caret's height, as shares of the text size. */
const WORD_GAP = 0.28;
const LINE_GAP = 0.3;
const CARET_HEIGHT = 1.1;
/** The newest word is a touch brighter, so the eye stays where the voice is. */
const OLDER_INK = 'rgb(255 255 255 / 0.78)';

/**
 * `LiveWords` in its `WordFlow`: what is being said, each word its own element laid out like a paragraph
 * on a shared bottom edge, arriving out of a blur and settling. A word the recognizer corrects is keyed
 * anew, so it arrives again and the sentence is seen firming up as it is heard.
 */
export function LiveWords({ text, size, align, listening }: { text: string; size: number; align: 'center' | 'leading'; listening: boolean }) {
  const words = text.split(/\s+/).filter((word) => word !== '');
  return (
    <div
      className="flex flex-wrap items-end"
      style={{ columnGap: size * WORD_GAP, rowGap: size * LINE_GAP, justifyContent: align === 'center' ? 'center' : 'flex-start', fontSize: size, lineHeight: 1.2 }}
    >
      {words.map((word, index) => (
        <span key={`${index}:${word}`} className="memnox-word font-medium" style={{ color: index === words.length - 1 ? '#fff' : OLDER_INK }}>
          {word}
        </span>
      ))}
      {listening && <ListeningCaret height={size * CARET_HEIGHT} />}
    </div>
  );
}

/** A thin blue bar after the last word that breathes once every 1.1 s while the microphone is open. */
export function ListeningCaret({ height }: { height: number }) {
  return <span className="inline-block w-0.5 shrink-0 animate-caret rounded-full bg-primary" style={{ height }} aria-hidden />;
}
