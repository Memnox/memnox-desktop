import { describe, expect, it } from 'vitest';
import { catalogueCards, connectedCards, connectedSummary, CONNECT_LINE, resultCountLine, STANDING_LINE, type YourConnection } from '../src/core/domain/your-apps';

const mine: YourConnection[] = [
  { toolkit: 'github', connected: true, local: true },
  { toolkit: 'notion', connected: true },
  { toolkit: 'slack', connected: false },
];

describe('your apps', () => {
  it('says a tool this computer reaches itself is already here, and offers no disconnect for it', () => {
    const [github] = connectedCards(mine, undefined);
    expect(github).toMatchObject({ name: 'GitHub', standing: 'local', line: STANDING_LINE.local, canDisconnect: false, canSignInAgain: false });
  });

  it('offers Sign in again only where a connection stopped working', () => {
    const cards = connectedCards(mine, undefined);
    expect(cards.map((card) => [card.toolkit, card.standing, card.canDisconnect, card.canSignInAgain])).toEqual([
      ['github', 'local', false, false],
      ['notion', 'connected', true, false],
      ['slack', 'signed-out', true, true],
    ]);
  });

  it('says to finish in the browser for the tool whose sign in is open', () => {
    expect(connectedCards(mine, 'slack')[2]?.line).toBe(STANDING_LINE.waiting);
  });

  it('marks catalogue tools the person already has instead of offering Connect twice', () => {
    const cards = catalogueCards(
      [
        { slug: 'notion', name: 'Notion' },
        { slug: 'figma', name: 'Figma', logo: 'https://logos.composio.dev/api/figma' },
        { slug: 'github', name: 'GitHub' },
      ],
      mine,
      undefined,
    );
    expect(cards.map((card) => [card.slug, card.standing, card.line])).toEqual([
      ['notion', 'connected', STANDING_LINE.connected],
      ['figma', 'new', CONNECT_LINE],
      ['github', 'local', STANDING_LINE.local],
    ]);
    expect(cards[1]?.logo).toBe('https://logos.composio.dev/api/figma');
  });

  it('shows a catalogue tool as waiting while its first sign in is open', () => {
    expect(catalogueCards([{ slug: 'figma', name: 'Figma' }], mine, 'figma')[0]?.standing).toBe('waiting');
  });

  it('counts what the search found, and says when the catalogue page is full', () => {
    expect(resultCountLine({ query: '', count: 30, searching: false, note: undefined })).toBe('30 apps you can connect');
    expect(resultCountLine({ query: ' fig ', count: 1, searching: false, note: undefined })).toBe('1 app matching "fig"');
    expect(resultCountLine({ query: 'g', count: 30, searching: false, note: undefined })).toBe('The first 30 apps matching "g", so type more to narrow it');
    expect(resultCountLine({ query: 'zz', count: 0, searching: false, note: undefined })).toBe('No app matches "zz"');
    expect(resultCountLine({ query: 'zz', count: 4, searching: true, note: undefined })).toBe('Looking');
    expect(resultCountLine({ query: 'zz', count: 0, searching: false, note: 'Memnox is not running' })).toBe('Memnox is not running');
  });

  it('sums the connected tools apart from the ones already here', () => {
    expect(connectedSummary(connectedCards(mine, undefined))).toBe('2 connected, 1 already on this computer');
    expect(connectedSummary([])).toBe('Nothing connected yet');
  });

  it('never asks for an account or sends the person to the console', () => {
    const words = [...Object.values(STANDING_LINE), CONNECT_LINE].join(' ').toLowerCase();
    expect(words).not.toMatch(/account with memnox|app\.memnox\.com|create an account|sign up/);
  });
});
