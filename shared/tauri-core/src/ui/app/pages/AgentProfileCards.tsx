import type { ProfileView } from '@memnox/core/wire';
import { useEffect } from 'react';
import { currentWork, NO_AGENT, orderedProfiles, purposeLine, responsibleLine } from '../../../core/domain/agent-work-lines';
import { connectionStatusLine, headlineLevel } from '../../../core/domain/capability-level-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CapabilityStrip, ConnectionPill, LevelPill } from '../capability-strip';
import { BrandLogo, Card, CardGrid, Section, StatusWord } from '../../kit';
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
  useEffect(() => {
    if (offersWork) void work.refresh();
  }, [offersWork]);
  const kept = profiles.profiles ?? [];
  if (!kept.some((each) => each.connections.length > 0 || each.isDefault === true)) return null;
  const all = offersWork ? (work.work ?? []) : [];
  return (
    <Section title="Your agents">
      <CardGrid min={CARD_WIDTH}>
        {orderedProfiles(kept).map((profile) => (
          <ProfileCard key={profile.id} profile={profile} work={currentWork(profile.id, all)} open={(url) => host.openPage(url)} />
        ))}
      </CardGrid>
    </Section>
  );
}

function ProfileCard({ profile, work, open }: { profile: ProfileView; work: ReturnType<typeof currentWork>; open: (url: string) => void }) {
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
            {profile.connections.map((connection) => (
              <span key={connection.id} className="flex items-center gap-2">
                <ConnectionPill connection={connection} />
                <span className="truncate text-meta text-muted">{connectionStatusLine(connection)}</span>
              </span>
            ))}
          </div>
          {work !== undefined && <WorkLine work={work} open={open} />}
          <details>
            <summary className="mx-focus cursor-pointer text-footnote font-medium text-muted select-none">How sure Memnox is</summary>
            <div className="pt-2">
              <CapabilityStrip levels={profile.levels} />
            </div>
          </details>
        </>
      ) : (
        <StatusWord tone="quiet">{NO_AGENT}</StatusWord>
      )}
    </Card>
  );
}
