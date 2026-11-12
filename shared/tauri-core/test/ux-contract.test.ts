import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ALWAYS_ALLOW, ALWAYS_DENY, ANSWER_LABEL, ANSWER_ORDER, ANSWER_OUTCOME } from '../src/core/domain/answer-words';
import { DESTINATIONS, groupHeading } from '../src/core/domain/destinations';
import { SESSION_REASON_LABEL, SESSION_STATUS_ORDER, statusLabel } from '../src/core/domain/session-status';

/**
 * The window against `shared/ux/contract.json`, the verbatim copy of `memnox-runtime/docs/ux/contract.json` every
 * surface checks itself against, so Windows and Linux cannot drift from the console, the Mac and the phone unnoticed.
 */

const PLATFORM = 'desktop';

interface ContractTab {
  id: string;
  label: string;
  platforms?: string[];
}

interface ContractPage {
  id: string;
  label: string;
  group: string | null;
  sf: string;
  platforms: string[];
  tabs?: ContractTab[];
}

interface Contract {
  pages: ContractPage[];
  groups: Record<string, string>;
  answers: { order: string[]; labels: Record<string, string>; outcomes: Record<string, string>; always: string; never: string };
  sessionStatus: { order: string[]; labels: Record<string, string>; reasons: Record<string, string> };
}

function contract(): Contract {
  // The file is the desktop repository's own copy and checked here, so its shape is the interface above.
  return JSON.parse(readFileSync(join(__dirname, '..', '..', 'ux', 'contract.json'), 'utf8')) as Contract;
}

describe('the ux contract', () => {
  it('lists its pages in its order, with its words and icons', () => {
    const pages = contract().pages.filter((page) => page.platforms.includes(PLATFORM));
    expect(DESTINATIONS.map((each) => each.id)).toEqual(pages.map((page) => page.id));
    expect(DESTINATIONS.map((each) => each.title)).toEqual(pages.map((page) => page.label));
    expect(DESTINATIONS.map((each) => each.symbol)).toEqual(pages.map((page) => page.sf));
    expect(DESTINATIONS.map((each) => (each.group === 'top' ? null : each.group))).toEqual(pages.map((page) => page.group));
  });

  it('gives every page its tabs for this platform', () => {
    for (const page of contract().pages.filter((each) => each.platforms.includes(PLATFORM) && each.id !== 'settings')) {
      const tabs = (page.tabs ?? []).filter((tab) => tab.platforms?.includes(PLATFORM) ?? true);
      const mine = DESTINATIONS.find((each) => each.id === page.id)?.tabs ?? [];
      expect(mine.map((tab) => [tab.id, tab.title]), page.id).toEqual(tabs.map((tab) => [tab.id, tab.label]));
    }
  });

  it('heads the sections as the contract does', () => {
    const { groups } = contract();
    expect(groupHeading('govern')).toBe(groups.govern);
    expect(groupHeading('knowledge')).toBe(groups.knowledge);
  });

  it('answers a held call and names a session in its words', () => {
    const { answers, sessionStatus } = contract();
    expect([...ANSWER_ORDER]).toEqual(answers.order.filter((answer) => answer !== 'edit'));
    expect({ ...ANSWER_LABEL }).toEqual(answers.labels);
    expect({ ...ANSWER_OUTCOME }).toEqual(answers.outcomes);
    expect(ALWAYS_ALLOW).toBe(answers.always);
    expect(ALWAYS_DENY).toBe(answers.never);
    expect([...SESSION_STATUS_ORDER]).toEqual(sessionStatus.order);
    expect(Object.fromEntries(SESSION_STATUS_ORDER.map((status) => [status, statusLabel(status)]))).toEqual(sessionStatus.labels);
    expect({ ...SESSION_REASON_LABEL }).toEqual(sessionStatus.reasons);
  });
});
