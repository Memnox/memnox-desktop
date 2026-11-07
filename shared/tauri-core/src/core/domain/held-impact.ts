// What a held action could affect, whether it can be undone and what was verified, as the machine worded each.
// Read as memnox-cloud/src/held-calls/held-impact.ts reads it, so every surface shows the same sentences.

export const CLAIM_BASIS = {
  RECORDED: 'recorded',
  EXTRACTED: 'extracted',
  INFERRED: 'inferred',
  UNKNOWN: 'unknown',
} as const;

export type ClaimBasis = (typeof CLAIM_BASIS)[keyof typeof CLAIM_BASIS];

export interface HeldClaim {
  readonly text: string;
  readonly basis: ClaimBasis;
  readonly source: string;
}

export interface HeldImpact {
  readonly affected: HeldClaim;
  readonly undo: HeldClaim;
  readonly verified: readonly HeldClaim[];
}

/** A line on a card rather than a document. */
const MOST_CLAIM_TEXT = 300;
const MOST_VERIFIED = 8;
const BASES: readonly string[] = Object.values(CLAIM_BASIS);

function claimOf(raw: unknown): HeldClaim | undefined {
  if (raw === null || typeof raw !== 'object') return undefined;
  const { text, basis, source } = raw as Record<string, unknown>;
  if (typeof text !== 'string' || text.trim() === '') return undefined;
  if (typeof basis !== 'string' || !BASES.includes(basis)) return undefined;
  return {
    text: text.trim().slice(0, MOST_CLAIM_TEXT),
    basis: basis as ClaimBasis,
    source: typeof source === 'string' ? source.slice(0, MOST_CLAIM_TEXT) : '',
  };
}

/** The impact the call carried, or undefined where an older runtime sent none or a part a person needs is missing. */
export function readHeldImpact(raw: unknown): HeldImpact | undefined {
  if (raw === null || typeof raw !== 'object') return undefined;
  const record = raw as Record<string, unknown>;
  const affected = claimOf(record['affected']);
  const undo = claimOf(record['undo']);
  const listed = record['verified'];
  if (affected === undefined || undo === undefined || !Array.isArray(listed)) return undefined;
  const verified = listed.slice(0, MOST_VERIFIED).flatMap((each) => {
    const claim = claimOf(each);
    return claim === undefined ? [] : [claim];
  });
  return { affected, undo, verified };
}

export const IMPACT_WORDS = {
  affected: 'What could be affected',
  undo: 'Can it be undone?',
  verified: 'What has been verified',
  more: 'More about this',
} as const;

/** The three lines on the face of the card; how each is known stays behind "More about this". */
export function impactRows(impact: HeldImpact): { label: string; text: string }[] {
  return [
    { label: IMPACT_WORDS.affected, text: impact.affected.text },
    { label: IMPACT_WORDS.undo, text: impact.undo.text },
    { label: IMPACT_WORDS.verified, text: impact.verified.map((claim) => claim.text).join(' ') },
  ];
}

const BASIS_WORDS: Record<ClaimBasis, string> = {
  recorded: 'recorded',
  extracted: 'extracted',
  inferred: 'inferred, not checked',
  unknown: 'not established',
};

/** How each claim is known, for "More about this". */
export function impactEvidence(impact: HeldImpact): { label: string; value: string }[] {
  return [impact.affected, impact.undo, ...impact.verified].map((claim) => ({
    label: BASIS_WORDS[claim.basis],
    value: claim.source === '' ? claim.text : `${claim.text} (${claim.source})`,
  }));
}
