import type { ProfileView } from '@memnox/core/wire';
import type { AgentWork, WorkHandoff } from './agent-wire';

/**
 * What a screen says about agent work and about an agent's job, mirroring the Mac's `AgentWorkLines` and
 * `AgentProfileLines`. The issue stays in its tracker; nothing here fetches it or decides what may happen to it.
 */

const FINISHED: readonly string[] = ['done', 'stopped'];

export function isFinished(work: AgentWork): boolean {
  return FINISHED.includes(work.status);
}

export function openWork(work: readonly AgentWork[]): AgentWork[] {
  return work.filter((each) => !isFinished(each));
}

export function finishedWork(work: readonly AgentWork[]): AgentWork[] {
  return work.filter(isFinished);
}

/** The open work a profile's agent carries now, the newest first. */
export function currentWork(profileId: string, work: readonly AgentWork[]): AgentWork | undefined {
  return openWork(work).find((each) => each.profileId === profileId);
}

export function issueLine(work: AgentWork): string {
  const title = work.target.title;
  return title === undefined || title === '' ? work.target.externalId : `${work.target.externalId} · ${title}`;
}

const TRACKER_NAMES: Record<string, string> = { linear: 'Linear', jira: 'Jira', github: 'GitHub', asana: 'Asana' };

export function trackerName(source: string): string {
  return TRACKER_NAMES[source] ?? source;
}

const STATUS_WORDS: Record<string, string> = {
  active: 'Working',
  blocked: 'Blocked',
  handoff_requested: 'Wants to hand it on',
  done_claimed: 'Says it is done',
  done: 'Done',
  stopped: 'Stopped',
};

export function workStatusLine(work: AgentWork): string {
  return STATUS_WORDS[work.status] ?? work.status;
}

export function waitingHandoff(work: AgentWork): WorkHandoff | undefined {
  return work.handoffs.find((each) => each.state === 'requested');
}

/** Whether it waits on the person: a handoff to answer or a done claim to check. */
export function needsYou(work: AgentWork): boolean {
  return work.status === 'done_claimed' || waitingHandoff(work) !== undefined;
}

export function latestLine(work: AgentWork): string {
  return work.progress.at(-1)?.note ?? 'No word from the agent yet.';
}

export function handoffLine(handoff: WorkHandoff, profileName: (id: string) => string | undefined): string {
  const to = handoff.to.profileId !== undefined ? (profileName(handoff.to.profileId) ?? handoff.to.profileId) : (handoff.to.person ?? 'someone else');
  return `Wants to hand it to ${to}: ${handoff.reason}`;
}

/** The link to open, only a web address, so a tracker's link never starts an app. */
export function workLink(work: AgentWork): string | undefined {
  const url = work.target.url;
  return url !== undefined && /^https?:\/\/[^/]/i.test(url) ? url : undefined;
}

export function startedLine(target: string): string {
  return `Started on ${target.trim()}. The agent sees it at its next pause.`;
}

export function answeredLine(word: 'accept' | 'decline'): string {
  return word === 'accept' ? 'Handed on.' : 'Declined. The work stays with the agent that has it.';
}

export function targetProblem(target: string): string | undefined {
  return target.trim() === '' ? 'Paste the issue key, such as LIN-123, or its link.' : undefined;
}

/** A field left blank is not sent, so the daemon never stores an empty title or folder. */
export function filled(text: string | undefined): string | undefined {
  const trimmed = text?.trim();
  return trimmed === undefined || trimmed === '' ? undefined : trimmed;
}

/** The line under an agent's name: the job's purpose, else what it was kept for, else that it has no job yet. */
export function purposeLine(profile: ProfileView): string {
  return filled(profile.purpose) ?? filled(profile.description) ?? (profile.isDefault === true ? 'No job yet.' : 'No purpose written yet.');
}

export function responsibleLine(profile: ProfileView): string | undefined {
  const person = filled(profile.responsiblePerson);
  return person === undefined ? undefined : `Answers to ${person}`;
}

/** The agents with a job first, then the defaults, then the jobs with nobody behind them, each by name. */
export function orderedProfiles(profiles: readonly ProfileView[]): ProfileView[] {
  const rank = (profile: ProfileView) => (profile.isDefault === true ? 1 : profile.connections.length > 0 ? 0 : 2);
  return [...profiles].sort((one, two) => rank(one) - rank(two) || one.name.toLowerCase().localeCompare(two.name.toLowerCase()));
}

export const NO_AGENT = 'No agent behind it yet';

/** The connections a card shows: every one not gone, then the gone ones, which say they are not found any more. */
export function shownConnections(profile: Pick<ProfileView, 'connections'>): ProfileView['connections'] {
  return [...profile.connections.filter((each) => each.status !== 'gone'), ...profile.connections.filter((each) => each.status === 'gone')];
}

/** The agent an Unbind names: its ledger key, else its kind, so a binding is taken off the agent it was put on. */
export function connectionAgent(connection: ProfileView['connections'][number]): string | undefined {
  return connection.agentId ?? connection.agentKind;
}
