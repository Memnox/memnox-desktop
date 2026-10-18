/**
 * The Mac's `TabMatch`: which of a terminal's tabs holds a session, told by what the tabs show when the
 * terminal cannot say. The one text showing the most of the session's lines wins, and none when two show
 * as many, since then which is the session's cannot be told.
 */

/** A tab must show at least this many of the session's lines to count at all. */
const FEWEST_SHOWN = 1;

/** Lowercase with every space and line break gone, since a terminal wraps a line wherever its width ends. */
export function squeezed(text: string): string {
  return text.toLowerCase().replace(/\s+/g, '');
}

function wanted(marks: readonly string[]): string[] {
  return marks.map(squeezed).filter((mark) => mark !== '');
}

/** The index of the text that holds the session, or undefined when none does or two do equally. */
export function bestTab(texts: readonly string[], marks: readonly string[]): number | undefined {
  const lines = wanted(marks);
  if (lines.length === 0) return undefined;
  const scores = texts.map((text) => {
    const screen = squeezed(text);
    return lines.filter((line) => screen.includes(line)).length;
  });
  const top = Math.max(0, ...scores);
  if (top < FEWEST_SHOWN || scores.filter((score) => score === top).length !== 1) return undefined;
  return scores.indexOf(top);
}

/** Whether this one text shows every one of the session's lines, which settles it without reading the rest. */
export function isCertainTab(text: string, marks: readonly string[]): boolean {
  const lines = wanted(marks);
  const screen = squeezed(text);
  return lines.length > 0 && lines.every((line) => screen.includes(line));
}
