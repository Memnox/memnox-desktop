import {
  isAddress,
  RULE_SCOPE,
  WORK_ACCOUNT_CHECK,
  type DaemonEvent,
  type RuleDraft,
  type RuleScope,
  type WorkDraft,
} from '@memnox/core/wire';
import { trimmed } from './call-label';

/** A proposal that waits on a card, because the person has to read it before the key is asked. */
export type ProposalCard =
  | { readonly kind: 'rule'; readonly subject: string; readonly rule: RuleDraft }
  | { readonly kind: 'work'; readonly subject: string; readonly work: WorkDraft };

/** The card a proposal needs, undefined for one answered without a card. */
export function proposalCard(event: DaemonEvent): ProposalCard | undefined {
  if (event.rule !== undefined) return { kind: 'rule', subject: event.subject, rule: event.rule };
  if (event.work !== undefined) return { kind: 'work', subject: event.subject, work: event.work };
  return undefined;
}

/** The scope picked when the card opens: the one the daemon suggests, or the narrowest it offers. */
export function suggestedScope(rule: RuleDraft): RuleScope | undefined {
  return rule.scopes.find((scope) => scope.suggested === true) ?? rule.scopes[0];
}

/** What the consent prompt says, so the person signs knowing where the rule will hold. */
export function ruleReason(rule: RuleDraft, scope: RuleScope): string {
  if (scope.kind === RULE_SCOPE.TEAM) return `offer the rule "${rule.summary}" to your team`;
  if (scope.kind === RULE_SCOPE.REPOSITORY) return `put the rule "${rule.summary}" in force in ${scope.label}`;
  return `put the rule "${rule.summary}" in force on this computer`;
}

/** Where it holds now, said once it is written, so the person hears the reach they signed for. */
export function afterRule(scope: RuleScope | undefined): string {
  if (scope === undefined) return 'Very well. I have left that rule out.';
  if (scope.kind === RULE_SCOPE.MACHINE) return 'Very well. That rule is in force on this computer.';
  if (scope.kind === RULE_SCOPE.REPOSITORY) return `Very well. That rule is in force in ${scope.label}.`;
  if (scope.kind === RULE_SCOPE.TEAM) return 'Very well. I have offered that rule to the team. It holds everywhere once a second admin approves it.';
  return 'Very well. That rule is in force.';
}

/** Who a draft goes to, in a few words for the prompt and the card. */
export function draftAudience(work: WorkDraft): string {
  const to = work.to !== undefined && work.to.length > 0 ? work.to.join(', ') : undefined;
  return trimmed(to) ?? trimmed(work.where) ?? work.toolkit;
}

/** What the consent prompt says for a Send, naming the addresses the person typed on the card where they did. */
export function draftReason(work: WorkDraft, typed?: readonly string[]): string {
  const audience = typed === undefined ? draftAudience(work) : typed.join(', ');
  return `send this ${work.kind === 'other' ? 'from ' + work.toolkit : work.kind} to ${audience}`;
}

/** Every address typed in a mail's To field, split on commas and spaces, or undefined while any is not a plain one. */
export function typedAddresses(typed: string): string[] | undefined {
  const parts = typed.split(/[\s,]+/).filter((each) => each !== '');
  return parts.length > 0 && parts.every(isAddress) ? parts : undefined;
}

/** A warning when the account it goes out as is not tied to the person, shown and never blocking, as on the Mac. */
export function accountWarning(work: WorkDraft): string | undefined {
  const account = work.account;
  if (account === undefined || account.check === WORK_ACCOUNT_CHECK.MATCHED) return undefined;
  const who = trimmed(account.name) ?? trimmed(account.handle) ?? 'this account';
  if (account.check === WORK_ACCOUNT_CHECK.MISMATCH) return `Goes out as ${who}, which is not the account you signed in with.`;
  return `Goes out as ${who}, which is not tied to you, so check the name.`;
}

/** Said once a draft went out, so a send is never left to be guessed at. */
export const SENT_LINE = 'Sent.';
