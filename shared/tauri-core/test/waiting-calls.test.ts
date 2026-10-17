import { describe, expect, it } from 'vitest';
import { WaitingCalls } from '../src/core/domain/waiting-calls';

const three = WaitingCalls.empty<string>().add('a', 'one', 'build-box').add('b', 'two', 'this computer').add('c', 'three', 'build-box');

describe('the calls waiting on the person', () => {
  it('shows the newest and counts from it', () => {
    expect(three.shown?.subject).toBe('three');
    expect(three.positionText).toBe('1 of 3');
    expect(three.header).toBe('3 waiting: 2 on build-box, 1 on this computer');
  });

  it('keeps the card under the person hand once they stepped to it', () => {
    const stepped = three.step(1).add('d', 'four', 'build-box');
    expect(stepped.shown?.subject).toBe('two');
  });

  it('keeps a call told again in its place in the queue', () => {
    expect(three.add('again', 'one', 'build-box').entries.map((entry) => entry.subject)).toEqual(['one', 'two', 'three']);
  });

  it('brings the newest left up when the shown one goes', () => {
    expect(three.remove('three').shown?.subject).toBe('two');
    expect(three.remove('nothing')).toBe(three);
  });

  it('stops at either end', () => {
    expect(three.step(-1)).toBe(three);
    expect(three.step(5).shown?.subject).toBe('one');
    expect(three.step(5).canStepOlder).toBe(false);
  });

  it('names one machine once', () => {
    expect(WaitingCalls.empty<string>().add('a', 'one', 'x').add('b', 'two', 'x').header).toBe('2 waiting on x');
  });
});
