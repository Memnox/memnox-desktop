import type { HoldAnswer } from '@memnox/core/wire';
import { PERSON_DEVICE_KIND, readHeldCall, type InboxAnswerReply, type PersonCode, type PersonToken, type RegisteredDevice, type WorkspaceHeldCall, type WorkspaceRef } from '../domain/workspace-wire';
import { readCloudMyWork, readCloudProfiles, type CloudMyWork, type CloudProfileView } from '../domain/workspace-agents';
import { readWorkCorrelations, type WorkCorrelation } from '../domain/work-correlations';
import { WorkspaceInboxError, type CodeRedemption, type HttpTransport, type WorkspaceAgentsReader, type WorkspaceInbox } from './ports/workspace-inbox';

/** Still waiting on the console is the one refusal that keeps the asking going. */
const PENDING = 'authorization_pending';
/** Recent settled calls come too, so a card can say who answered it; a cloud that ignores the query sends only open ones. */
const RECENT = 'include=recent';

/**
 * The person inbox over Memnox Cloud's JSON API, as memnox-cloud/docs/person-inbox.md describes it, over one
 * HTTP exchange at a time. Ported from the Mac's `HttpWorkspaceInbox`.
 */
export class CloudInbox implements WorkspaceInbox, WorkspaceAgentsReader {
  constructor(private readonly transport: HttpTransport) {}

  startSignIn(name: string): Promise<PersonCode> {
    return this.call<PersonCode>('POST', 'v1/person/codes', { name, kind: PERSON_DEVICE_KIND });
  }

  async redeem(deviceCode: string): Promise<CodeRedemption> {
    const { status, body } = await this.exchange('POST', 'v1/person/tokens', { deviceCode });
    if (succeeded(status)) return { kind: 'granted', token: decode<PersonToken>(body) };
    const word = errorWord(body);
    if (word === PENDING) return { kind: 'pending' };
    if (status === 400 || status === 403) return { kind: 'stopped', word: word ?? String(status) };
    throw failure(status, body);
  }

  async workspaces(token: string): Promise<readonly WorkspaceRef[]> {
    return (await this.call<{ workspaces: WorkspaceRef[] }>('GET', 'v1/me', undefined, token)).workspaces ?? [];
  }

  registerDevice(name: string, signingPoint: string, token: string): Promise<RegisteredDevice> {
    return this.call<RegisteredDevice>('POST', 'v1/me/devices', { name, kind: PERSON_DEVICE_KIND, signingPoint }, token);
  }

  async removeDevice(id: string, token: string): Promise<void> {
    const { status, body } = await this.exchange('DELETE', `v1/me/devices/${segment(id)}`, undefined, token);
    if (!succeeded(status)) throw failure(status, body);
  }

  async held(workspace: string, token: string): Promise<readonly WorkspaceHeldCall[]> {
    const listed = await this.call<unknown>('GET', `v1/workspaces/${segment(workspace)}/me/held-calls?${RECENT}`, undefined, token);
    // One item that cannot be read never hides every other from the island.
    return Array.isArray(listed) ? listed.map(readHeldCall).filter((call): call is WorkspaceHeldCall => call !== undefined) : [];
  }

  answer(call: string, workspace: string, answer: HoldAnswer, deviceId: string, signature: string | undefined, token: string): Promise<InboxAnswerReply> {
    const body: Record<string, string> = { answer, deviceId };
    if (signature !== undefined) body['signature'] = signature;
    return this.call<InboxAnswerReply>('POST', `v1/workspaces/${segment(workspace)}/me/held-calls/${segment(call)}/answer`, body, token);
  }

  /** The workspace's jobs, for agents no daemon here reaches. */
  async agentProfiles(workspace: string, token: string): Promise<readonly CloudProfileView[]> {
    return readCloudProfiles(await this.call<unknown>('GET', `v1/workspaces/${segment(workspace)}/agent-profiles`, undefined, token));
  }

  async myAgentWork(workspace: string, token: string): Promise<CloudMyWork> {
    return readCloudMyWork(await this.call<unknown>('GET', `v1/workspaces/${segment(workspace)}/me/agent-work`, undefined, token));
  }

  async workCorrelations(workspace: string, sessionIds: readonly string[], token: string): Promise<readonly WorkCorrelation[]> {
    if (sessionIds.length === 0) return [];
    const sessions = encodeURIComponent([...sessionIds].sort().join(','));
    return readWorkCorrelations(await this.call<unknown>('GET', `v1/workspaces/${segment(workspace)}/work-correlations?session=${sessions}`, undefined, token));
  }

  /** The answer goes as the cloud's own boolean, unsigned, since it only moves who carries the work. */
  async answerHandoff(handoff: string, workspace: string, accept: boolean, token: string): Promise<void> {
    const { status, body } = await this.exchange('POST', `v1/workspaces/${segment(workspace)}/me/handoffs/${segment(handoff)}/answer`, { accept }, token);
    if (!succeeded(status)) throw failure(status, body);
  }

  private async call<T>(method: 'GET' | 'POST' | 'DELETE', path: string, body?: Record<string, string>, token?: string): Promise<T> {
    const { status, body: answered } = await this.exchange(method, path, body, token);
    if (!succeeded(status)) throw failure(status, answered);
    return decode<T>(answered);
  }

  private async exchange(method: 'GET' | 'POST' | 'DELETE', path: string, body?: Record<string, string | boolean>, token?: string): Promise<{ status: number; body: string }> {
    try {
      return await this.transport.send(method, path, body === undefined ? undefined : JSON.stringify(sorted(body)), token);
    } catch (error) {
      throw new WorkspaceInboxError({ kind: 'unreachable', words: error instanceof Error ? error.message : String(error) });
    }
  }
}

function succeeded(status: number): boolean {
  return status >= 200 && status <= 299;
}

function decode<T>(body: string): T {
  try {
    return JSON.parse(body) as T;
  } catch {
    throw new WorkspaceInboxError({ kind: 'refused', status: 0, words: 'the workspace answered in a shape this app cannot read' });
  }
}

/** The status the contract names, with whatever words the cloud put beside it. */
export function failure(status: number, body: string): WorkspaceInboxError {
  const words = errorWord(body) ?? `status ${status}`;
  switch (status) {
    case 401:
      return new WorkspaceInboxError({ kind: 'signed-out' });
    case 403:
      return new WorkspaceInboxError({ kind: 'not-reached', words });
    case 404:
      return new WorkspaceInboxError({ kind: 'not-found', words });
    case 409:
      return new WorkspaceInboxError({ kind: 'settled', words });
    default:
      return new WorkspaceInboxError({ kind: 'refused', status, words });
  }
}

/** The cloud says why under `error` for the code flow and under `message` for its framework's own refusals. */
export function errorWord(body: string): string | undefined {
  try {
    const object = JSON.parse(body) as Record<string, unknown>;
    for (const field of ['error', 'message']) {
      const text = object[field];
      if (typeof text === 'string' && text !== '') return text;
    }
  } catch {
    // Not JSON, so there are no words to read.
  }
  return undefined;
}

/** An id from the cloud kept to one path segment, so nothing in it can reach another route. */
function segment(id: string): string {
  return encodeURIComponent(id);
}

/** Keys in order, as the Mac writes its bodies. */
function sorted(body: Record<string, string | boolean>): Record<string, string | boolean> {
  return Object.fromEntries(Object.entries(body).sort(([a], [b]) => (a < b ? -1 : 1)));
}
