import type { HoldAnswer } from '@memnox/core/wire';
import type { InboxAnswerReply, PersonCode, PersonToken, RegisteredDevice, WorkspaceCredential, WorkspaceHeldCall, WorkspaceRef } from '../../domain/workspace-wire';

/** Where asking whether the person approved the code stands. */
export type CodeRedemption =
  /** Nobody has answered in the console yet, so the asking goes on. */
  | { kind: 'pending' }
  | { kind: 'granted'; token: PersonToken }
  /** Refused, expired or spent: the cloud's word for it, and the asking stops. */
  | { kind: 'stopped'; word: string };

/** Why the workspace would not do what was asked, in the statuses the inbox contract names. */
export type WorkspaceInboxFailure =
  /** 401: the credential was revoked or the member suspended, so the person signs in again. */
  | { kind: 'signed-out' }
  /** 403: the call has not reached this person, or a yes whose signature did not verify. */
  | { kind: 'not-reached'; words: string }
  /** 404: no machine holds that call, or the device is not this person's. */
  | { kind: 'not-found'; words: string }
  /** 409: answered already, or the machine stopped waiting. */
  | { kind: 'settled'; words: string }
  | { kind: 'refused'; status: number; words: string }
  /** Nothing came back at all. */
  | { kind: 'unreachable'; words: string };

/** Thrown by an inbox for a failure the contract names. */
export class WorkspaceInboxError extends Error {
  constructor(readonly failure: WorkspaceInboxFailure) {
    super(`${failure.kind}${'words' in failure ? `: ${failure.words}` : ''}`);
  }
}

/**
 * The person's side of Memnox Cloud: signing in with a code, registering this computer's key, and the held calls
 * routed to them. The workspace decides who a call reaches; this only carries what it says. Ported from the Mac's `WorkspaceInbox`.
 */
export interface WorkspaceInbox {
  startSignIn(name: string): Promise<PersonCode>;
  redeem(deviceCode: string): Promise<CodeRedemption>;
  workspaces(token: string): Promise<readonly WorkspaceRef[]>;
  /** Registers this computer with the public half of its confirm key, which every yes is verified against. */
  registerDevice(name: string, signingPoint: string, token: string): Promise<RegisteredDevice>;
  /** Removes this computer, which also revokes the credential that registered it. */
  removeDevice(id: string, token: string): Promise<void>;
  /** The open calls routed to the person in one workspace, oldest first, and those settled a moment ago. */
  held(workspace: string, token: string): Promise<readonly WorkspaceHeldCall[]>;
  /** One answer; a yes carries the signature, a deny goes without one. */
  answer(call: string, workspace: string, answer: HoldAnswer, deviceId: string, signature: string | undefined, token: string): Promise<InboxAnswerReply>;
}

/** Where the signed in person's credential is kept between launches; a bearer token, so the real one is the system's credential store. */
export interface PersonCredentialStore {
  load(): Promise<WorkspaceCredential | undefined>;
  save(credential: WorkspaceCredential): Promise<void>;
  delete(): Promise<void>;
}

/** One HTTP exchange with Memnox Cloud, so the inbox is tested with no network. */
export interface HttpTransport {
  /** The status and the body, or a throw when nothing came back. */
  send(method: 'GET' | 'POST' | 'DELETE', path: string, body: string | undefined, token: string | undefined): Promise<{ status: number; body: string }>;
}
