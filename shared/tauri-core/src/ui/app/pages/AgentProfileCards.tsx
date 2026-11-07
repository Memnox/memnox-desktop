import type { ProfileView } from '@memnox/core/wire';
import { Briefcase, Pencil } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { AgentWork } from '../../../core/domain/agent-wire';
import { currentWork, NO_AGENT, orderedProfiles, purposeLine, responsibleLine, shownConnections } from '../../../core/domain/agent-work-lines';
import { connectionStatusLine, headlineLevel } from '../../../core/domain/capability-level-lines';
import { JobsLines } from '../../../core/domain/profile-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CapabilityStrip, ConnectionPill, LevelPill } from '../capability-strip';
import { BrandLogo, Button, Card, CardGrid, Note, Section, StatusWord } from '../../kit';
import { JobSheet } from './JobsTab';
import { WorkLine } from './WorkTab';

/** As the Mac's agent grid sets it. */
const CARD_WIDTH = 300;
const CARD_LOGO = 30;

/**
 * The agents as their jobs, over the connections Memnox reaches them through, as the Mac's `AgentProfileCard`. A
 * runtime that sends no connections leaves this out, and the cards of what was found stand alone as before.
 */
export function AgentProfileCards({ parts }: { parts: SettingsParts }) {
  const { profiles, work, support, host } = parts;
  useObserved(profiles, work, support);
  const offersWork = support.supports('agent-work') === true;
  const [note, setNote] = useState<string | undefined>(undefined);
  const [jobFor, setJobFor] = useState<ProfileView | undefined>(undefined);
  const [editing, setEditing] = useState<ProfileView | undefined>(undefined);
  useEffect(() => {
    if (offersWork) void work.refresh();
  }, [offersWork]);
  const kept = profiles.profiles ?? [];
  const local = kept.some((each) => each.connections.length > 0 || each.isDefault === true);
  const all = offersWork ? (work.work ?? []) : [];
  return (
    <>
      {local && (
        <Section title="Your agents">
          {note !== undefined && <Note>{note}</Note>}
          <CardGrid min={CARD_WIDTH}>
            {orderedProfiles(kept).map((profile) => (
              <AgentProfileCard
                key={profile.id}
                profile={profile}
                work={currentWork(profile.id, all)}
                open={(url) => host.openPage(url)}
                giveJob={() => (profile.isDefault === true ? setJobFor(profile) : setEditing(profile))}
              />
            ))}
          </CardGrid>
        </Section>
      )}
      {(jobFor !== undefined || editing !== undefined) && (
        <JobSheet
          parts={parts}
          {...(jobFor === undefined ? {} : { jobFor })}
          {...(editing === undefined ? {} : { editing })}
          close={() => {
            setJobFor(undefined);
            setEditing(undefined);
          }}
          said={(outcome) => setNote(outcome.kind === 'done' ? outcome.note : outcome.why)}
        />
      )}
    </>
  );
}

/**
 * One agent as its job: the name and purpose line, who answers for it, each way Memnox reaches it as a pill wearing
 * its level, and the work it carries now. A default is offered a job; one with no agent behind it stays grey with no
 * activity. `giveJob` is left out for a job the workspace keeps, which is edited in the console.
 */
export function AgentProfileCard({ profile, work, open, giveJob }: { profile: ProfileView; work?: AgentWork | undefined; open?: (url: string) => void; giveJob?: () => void }) {
  const bound = profile.connections.length > 0;
  const responsible = responsibleLine(profile);
  return (
    <Card label={profile.name} className={`flex flex-col gap-3 ${bound ? '' : 'opacity-70'}`}>
      <div className="flex items-center gap-2.5">
        <BrandLogo agent={profile.connections[0]?.agentKind} name={profile.name} size={CARD_LOGO} />
        <div className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-headline font-semibold text-foreground">{profile.name}</span>
          <span className="line-clamp-2 text-meta text-muted">{purposeLine(profile)}</span>
        </div>
        {bound && <LevelPill level={headlineLevel(profile.levels)} />}
      </div>
      {responsible !== undefined && <span className="text-meta text-muted">{responsible}</span>}
      {bound ? (
        <>
          <div className="flex flex-col gap-1.5">
            <span className="text-label font-medium text-muted">Connected through</span>
            {shownConnections(profile).map((connection) => (
              <span key={connection.id} className="flex items-center gap-2">
                <ConnectionPill connection={connection} />
                <span className="truncate text-meta text-muted">{connectionStatusLine(connection)}</span>
              </span>
            ))}
          </div>
          {work !== undefined && <WorkLine work={work} {...(open === undefined ? {} : { open })} />}
          <details>
            <summary className="mx-focus cursor-pointer text-footnote font-medium text-muted select-none">{JobsLines.howSure}</summary>
            <div className="pt-2">
              <CapabilityStrip levels={profile.levels} />
            </div>
          </details>
        </>
      ) : (
        <StatusWord tone="quiet">{NO_AGENT}</StatusWord>
      )}
      {giveJob !== undefined && (
        <div className="mt-auto">
          <Button kind={profile.isDefault === true ? 'primary' : 'secondary'} icon={profile.isDefault === true ? Briefcase : Pencil} onClick={giveJob}>
            {profile.isDefault === true ? JobsLines.giveJob : JobsLines.editJob}
          </Button>
        </div>
      )}
    </Card>
  );
}
