import { ago } from './session-text';

/**
 * A change to the team's rules that waits on a second person, as memnox-cloud's `PolicyProposal` sends it. Only the
 * fields this app shows are read, since approving one is signed in Memnox Cloud and never here. Mirrors the Mac's
 * `CloudRuleChange`.
 */
export interface CloudRuleChange {
  readonly id: string;
  readonly proposedBy: string;
  readonly proposedAt: string;
  /** What it changes; absent on an older record, which is a rule set. */
  readonly kind?: string;
}

/** One team rule change as Needs you lists it. */
export interface TeamRuleChangeLine {
  readonly id: string;
  readonly title: string;
  readonly caption: string;
}

/** The cloud's list, leaving out any item that cannot be read rather than hiding every other. */
export function readCloudRuleChanges(body: unknown): CloudRuleChange[] {
  if (!Array.isArray(body)) return [];
  return body.flatMap((row: unknown) => {
    if (typeof row !== 'object' || row === null) return [];
    const { id, proposedBy, proposedAt, kind } = row as Record<string, unknown>;
    if (typeof id !== 'string' || typeof proposedBy !== 'string' || typeof proposedAt !== 'string') return [];
    return [{ id, proposedBy, proposedAt, ...(typeof kind === 'string' ? { kind } : {}) }];
  });
}

const TITLES: Readonly<Record<string, string>> = {
  data_patterns: 'A change to what counts as sensitive',
  mcp_servers: "A change to the team's tool servers",
  org_skills: "A change to the team's skills",
  shared_projects: "A change to the team's projects",
};

/** The words for team rule changes on Needs you, which point to Memnox Cloud because a second admin signs them there. */
export const TeamRuleChangeLines = {
  title: 'Team rule changes',
  detail: 'Each one is approved by a second person in Memnox Cloud, where your team signs it.',
  open: 'Open in Memnox Cloud',
  /** The console's Needs you, opened on its Rule changes list. */
  consoleAddress: 'https://app.memnox.com/inbox?queue=rule-changes',
  /** What a change is about, by the cloud's `ProposalKind`; an unknown kind is still a change to what the team allows. */
  titleOf(kind: string | undefined): string {
    return (kind === undefined ? undefined : TITLES[kind]) ?? "A change to the team's rules";
  },
} as const;

/** Every waiting change, newest first as the cloud sends it. */
export function teamRuleChangeLines(changes: readonly CloudRuleChange[], now: number): TeamRuleChangeLine[] {
  return changes.map((change) => {
    const asked = change.proposedBy === '' ? 'Asked by a teammate' : `Asked by ${change.proposedBy}`;
    const when = ago(change.proposedAt, now);
    return { id: change.id, title: TeamRuleChangeLines.titleOf(change.kind), caption: when === undefined ? asked : `${asked}, ${when}` };
  });
}
