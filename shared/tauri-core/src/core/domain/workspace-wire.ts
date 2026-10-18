import type { TeamCallBrief } from '@memnox/core/wire';
import { callLabel, teamPlace, trimmed, type CallPlace } from './call-label';
import { readInstant } from './pairing-invitation';
import { settledLine } from './settled-line';

// The person inbox as memnox-cloud/docs/person-inbox.md names it, field for field. Ported from the Mac's `WorkspaceWire`.

/** What the workspace calls a device when it introduces itself. */
export const PERSON_DEVICE_KIND = 'desktop';

/** The code a person approves in the console, and how often to ask whether they have. */
export interface PersonCode {
  readonly deviceCode: string;
  readonly userCode: string;
  readonly intervalSeconds: number;
  /** Epoch milliseconds, as the cloud sends it. */
  readonly expiresAt: number;
  readonly verificationUri?: string;
  readonly verificationUriComplete?: string;
}

/** The page to open, the one that already carries the code when the cloud gave it. */
export function codePage(code: PersonCode): string | undefined {
  return code.verificationUriComplete ?? code.verificationUri;
}

/** The credential the console granted once the person approved the code. */
export interface PersonToken {
  readonly token: string;
  readonly tokenId: string;
  /** The member held calls are routed to. */
  readonly personId: string;
  readonly name: string;
  readonly role: string;
  readonly orgId: string;
}

/** This computer as the workspace registered it, whose id every answer names. */
export interface RegisteredDevice {
  readonly id: string;
  readonly name?: string;
  readonly kind?: string;
}

/** One workspace the person reaches, as `GET /v1/me` lists it. */
export interface WorkspaceRef {
  readonly id: string;
  readonly orgId?: string;
}

/** What the credential store keeps for the signed in person: the credential, where to poll and the device answers name. */
export interface WorkspaceCredential {
  readonly token: string;
  readonly tokenId: string;
  readonly personId: string;
  readonly name: string;
  readonly orgId: string;
  readonly workspaces: readonly string[];
  readonly deviceId: string;
}

/** What an answer from the inbox did: `answered` went back to the machine, `counted` waits on more yeses. */
export interface InboxAnswerReply {
  readonly id: string;
  readonly status: string;
  readonly answer?: string;
  readonly approvalsNeeded: number;
}

/**
 * A held call a teammate's agent raised that the workspace routed to this person. With `include=recent` the
 * inbox also lists calls settled a moment ago, with who answered and where; any field may be missing but the id.
 */
export interface WorkspaceHeldCall {
  readonly id: string;
  readonly machineId: string;
  readonly machineLabel: string | undefined;
  readonly machineClass: string;
  readonly agent: string;
  readonly operation: string;
  readonly target: string | undefined;
  readonly summary: string | undefined;
  readonly why: string | undefined;
  readonly reason: string;
  readonly askedAt: string;
  readonly expiresAt: string;
  readonly escalated: boolean;
  readonly approvalsNeeded: number;
  readonly approvedByYou: boolean;
  /** Whose team the call came from, by the teammate's name. */
  readonly ownerName: string | undefined;
  readonly answer: string | undefined;
  readonly answeredBy: string | undefined;
  readonly answeredOn: string | undefined;
}

/** The class the contract reads a machine nobody can find as. */
const WORKSTATION = 'workstation';

const text = (value: unknown): string | undefined => (typeof value === 'string' ? value : undefined);

/** One item of the inbox, read leniently, or undefined without an id, so one odd call never hides the rest. */
export function readHeldCall(raw: unknown): WorkspaceHeldCall | undefined {
  if (typeof raw !== 'object' || raw === null) return undefined;
  const item = raw as Record<string, unknown>;
  const id = text(item['id']);
  if (id === undefined) return undefined;
  return {
    id,
    machineId: text(item['machineId']) ?? '',
    machineLabel: text(item['machineLabel']),
    machineClass: text(item['machineClass']) ?? WORKSTATION,
    agent: text(item['agent']) ?? '',
    operation: text(item['operation']) ?? '',
    target: text(item['target']),
    summary: text(item['summary']),
    why: text(item['why']),
    reason: text(item['reason']) ?? '',
    askedAt: text(item['askedAt']) ?? '',
    expiresAt: text(item['expiresAt']) ?? '',
    escalated: item['escalated'] === true,
    approvalsNeeded: typeof item['approvalsNeeded'] === 'number' ? item['approvalsNeeded'] : 1,
    approvedByYou: item['approvedByYou'] === true,
    ownerName: text(item['ownerName']),
    answer: text(item['answer']),
    answeredBy: text(item['answeredBy']),
    answeredOn: text(item['answeredOn']),
  };
}

/** The teammate's machine, by the name it was given, else its id. */
export function callPlace(call: WorkspaceHeldCall): CallPlace {
  return teamPlace(trimmed(call.machineLabel) ?? call.machineId, call.ownerName);
}

/** "codex on build-box, from Ana's team", so the person sees whose machine waits and that it came through the workspace. */
export function callWho(call: WorkspaceHeldCall): string {
  return callLabel(call.agent, callPlace(call));
}

/** Settled already, listed only so the card can say who answered it before it leaves. */
export function isSettled(call: WorkspaceHeldCall): boolean {
  return call.answer !== undefined || call.answeredBy !== undefined || call.answeredOn !== undefined;
}

export function callSettledLine(call: WorkspaceHeldCall): string {
  return settledLine(call.answer, call.answeredBy, call.answeredOn);
}

/** What it wants, in the cloud's own words where it gave some, else the operation and its target. */
export function callWhat(call: WorkspaceHeldCall): string {
  if (call.summary !== undefined && call.summary !== '') return call.summary;
  return [call.operation, call.target].filter((part): part is string => part !== undefined).join(' ');
}

/** Why it is held: the rule's own sentence where there is one, else the reason the policy gave. */
export function callWhy(call: WorkspaceHeldCall): string {
  return call.why !== undefined && call.why !== '' ? call.why : call.reason;
}

/** When the machine stops waiting, undefined when the cloud sent a date this app cannot read. */
export function callExpiry(call: WorkspaceHeldCall): number | undefined {
  return readInstant(call.expiresAt);
}

export function callBrief(call: WorkspaceHeldCall): TeamCallBrief {
  return { id: call.id, label: callWho(call), what: callWhat(call) };
}
