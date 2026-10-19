import type { DaemonEvent, DaemonRequest, DaemonResponse, RuleDraft, WorkDraft } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { ProposalCards } from '../src/core/application/proposal-cards';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { accountWarning, afterRule, suggestedScope, typedAddresses } from '../src/core/domain/proposal-card';
import { held, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

const rule: RuleDraft = {
  summary: 'Deny git push to main',
  effect: 'deny',
  action: 'git.push',
  branches: ['main'],
  reason: 'You asked for it',
  scopes: [
    { id: 'scope_machine', kind: 'machine', label: 'This Mac' },
    { id: 'scope_repo', kind: 'repository', label: 'memnox-web', folder: '/code/memnox-web', suggested: true },
  ],
};

const work: WorkDraft = {
  toolkit: 'gmail',
  tool: 'GMAIL_SEND_EMAIL',
  kind: 'email',
  to: ['maya@example.test'],
  subject: 'The release',
  body: 'It ships on Friday.',
  fields: [],
  account: { handle: 'me@example.test', check: 'unverified' },
};

const proposal = (subject: string, extra: Partial<DaemonEvent>): DaemonEvent => ({ ...held(subject), kind: 'proposal', ...extra });

function cardsOver(confirm: (request: DaemonRequest) => DaemonResponse[], key = new PersonKey()) {
  const daemon = new ScriptedDaemon({ 'register-key': registered, confirm });
  const speaker = new RecordingSpeaker();
  const ids = new RequestIds();
  const cards = new ProposalCards(daemon, new Signer(daemon, key, ids), speaker, ids);
  return { daemon, speaker, cards, key };
}

const ok = (request: DaemonRequest): DaemonResponse[] => [{ id: request.id, ok: true }];

describe('a rule on its card', () => {
  it('opens on the place the daemon suggests', () => {
    expect(suggestedScope(rule)?.id).toBe('scope_repo');
  });

  it('goes in force only with a signature over the place picked', async () => {
    const { daemon, key, speaker, cards } = cardsOver(ok);
    cards.show(proposal('prp_rule', { rule }));
    expect(await cards.answerRule('prp_rule', 'scope_repo')).toEqual({ kind: 'answered' });
    expect(key.signed[0]).toEqual({
      message: 'memnox-confirm:v1:prp_rule:scope_repo',
      reason: 'put the rule "Deny git push to main" in force in memnox-web',
    });
    expect(daemon.sent('confirm')[0]).toMatchObject({ answer: 'scope_repo', signature: 'sig(memnox-confirm:v1:prp_rule:scope_repo)' });
    expect(speaker.said).toEqual(['Very well. That rule is in force in memnox-web.']);
    expect(cards.cards).toEqual([]);
  });

  it('is left out unsigned', async () => {
    const { daemon, key, cards } = cardsOver(ok);
    cards.show(proposal('prp_rule', { rule }));
    await cards.answerRule('prp_rule', undefined);
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')[0]).toMatchObject({ answer: 'declined' });
    expect(daemon.sent('confirm')[0]?.signature).toBeUndefined();
  });

  it('refuses a place the rule never offered, before any prompt', async () => {
    const { key, cards } = cardsOver(ok);
    cards.show(proposal('prp_rule', { rule }));
    expect((await cards.answerRule('prp_rule', 'scope_everywhere')).kind).toBe('failed');
    expect(key.signed).toEqual([]);
  });

  it('stays on its card when the prompt is cancelled', async () => {
    const { cards } = cardsOver(ok, new PersonKey('BPOINT', false));
    cards.show(proposal('prp_rule', { rule }));
    expect(await cards.answerRule('prp_rule', 'scope_machine')).toEqual({ kind: 'cancelled' });
    expect(cards.cards).toHaveLength(1);
  });

  it('says the team needs a second admin', () => {
    expect(afterRule({ id: 't', kind: 'team', label: 'Team' })).toContain('second admin');
  });
});

describe('a draft on its card', () => {
  it('sends with a signature over exactly the words the person rewrote', async () => {
    const { daemon, key, speaker, cards } = cardsOver(ok);
    cards.show(proposal('prp_mail', { work }));
    await cards.answerDraft('prp_mail', true, 'It ships on Monday.');
    expect(key.signed[0]).toEqual({
      message: 'memnox-confirm:v2:prp_mail:confirmed:It ships on Monday.',
      reason: 'send this email to maya@example.test',
    });
    expect(daemon.sent('confirm')[0]).toMatchObject({ answer: 'confirmed', edited: 'It ships on Monday.' });
    expect(speaker.said).toEqual(['Sent.']);
  });

  it('sends to the address typed on the card under a signature over it and the words', async () => {
    const { daemon, key, cards } = cardsOver(ok);
    cards.show(proposal('prp_mail', { work }));
    await cards.answerDraft('prp_mail', true, 'It ships on Monday.', 'moise@memnox.com');
    expect(key.signed[0]).toEqual({
      message: 'memnox-confirm:v3:prp_mail:confirmed:moise@memnox.com:It ships on Monday.',
      reason: 'send this email to moise@memnox.com',
    });
    expect(daemon.sent('confirm')[0]).toMatchObject({ edited: 'It ships on Monday.', editedTo: 'moise@memnox.com' });
  });

  it('reads only plain addresses from the To field', () => {
    expect(typedAddresses(' a@acme.test, b@acme.test ')).toEqual(['a@acme.test', 'b@acme.test']);
    expect(typedAddresses('moise memnox')).toBeUndefined();
    expect(typedAddresses('a:b@acme.test')).toBeUndefined();
    expect(typedAddresses('')).toBeUndefined();
  });

  it('sends the words as drafted with the first form of the signed message', async () => {
    const { key, cards } = cardsOver(ok);
    cards.show(proposal('prp_mail', { work }));
    await cards.answerDraft('prp_mail', true);
    expect(key.signed[0]?.message).toBe('memnox-confirm:v1:prp_mail:confirmed');
  });

  it('closes unsigned, carrying no words', async () => {
    const { daemon, key, cards } = cardsOver(ok);
    cards.show(proposal('prp_mail', { work }));
    await cards.answerDraft('prp_mail', false, 'ignored');
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')[0]).toMatchObject({ answer: 'declined' });
    expect(daemon.sent('confirm')[0]?.edited).toBeUndefined();
  });

  it('warns when the account it goes out as is not tied to the person', () => {
    expect(accountWarning(work)).toBe('Goes out as me@example.test, which is not tied to you, so check the name.');
    expect(accountWarning({ ...work, account: { check: 'matched' } })).toBeUndefined();
  });
});

describe('cards and the feed', () => {
  it('leave once settled elsewhere, and take no proposal that needs none', () => {
    const { cards } = cardsOver(ok);
    expect(cards.show(proposal('prp_plain', {}))).toBe(false);
    cards.show(proposal('prp_rule', { rule }));
    cards.remove('prp_rule');
    expect(cards.cards).toEqual([]);
  });
});
