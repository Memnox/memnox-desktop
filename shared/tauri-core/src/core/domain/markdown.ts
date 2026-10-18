/**
 * A card's markdown cut into the few shapes a card lays out, ported from the Mac's `MarkdownBlock`:
 * headings, bullets, fenced code and plain lines. Inline marks stay in the text, and `inlineMarks` cuts
 * one line into backticks, bold, italics and links for the view to draw, as SwiftUI's
 * `inlineOnlyPreservingWhitespace` does, so nothing the brain wrote is lost on the way to the screen.
 */

export type MarkdownBlock =
  | { readonly kind: 'heading'; readonly text: string }
  | { readonly kind: 'bullet'; readonly text: string }
  | { readonly kind: 'code'; readonly text: string }
  | { readonly kind: 'text'; readonly text: string };

/** Opens and closes a fenced code block. */
const FENCE = '```';
const HEADING = '#';
/** The marks a bulleted line starts with, each with the space after it. */
const BULLETS = ['- ', '* ', '+ '];

export function markdownBlocks(source: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  let fence: string[] | undefined;
  for (const raw of source.split(/\r\n|\r|\n/)) {
    const line = raw.trim();
    if (line.startsWith(FENCE)) {
      if (fence !== undefined) {
        blocks.push({ kind: 'code', text: fence.join('\n') });
        fence = undefined;
      } else fence = [];
      continue;
    }
    if (fence !== undefined) {
      fence.push(raw);
      continue;
    }
    if (line === '') continue;
    const heading = headingOf(line);
    const bullet = heading === undefined ? bulletOf(line) : undefined;
    if (heading !== undefined) blocks.push({ kind: 'heading', text: heading });
    else if (bullet !== undefined) blocks.push({ kind: 'bullet', text: bullet });
    else blocks.push({ kind: 'text', text: line });
  }
  // A fence the brain never closed is still code, rather than lines that vanish.
  if (fence !== undefined && fence.length > 0) blocks.push({ kind: 'code', text: fence.join('\n') });
  return blocks;
}

/** "## Pushed" as "Pushed", for any depth of heading. */
function headingOf(line: string): string | undefined {
  if (!line.startsWith(HEADING)) return undefined;
  let rest = line;
  while (rest.startsWith(HEADING)) rest = rest.slice(1);
  return rest.startsWith(' ') ? rest.trim() : undefined;
}

/** "- item", "* item" or "1. item" as "item". */
function bulletOf(line: string): string | undefined {
  for (const mark of BULLETS) if (line.startsWith(mark)) return line.slice(mark.length);
  const dot = line.indexOf('.');
  if (dot <= 0 || !/^\d+$/.test(line.slice(0, dot))) return undefined;
  const rest = line.slice(dot + 1);
  return rest.startsWith(' ') ? rest.trim() : undefined;
}

/** One run of a line with the marks it carries. */
export type InlineRun =
  | { readonly kind: 'plain'; readonly text: string }
  | { readonly kind: 'code'; readonly text: string }
  | { readonly kind: 'strong'; readonly text: string }
  | { readonly kind: 'emphasis'; readonly text: string }
  | { readonly kind: 'link'; readonly text: string; readonly href: string };

/** Backticks first, so nothing inside code is read as a mark; then links, bold and italics. */
const INLINE = /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*|__([^_]+)__|\*([^*\s][^*]*)\*|(?<![\w])_([^_\s][^_]*)_(?![\w])/g;

export function inlineMarks(line: string): InlineRun[] {
  const runs: InlineRun[] = [];
  let at = 0;
  for (const match of line.matchAll(INLINE)) {
    const start = match.index ?? 0;
    if (start > at) runs.push({ kind: 'plain', text: line.slice(at, start) });
    const [, code, label, href, bold, boldUnder, italic, italicUnder] = match;
    if (code !== undefined) runs.push({ kind: 'code', text: code });
    else if (label !== undefined && href !== undefined) runs.push({ kind: 'link', text: label, href });
    else if ((bold ?? boldUnder) !== undefined) runs.push({ kind: 'strong', text: bold ?? boldUnder ?? '' });
    else runs.push({ kind: 'emphasis', text: italic ?? italicUnder ?? '' });
    at = start + match[0].length;
  }
  if (at < line.length) runs.push({ kind: 'plain', text: line.slice(at) });
  return runs;
}

/** Only links a browser can open safely are drawn as links; anything else reads as its words. */
export function isOpenableLink(href: string): boolean {
  return /^https?:\/\//i.test(href);
}
