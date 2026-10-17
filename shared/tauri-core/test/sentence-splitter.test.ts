import { describe, expect, it } from 'vitest';
import { SentenceSplitter } from '../src/core/domain/sentence-splitter';

describe('cutting a streamed reply into sentences', () => {
  it('cuts where an end meets a space, and never inside a number', () => {
    const splitter = new SentenceSplitter();
    expect(splitter.push('Version 3.5 is out on every machine. Next')).toEqual(['Version 3.5 is out on every machine.']);
    expect(splitter.push(' one comes soon')).toEqual([]);
    expect(splitter.flush()).toBe('Next one comes soon');
  });

  it('lets the first piece end at a comma once it has a few words, so the voice starts sooner', () => {
    expect(new SentenceSplitter().push('Right, two sessions are open, both in memnox-web. ')).toEqual([
      'Right, two sessions are open,',
      'both in memnox-web.',
    ]);
  });

  it('carries a short sentence into the next', () => {
    expect(new SentenceSplitter().push('Proposed. I will push it to main once you allow it. ')).toEqual([
      'Proposed. I will push it to main once you allow it.',
    ]);
  });
});
