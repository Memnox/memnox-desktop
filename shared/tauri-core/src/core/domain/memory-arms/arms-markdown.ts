/**
 * Enough markdown to read a skill's instructions as they were written:
 * headings, lists, quotes, fenced code and paragraphs, with inline code,
 * bold, italics and links. It builds data rather than HTML, so nothing in a
 * skill's text can reach the page as markup.
 */

export type Inline =
  | { kind: "text"; text: string }
  | { kind: "code"; text: string }
  | { kind: "strong"; text: string }
  | { kind: "em"; text: string }
  | { kind: "link"; text: string; href: string };

export type Block =
  | { kind: "heading"; level: number; inline: Inline[] }
  | { kind: "list"; ordered: boolean; items: Inline[][] }
  | { kind: "quote"; inline: Inline[] }
  | { kind: "code"; text: string }
  | { kind: "paragraph"; inline: Inline[] };

const FENCE = /^\s*(```|~~~)/;
const HEADING = /^(#{1,6})\s+(.*)$/;
const BULLET = /^\s*[-*+]\s+(.*)$/;
const NUMBERED = /^\s*\d+[.)]\s+(.*)$/;
const QUOTE = /^\s*>\s?(.*)$/;
const FRONT_MATTER = /^---\s*$/;
const INLINE = /(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\*[^*\s][^*]*\*|_[^_\s][^_]*_|\[[^\]]+\]\([^)\s]+\))/g;
/** Only these schemes become a link; anything else stays words. */
const SAFE_HREF = /^(https?:|mailto:|\/)/i;

export function inlineOf(text: string): Inline[] {
  const out: Inline[] = [];
  let last = 0;
  for (const match of text.matchAll(INLINE)) {
    const token = match[0];
    const at = match.index ?? 0;
    if (at > last) out.push({ kind: "text", text: text.slice(last, at) });
    out.push(tokenOf(token));
    last = at + token.length;
  }
  if (last < text.length) out.push({ kind: "text", text: text.slice(last) });
  return out;
}

function tokenOf(token: string): Inline {
  if (token.startsWith("`")) return { kind: "code", text: token.slice(1, -1) };
  if (token.startsWith("**") || token.startsWith("__")) return { kind: "strong", text: token.slice(2, -2) };
  if (token.startsWith("[")) {
    const close = token.indexOf("](");
    const text = token.slice(1, close);
    const href = token.slice(close + 2, -1);
    return SAFE_HREF.test(href) ? { kind: "link", text, href } : { kind: "text", text };
  }
  return { kind: "em", text: token.slice(1, -1) };
}

/** Front matter is the skill's own settings, which the card already shows as fields. */
function withoutFrontMatter(lines: string[]): string[] {
  if (!FRONT_MATTER.test(lines[0] ?? "")) return lines;
  const end = lines.slice(1).findIndex((line) => FRONT_MATTER.test(line));
  return end === -1 ? lines : lines.slice(end + 2);
}

export function markdownBlocks(source: string): Block[] {
  const lines = withoutFrontMatter(source.replace(/\r\n?/g, "\n").split("\n"));
  const blocks: Block[] = [];
  let paragraph: string[] = [];
  const flush = () => {
    if (paragraph.length > 0) blocks.push({ kind: "paragraph", inline: inlineOf(paragraph.join(" ")) });
    paragraph = [];
  };
  for (let at = 0; at < lines.length; at += 1) {
    const line = lines[at]!;
    if (FENCE.test(line)) {
      flush();
      const code: string[] = [];
      for (at += 1; at < lines.length && !FENCE.test(lines[at]!); at += 1) code.push(lines[at]!);
      blocks.push({ kind: "code", text: code.join("\n") });
      continue;
    }
    const heading = HEADING.exec(line);
    const bullet = BULLET.exec(line);
    const numbered = NUMBERED.exec(line);
    const quote = QUOTE.exec(line);
    if (heading !== null) {
      flush();
      blocks.push({ kind: "heading", level: heading[1]!.length, inline: inlineOf(heading[2]!.trim()) });
    } else if (bullet !== null || numbered !== null) {
      flush();
      const ordered = numbered !== null && bullet === null;
      const item = inlineOf((bullet ?? numbered)![1]!.trim());
      const previous = blocks[blocks.length - 1];
      if (previous?.kind === "list" && previous.ordered === ordered) previous.items.push(item);
      else blocks.push({ kind: "list", ordered, items: [item] });
    } else if (quote !== null) {
      flush();
      blocks.push({ kind: "quote", inline: inlineOf(quote[1]!.trim()) });
    } else if (line.trim() === "") {
      flush();
    } else {
      paragraph.push(line.trim());
    }
  }
  flush();
  return blocks;
}
