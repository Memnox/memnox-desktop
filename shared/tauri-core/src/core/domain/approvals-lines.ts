/** The Approvals page's words, the same as the Mac's `ApprovalsDestination` and `HeldSigning` say them. */

export const NOTHING_WAITING = 'Nothing is waiting on you';
export const NOTHING_WAITING_DETAIL = 'When an agent asks before doing something your rules hold, it waits here and on the island.';

/** "3 waiting, oldest first." */
export function waitingLine(count: number): string {
  return `${count} waiting, oldest first.`;
}

/** How a yes to this call is signed, and whether the signature covers exactly the call shown. */
export function signedLine(signs: boolean, actionDigest: string | undefined, keyTitle: string): string {
  if (!signs) return 'Inside its own repository, so a yes needs no signature';
  if (actionDigest === undefined) return `A yes is signed with ${keyTitle}`;
  return `A yes is signed with ${keyTitle} over exactly this call, so one changed since is refused`;
}

/** The facts under a held call, in the Mac's order: where it waits, why it asks, then how a yes is signed. */
export function heldFacts(card: { readonly why: string | undefined; readonly touchID: boolean; readonly actionDigest: string | undefined }, project: string | undefined, keyTitle: string): [string, string][] {
  const facts: [string, string][] = [];
  if (project !== undefined) facts.push(['Project', project]);
  if (card.why !== undefined) facts.push(['Why it asks', card.why]);
  facts.push(['Signed', signedLine(card.touchID, card.actionDigest, keyTitle)]);
  return facts;
}
