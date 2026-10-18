import { DAEMON_EVENT, type DaemonEvent } from '@memnox/core/wire';
import { CloudInbox } from '../core/application/cloud-inbox';
import type { HeldCalls, HeldCallsOptions } from '../core/application/held-calls';
import type { ConfirmKey } from '../core/application/ports/confirm-key';
import type { DaemonLink } from '../core/application/ports/daemon-link';
import type { PreferenceStore } from '../core/application/ports/preference-store';
import type { RequestIds } from '../core/application/request-ids';
import { ServerFeeds } from '../core/application/server-feeds';
import type { Talking, TalkingOptions, Timer } from '../core/application/talking';
import { THIS_COMPUTER_TARGET, TargetLink } from '../core/application/target-link';
import { TeamInbox } from '../core/application/team-inbox';
import { WorkspaceAnswering } from '../core/application/workspace-answering';
import { deliversFrom } from '../core/domain/machine-events';
import { settledLine } from '../core/domain/settled-line';
import { tauriCloud, tauriPersonCredential } from './adapters/tauri-cloud';
import { TauriRelayLink, tauriPairer } from './adapters/tauri-relay';

/** The server the voice talks to, by machine id, empty for this computer; Settings writes it and the island follows. */
export const TALKING_TO = 'memnox.talkingTo';
/** Bumped by Settings when a server is paired or forgotten, so the island opens or drops its link. */
export const SERVERS_CHANGED = 'memnox.servers.changed';
/** Bumped when the person signs in or out of their workspace, so the island reads the inbox again or stops. */
export const TEAM_CHANGED = 'memnox.team.changed';

/**
 * The island's half of the relay and the workspace: one link that routes every request to the machine it belongs
 * to, a feed from every paired server, and the team's inbox. Built beside the island's composition root so that
 * root only hands its links over and back.
 */
export function islandRelay(parts: { local: DaemonLink; ids: RequestIds; key: ConfirmKey; timer: Timer; store: PreferenceStore }) {
  const target = new TargetLink(parts.local);
  const team = new WorkspaceAnswering(new CloudInbox(tauriCloud), tauriPersonCredential, parts.key);
  /** What HeldCalls takes: answers by the link that routes them, this computer's events filtered and remembered, the team's own answers. */
  const heldOptions: Pick<HeldCallsOptions, 'answers' | 'accept' | 'team'> = {
    answers: target,
    accept: (event: DaemonEvent) => {
      if (!deliversFrom(event, !target.isRemote, true)) return false;
      target.remember(event.subject, THIS_COMPUTER_TARGET);
      if (event.kind === DAEMON_EVENT.SETTLED) target.forget(event.subject);
      return true;
    },
    team: { owns: (subject) => team.owns(subject), answer: (subject, answer, reason) => team.answer(subject, answer, reason) },
  };
  let calls: HeldCalls | undefined;
  const talkingOptions: Pick<TalkingOptions, 'team' | 'raisedOn' | 'signsEveryYes' | 'teamAnswered'> = {
    team,
    // A team's question answered by voice leaves the island the way a press of its button does.
    teamAnswered: (subject, outcome) => {
      target.forget(subject);
      calls?.settledElsewhere(subject, outcome.kind === 'answered-elsewhere' ? settledLine(outcome.earlier.word) : undefined);
    },
    raisedOn: (subject) => target.serverNameFor(subject),
    signsEveryYes: (subject) => target.reachesAnotherMachine(subject),
  };

  /** Starts the servers' feeds and the inbox once the queue and the voice exist. */
  function start(island: { calls: HeldCalls; talking: Talking }): void {
    calls = island.calls;
    const feeds = new ServerFeeds(target, (machineId) => new TauriRelayLink(machineId), parts.ids, (event, server) => island.calls.fromServer(event, server), (ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    const restore = () =>
      void tauriPairer
        .servers()
        .then((servers) => feeds.restore(servers, parts.store.load(TALKING_TO) || undefined))
        .catch(() => undefined);
    const inbox = new TeamInbox(team, {
      arrived: (call) => {
        // Known to belong to the workspace, so no daemon link is ever sent its answer.
        target.rememberWorkspace(call.id);
        island.calls.holdTeam(call);
        void island.talking.announceTeam(call);
      },
      gone: (id, note) => {
        if (!target.belongsToWorkspace(id)) return;
        target.forget(id);
        island.calls.settledElsewhere(id, note);
        island.talking.teamSettled(id);
      },
      signedOut: () => void tauriPersonCredential.delete().then(() => parts.store.save(TEAM_CHANGED, String(Date.now()))),
    }, parts.timer);
    window.addEventListener('storage', (event) => {
      if (event.key === TALKING_TO || event.key === SERVERS_CHANGED) restore();
      if (event.key === TEAM_CHANGED) void inbox.read();
    });
    restore();
    inbox.start();
  }

  return { target, team, heldOptions, talkingOptions, start };
}
