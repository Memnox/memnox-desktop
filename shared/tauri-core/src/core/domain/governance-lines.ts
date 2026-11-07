/** The Approvals page's own words, beside those the island's held card says. */
export const GovernanceLines = {
  asksFirst: 'Asks first',
  asks: (who: string) => `${who} asks first`,
  allowOnce: 'Allow once',
  allowSession: 'Allow this session',
  deny: 'Deny',
  answered: 'Answered.',
  answeredElsewhere: 'Somebody answered this first, and that answer stands.',
  cancelled: 'Nothing was sent, so it still waits.',
} as const;
