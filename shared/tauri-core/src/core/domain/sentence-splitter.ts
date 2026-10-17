/** Shorter than this and a sentence rides with the one after it, since "Proposed." alone sounds clipped. */
const JOIN_BELOW = 16;
/** The first piece of a reply may end at a comma once it has this many words, so the voice starts sooner. */
const FIRST_CLAUSE_WORDS = 4;
const SENTENCE_ENDS = '.!?';
const CLAUSE_BREAKS = ',;:';

const isSpace = (character: string | undefined): boolean => character !== undefined && /\s/.test(character);
const words = (text: string): number => text.split(/\s+/).filter((word) => word !== '').length;

/**
 * Streamed text cut into whole sentences, the unit the voice speaks, so speech starts on the first
 * sentence rather than after the whole answer. A full stop inside "3.5" is no end, because a sentence
 * only ends where punctuation meets a space. Ported from the Mac's `SentenceSplitter`.
 */
export class SentenceSplitter {
  private pending = '';
  private carried = '';
  private spoke = false;

  push(text: string): string[] {
    this.pending += text;
    const sentences: string[] = [];
    let start = 0;
    for (let index = 0; index < this.pending.length; index += 1) {
      const mark = this.pending[index] ?? '';
      const spaced = isSpace(this.pending[index + 1]);
      const ends = spaced && SENTENCE_ENDS.includes(mark);
      const pauses = spaced && !this.spoke && CLAUSE_BREAKS.includes(mark);
      if (!ends && !pauses) continue;
      const sentence = this.pending.slice(start, index + 1).trim();
      const joined = this.carried === '' ? sentence : `${this.carried} ${sentence}`;
      if (pauses && !ends && words(joined) < FIRST_CLAUSE_WORDS) continue;
      if (sentence !== '') this.take(joined, sentences);
      start = index + 1;
    }
    this.pending = this.pending.slice(start);
    return sentences;
  }

  private take(joined: string, sentences: string[]): void {
    if (joined.length < JOIN_BELOW) {
      this.carried = joined;
      return;
    }
    sentences.push(joined);
    this.carried = '';
    this.spoke = true;
  }

  /** Whatever is left once the turn ends, said even without a full stop. */
  flush(): string | undefined {
    const rest = [this.carried, this.pending.trim()].filter((part) => part !== '').join(' ');
    this.pending = '';
    this.carried = '';
    this.spoke = false;
    return rest === '' ? undefined : rest;
  }
}
