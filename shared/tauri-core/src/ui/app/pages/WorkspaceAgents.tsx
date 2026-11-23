import { useEffect, useState } from 'react';
import { currentWork, handoffLine, issueLine, orderedProfiles } from '../../../core/domain/agent-work-lines';
import { waitingHandoffs, WorkspaceAgentsLines } from '../../../core/domain/workspace-agents';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button, Card, CardGrid, Note, Panel, Row, Section } from '../../kit';
import { teamRuleChangeLines, TeamRuleChangeLines } from '../../../core/domain/team-rule-changes';
import { AgentProfileCard } from './AgentProfileCards';
import { WorkLine } from './WorkCards';

/** As the Mac's agent grid sets it. */
const CARD_WIDTH = 300;

/** Reads the workspace's agents once the page opens, and again whenever the person signs in or out. */
function useWorkspaceAgents(parts: SettingsParts): void {
  const { workspaceAgents, team } = parts;
  useObserved(workspaceAgents, team);
  const step = team.step.kind;
  useEffect(() => {
    void workspaceAgents.refresh();
  }, [step]);
}

/**
 * In your workspace: the jobs Memnox Cloud keeps, for agents hosted elsewhere, drawn as the cards on this computer
 * are. Shown only while the person is signed in, so with no account the list here is the whole of it and nothing is
 * sent anywhere. Mirrors the Mac's `WorkspaceAgentsSection`.
 */
export function WorkspaceAgentsSection({ parts }: { parts: SettingsParts }) {
  const { workspaceAgents, host } = parts;
  useWorkspaceAgents(parts);
  const remote = workspaceAgents.remote;
  const profiles = remote.flatMap((each) => each.profiles);
  if (!workspaceAgents.signedIn || profiles.length === 0) return null;
  const work = remote.flatMap((each) => each.work);
  return (
    <Section title={WorkspaceAgentsLines.title}>
      <p className="text-footnote text-muted">{WorkspaceAgentsLines.intro}</p>
      <CardGrid min={CARD_WIDTH}>
        {orderedProfiles(profiles).map((profile) => (
          <AgentProfileCard key={profile.id} profile={profile} work={currentWork(profile.id, work)} open={(url) => host.openPage(url)} />
        ))}
      </CardGrid>
    </Section>
  );
}

/** The workspace's handoffs waiting on the person, for Needs your attention, each answered through the workspace. */
export function WorkspaceHandoffs({ parts }: { parts: SettingsParts }) {
  const { workspaceAgents, host } = parts;
  useWorkspaceAgents(parts);
  const [note, setNote] = useState<string | undefined>(undefined);
  const remote = workspaceAgents.remote;
  const waiting = waitingHandoffs(remote);
  if (!workspaceAgents.signedIn || waiting.length === 0) return null;
  const names = new Map(remote.flatMap((each) => each.profiles).map((each) => [each.id, each.name]));
  const busy = workspaceAgents.busy !== undefined;
  return (
    <Section title={WorkspaceAgentsLines.handoffs(waiting.length)}>
      {note !== undefined && <Note>{note}</Note>}
      <div className="flex flex-col gap-3">
        {waiting.map(({ workspace, work, handoff }) => {
          const answer = (word: 'accept' | 'decline') => void workspaceAgents.answer(handoff.id, workspace, word).then((outcome) => setNote(outcome.kind === 'done' ? outcome.note : outcome.why));
          return (
            <Card key={handoff.id} label={issueLine(work)} className="flex flex-col gap-3">
              <WorkLine work={work} open={(url) => host.openPage(url)} />
              <p className="text-footnote text-foreground">{handoffLine(handoff, (id) => names.get(id))}</p>
              <div className="flex gap-2">
                <Button kind="primary" disabled={busy} onClick={() => answer('accept')}>
                  Accept
                </Button>
                <Button disabled={busy} onClick={() => answer('decline')}>
                  Decline
                </Button>
              </div>
            </Card>
          );
        })}
      </div>
    </Section>
  );
}

/**
 * The team's rule changes that wait on a second person, listed here so they are seen, and opened in Memnox Cloud to
 * approve, since the team signs them there rather than on this computer. Mirrors the Mac's `TeamRuleChanges`.
 */
export function TeamRuleChanges({ parts }: { parts: SettingsParts }) {
  const { workspaceAgents, host } = parts;
  useObserved(workspaceAgents);
  if (!workspaceAgents.signedIn) return null;
  const lines = teamRuleChangeLines(workspaceAgents.remote.flatMap((each) => each.ruleChanges), Date.now());
  if (lines.length === 0) return null;
  return (
    <Section
      title={`${TeamRuleChangeLines.title} \u00B7 ${lines.length}`}
      trailing={<Button kind="link" onClick={() => host.openPage(TeamRuleChangeLines.consoleAddress)}>{TeamRuleChangeLines.open}</Button>}
    >
      <p className="text-footnote text-muted">{TeamRuleChangeLines.detail}</p>
      <Panel>
        {lines.map((line) => (
          <Row key={line.id} title={line.title} caption={line.caption} />
        ))}
      </Panel>
    </Section>
  );
}
