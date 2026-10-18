import type { DaemonEvent } from '@memnox/core/wire';
import { agentKind } from './agent-colour';
import { callLabel, ON_THIS_COMPUTER, placeMachine, type CallPlace } from './call-label';
import { callPlace, callWhat, callWhy, callWho, type WorkspaceHeldCall } from './workspace-wire';

/** A held call as the island draws it: whose it is, what it wants, why it was held. */
export interface HeldCard {
  readonly subject: string;
  /** The agent's kind, its id without `agt_`, which picks its colour and logo. */
  readonly agent: string;
  /** Whose call it is as the card heads it: "Codex". */
  readonly who: string;
  /** "codex on this computer". */
  readonly label: string;
  /** What it wants to do as a phrase, or the daemon's summary when it gave none. */
  readonly what: string;
  readonly why: string | undefined;
  readonly task: string | undefined;
  readonly place: string | undefined;
  /** The daemon placed the call inside its session's repository, so a yes goes without the key. */
  readonly withinSession: boolean;
  /** An allow reaches outside the session and is signed, so its buttons carry the fingerprint before they are pressed. */
  readonly touchID: boolean;
  readonly expiresAt: string | undefined;
  /** The session that is waiting, so its logo beside the notch hops until somebody answers. */
  readonly sessionId: string | undefined;
}

/**
 * The card for a HELD event, labelled with where it waits: this computer, or the server that raised it. A server
 * takes no yes without a signature, so its card always carries the fingerprint, whatever the event says.
 */
export function heldCard(event: DaemonEvent, place: CallPlace = ON_THIS_COMPUTER): HeldCard {
  const local = place.kind === 'this-computer';
  const within = local && event.withinSession === true;
  return {
    subject: event.subject,
    agent: agentKind(event.agent),
    // Away from this computer the card heads with where it waits, as the Mac's does.
    who: local ? (event.agentName ?? event.agent) : callLabel(event.agentName ?? event.agent, place),
    label: callLabel(event.agentName ?? event.agent, place),
    what: event.what ?? event.summary,
    why: event.why,
    task: event.task,
    place: event.place,
    withinSession: within,
    touchID: !within,
    expiresAt: event.expiresAt,
    sessionId: event.sessionId,
  };
}

/** The card for a teammate's call the workspace routed here, whose every yes is signed. Ported from the Mac's `HeldCard(team:)`. */
export function teamHeldCard(call: WorkspaceHeldCall): HeldCard {
  return {
    subject: call.id,
    agent: agentKind(call.agent),
    who: callWho(call),
    label: callWho(call),
    what: callWhat(call),
    why: callWhy(call) === '' ? undefined : callWhy(call),
    task: undefined,
    place: undefined,
    withinSession: false,
    touchID: true,
    expiresAt: call.expiresAt === '' ? undefined : call.expiresAt,
    sessionId: undefined,
  };
}

/** The machine the island's queue header groups a teammate's call under. */
export function teamMachine(call: WorkspaceHeldCall): string {
  return placeMachine(callPlace(call));
}
