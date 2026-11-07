import type { ProfileView } from '@memnox/core/wire';
import { NO_LEVELS, type AgentConnection, type AgentWork, type CapabilityLevel, type CapabilityLevels, type Tracker, type WorkHandoff, type WorkStatus } from './agent-wire';

// Agent profiles and agent work as Memnox Cloud sends them, field for field from memnox-cloud's src/agent-profiles and
// src/agent-work, for agents hosted elsewhere that no daemon here reaches. Mirrors the Mac's `WorkspaceAgentsWire`.

/** A job as the workspace keeps it. */
export interface CloudProfile {
  readonly id: string;
  readonly name: string;
  readonly purpose?: string;
  readonly role?: string;
  readonly responsibilities?: readonly string[];
  readonly responsiblePersonId?: string;
  /** The responsible person's name, sent by a newer cloud; older ones send only the id. */
  readonly responsiblePersonName?: string;
  readonly projects?: readonly string[];
  readonly templateOf?: string;
}

/** One way the workspace reaches a profile's agent, and how sure it is through it. */
export interface CloudProfileConnection {
  readonly machineId: string;
  readonly connection?: string;
  readonly label?: string;
  readonly live: boolean;
  /** By capability, with enforcement as one level rather than by seam. */
  readonly levels?: Readonly<Record<string, string>>;
}

/** A profile as the person reads it, with what the workspace derived about it. */
export interface CloudProfileView {
  readonly profile: CloudProfile;
  /** The responsible person left or was never one, so an admin must reassign it. */
  readonly needsResponsiblePerson?: boolean;
  /** Where a newer cloud puts the responsible person's name beside the profile rather than in it. */
  readonly responsiblePersonName?: string;
  readonly connected?: boolean;
  readonly connections?: readonly CloudProfileConnection[];
  readonly levels?: Readonly<Record<string, string>>;
}

export interface CloudWork {
  readonly id: string;
  readonly agentProfileId: string;
  readonly responsiblePersonId: string;
  readonly target: { readonly source: string; readonly externalId: string; readonly url?: string; readonly title?: string };
  readonly status: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface CloudHandoff {
  readonly id: string;
  readonly workId: string;
  readonly fromProfileId: string;
  readonly toProfileId?: string;
  readonly toPersonId?: string;
  readonly reason: string;
  readonly state: string;
  readonly requestedAt: string;
}

/** What `GET :ws/me/agent-work` answers: the work the person answers for and the handoffs waiting on them. */
export interface CloudMyWork {
  readonly work: readonly CloudWork[];
  readonly handoffs: readonly CloudHandoff[];
}

/** The cloud states enforcement as one level, so it stands as a single seam of its own. */
export const EVERY_SEAM = 'everything';

const LEVELS: readonly string[] = ['enforced', 'mediated', 'advisory', 'observed', 'none'];

function level(cloud: Readonly<Record<string, string>>, key: string): CapabilityLevel {
  const said = cloud[key];
  return said !== undefined && LEVELS.includes(said) ? (said as CapabilityLevel) : 'none';
}

/** The cloud's levels as the strip reads them; anything it did not say is outside Memnox, never more. */
export function cloudLevels(cloud: Readonly<Record<string, string>> | undefined): CapabilityLevels {
  if (cloud === undefined) return NO_LEVELS;
  return {
    context: level(cloud, 'context'),
    instructions: level(cloud, 'instructions'),
    tools: level(cloud, 'tools'),
    activity: level(cloud, 'activity'),
    coordination: level(cloud, 'coordination'),
    approval: level(cloud, 'approval'),
    // Cast is safe: the strip reads the seams by key and names this one Everything it runs, so no seam is claimed.
    enforcement: { [EVERY_SEAM]: level(cloud, 'enforcement') } as unknown as CapabilityLevels['enforcement'],
  };
}

/** Who answers for a workspace job: their name when the cloud sends it, else you or a teammate, else nobody yet. */
export function responsibleOf(view: CloudProfileView, you: string | undefined): string | undefined {
  if (view.needsResponsiblePerson === true) return undefined;
  const named = (view.profile.responsiblePersonName ?? view.responsiblePersonName)?.trim();
  if (named !== undefined && named !== '') return named;
  const id = view.profile.responsiblePersonId;
  if (id === undefined) return undefined;
  return id === you ? 'you' : 'a teammate';
}

/** The profile as a card draws it, so a hosted agent wears the same card, pills and words as one on this computer. */
export function cloudProfileView(view: CloudProfileView, you: string | undefined): ProfileView {
  const profile = view.profile;
  const responsible = responsibleOf(view, you);
  const connections: AgentConnection[] = (view.connections ?? []).map((each) => ({
    id: `${each.machineId}/${each.connection ?? ''}`,
    profileId: profile.id,
    // Cast is safe: an unknown kind is said by its own name, as every connection word falls back.
    kind: (each.connection ?? 'observed') as AgentConnection['kind'],
    ...(each.label === undefined ? {} : { agentKind: each.label }),
    mediation: 'observed',
    firstSeen: '',
    lastSeen: '',
    status: each.live ? 'live' : 'idle',
    levels: cloudLevels(each.levels),
  }));
  return {
    id: profile.id,
    name: profile.name,
    skills: [],
    mcpServers: [],
    updatedAt: '',
    missing: [],
    ...(profile.purpose === undefined ? {} : { purpose: profile.purpose }),
    ...(profile.role === undefined ? {} : { role: profile.role }),
    responsibilities: [...(profile.responsibilities ?? [])],
    ...(responsible === undefined ? {} : { responsiblePerson: responsible }),
    projects: [...(profile.projects ?? [])],
    ...(profile.templateOf === undefined ? {} : { templateOf: profile.templateOf }),
    connections,
    levels: cloudLevels(view.levels),
  };
}

function handoffOf(each: CloudHandoff): WorkHandoff {
  return {
    id: each.id,
    from: { profileId: each.fromProfileId },
    to: { ...(each.toProfileId === undefined ? {} : { profileId: each.toProfileId }), ...(each.toPersonId === undefined ? {} : { person: each.toPersonId }) },
    reason: each.reason,
    refs: [],
    // Cast is safe: the work lines only ask whether a handoff is still requested.
    state: each.state as WorkHandoff['state'],
    requestedAt: each.requestedAt,
  };
}

/** A piece of the workspace's work as the work lines read it, its waiting handoffs with it. */
export function cloudWork(work: CloudWork, handoffs: readonly CloudHandoff[]): AgentWork {
  return {
    id: work.id,
    profileId: work.agentProfileId,
    responsiblePerson: work.responsiblePersonId,
    // Cast is safe: an unknown tracker is named by its own word, as `trackerName` falls back.
    target: { ...work.target, source: work.target.source as Tracker },
    sessions: [],
    attempts: 1,
    status: work.status as WorkStatus,
    progress: [],
    handoffs: handoffs.filter((each) => each.workId === work.id).map(handoffOf),
    createdAt: work.createdAt,
    updatedAt: work.updatedAt,
  };
}

/** Every piece of work the person answers for, then a piece of its own for each handoff on work they do not. */
export function cloudWorkAll(mine: CloudMyWork): AgentWork[] {
  const known = new Set(mine.work.map((each) => each.id));
  const orphans = mine.handoffs
    .filter((each) => !known.has(each.workId))
    .map(
      (each): AgentWork => ({
        id: each.workId,
        profileId: each.fromProfileId,
        responsiblePerson: '',
        target: { source: '' as Tracker, externalId: each.workId },
        sessions: [],
        attempts: 1,
        status: 'handoff_requested',
        progress: [],
        handoffs: [handoffOf(each)],
        createdAt: each.requestedAt,
        updatedAt: each.requestedAt,
      }),
    );
  return [...mine.work.map((each) => cloudWork(each, mine.handoffs)), ...orphans];
}

/** The profiles a reply holds, each one that cannot be read dropped, so one bad entry never hides the rest. */
export function readCloudProfiles(body: unknown): CloudProfileView[] {
  const list = isObject(body) && Array.isArray(body['profiles']) ? (body['profiles'] as unknown[]) : [];
  return list.filter((each): each is CloudProfileView => {
    if (!isObject(each)) return false;
    const profile = each['profile'];
    return isObject(profile) && typeof profile['id'] === 'string' && typeof profile['name'] === 'string';
  });
}

/** The person's work and handoffs, each that cannot be read dropped. */
export function readCloudMyWork(body: unknown): CloudMyWork {
  const work = isObject(body) && Array.isArray(body['work']) ? (body['work'] as unknown[]) : [];
  const handoffs = isObject(body) && Array.isArray(body['handoffs']) ? (body['handoffs'] as unknown[]) : [];
  return {
    work: work.filter((each): each is CloudWork => isObject(each) && typeof each['id'] === 'string' && typeof each['agentProfileId'] === 'string' && isObject(each['target'])),
    handoffs: handoffs.filter((each): each is CloudHandoff => isObject(each) && typeof each['id'] === 'string' && typeof each['workId'] === 'string'),
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** The words the workspace's agents are drawn with. */
export const WorkspaceAgentsLines = {
  title: 'In your workspace',
  intro: 'Agents Memnox Cloud reaches beyond this computer. Edit their jobs in the console.',
  handoffs: (count: number) => `In your workspace · ${count}`,
  signIn: 'Sign in to Memnox Cloud to answer this.',
  notTaken: (why: string) => `The workspace did not take the answer: ${why}`,
} as const;

/** The handoffs that wait on the person across every workspace, each with the work and workspace it is answered in. */
export function waitingHandoffs(remote: readonly { readonly workspace: string; readonly work: readonly AgentWork[] }[]): { workspace: string; work: AgentWork; handoff: WorkHandoff }[] {
  return remote.flatMap((each) =>
    each.work.flatMap((work) => {
      const handoff = work.handoffs.find((one) => one.state === 'requested');
      return handoff === undefined ? [] : [{ workspace: each.workspace, work, handoff }];
    }),
  );
}
