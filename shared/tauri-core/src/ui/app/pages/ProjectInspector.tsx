import type { ProjectGrantView, ProjectOrganizationView, ProjectView } from '@memnox/core/wire';
import { Building2, FileText, Play, Save } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { ProjectOutcome } from '../../../core/application/projects';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import {
  draftOf,
  FROM_ORGANIZATION,
  grantLine,
  instructionWord,
  organizationMemoryLine,
  organizationRulesLine,
  projectRules,
  projectStanding,
  projectTiles,
  questionsLine,
  readersLine,
  rulesLine,
  sharedBy,
} from '../../../core/domain/project-lines';
import { ago } from '../../../core/domain/session-text';
import { EFFECT_WORDS, effectTone, isEffect } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { EmptyState, Panel, ReadFailed, Row, Section, StatTile, StatusWord } from '../widgets';

const TABS = [
  { id: 'overview', title: 'Overview' },
  { id: 'agents', title: 'Agents' },
  { id: 'skills', title: 'Skills' },
  { id: 'tools', title: 'Tools' },
  { id: 'policies', title: 'Policies' },
] as const;

type ProjectTab = (typeof TABS)[number]['id'];

/** What a press said, the part waiting on the island named with the key that signs it. */
export function projectNote(outcome: ProjectOutcome, keyTitle: string): string {
  if (outcome.kind === 'failed') return outcome.why;
  if (outcome.kind === 'proposed') return `${outcome.note} Its servers, skills and rules wait for you on the island: confirm them with ${keyTitle}.`;
  return outcome.note;
}

/** One project's details, a tab each for what it gives its agents and the rules that hold in it. */
export function ProjectInspector({ parts, project, said }: { parts: SettingsParts; project: ProjectView; said: (note: string) => void }) {
  const [tab, setTab] = useState<ProjectTab>('overview');
  return (
    <div className="flex flex-col gap-4">
      <div role="tablist" className="flex gap-1 overflow-x-auto border-b border-panel-edge [scrollbar-width:none]">
        {TABS.map((each) => (
          <button
            key={each.id}
            type="button"
            role="tab"
            aria-selected={tab === each.id}
            onClick={() => setTab(each.id)}
            className={`mx-focus relative cursor-pointer px-2 py-2 text-footnote whitespace-nowrap ${tab === each.id ? 'font-medium text-foreground' : 'text-muted hover:text-foreground'}`}
          >
            {each.title}
            {tab === each.id && <span aria-hidden className="absolute inset-x-1.5 -bottom-px h-0.5 rounded-full bg-primary" />}
          </button>
        ))}
      </div>
      {tab === 'overview' && <Overview parts={parts} project={project} said={said} />}
      {tab === 'agents' && <AgentsHere parts={parts} project={project} />}
      {tab === 'skills' && <Grants project={project} grants={project.skills} empty="This project names no skills." />}
      {tab === 'tools' && <Grants project={project} grants={project.servers} empty="This project names no MCP servers." />}
      {tab === 'policies' && <PoliciesHere parts={parts} project={project} />}
    </div>
  );
}

function Overview({ parts, project, said }: { parts: SettingsParts; project: ProjectView; said: (note: string) => void }) {
  const { projects } = parts;
  useObserved(projects);
  const standing = projectStanding(project);
  const busy = projects.busy === project.id || projects.busy === project.path;
  const organization = sharedBy(project);
  return (
    <div className="flex flex-col gap-5">
      <div className="flex items-center justify-between gap-2">
        {organization === undefined ? <StatusWord tone={standing.tone}>{standing.word}</StatusWord> : <OrganizationBadge />}
        <span className="truncate font-mono text-micro text-muted" title={project.path}>
          {project.path}
        </span>
      </div>
      {project.problems !== undefined && project.problems.length > 0 && (
        <ul role="alert" className="flex flex-col gap-1 rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-destructive">
          {project.problems.map((problem) => (
            <li key={problem}>{problem}</li>
          ))}
        </ul>
      )}
      <div className="grid grid-cols-2 gap-2.5">
        {projectTiles(project).map((tile) => (
          <StatTile key={tile.label} value={tile.value} label={tile.label} />
        ))}
      </div>
      {organization !== undefined && <OrganizationPanel organization={organization} />}
      <p className="text-footnote text-muted">{rulesLine(project.rules)}</p>
      {organization !== undefined ? (
        <p className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-muted">{organization.editedIn}</p>
      ) : (
        <EditControls parts={parts} project={project} busy={busy} said={said} />
      )}
      <Section title="Instructions">
        {project.instructions.length === 0 ? (
          <p className="text-footnote text-muted">No instruction file, so its agents get none from this project.</p>
        ) : (
          <Panel>
            {project.instructions.map((each) => (
              <Row key={each.path} leading={<FileText size={15} className="text-muted" aria-hidden />} title={<span className="font-mono">{each.path}</span>} caption={`${instructionWord(each)} · ${readersLine(each)}`} />
            ))}
          </Panel>
        )}
      </Section>
      <Section title="Open missions">
        {project.openMissions.length === 0 ? (
          <p className="text-footnote text-muted">No mission is open here.</p>
        ) : (
          <Panel>
            {project.openMissions.map((mission) => (
              <Row key={mission.id} title={mission.statement} caption={`Started ${ago(mission.startedAt, Date.now()) ?? 'a while ago'}`} />
            ))}
          </Panel>
        )}
        <p className="text-footnote text-muted">{questionsLine(project.openQuestions)}</p>
      </Section>
      <p className="text-footnote text-muted">
        {`${project.sessions.total} sessions, ${project.sessions.ended} ended.`}
        {project.appliedAt === undefined ? ' Never applied on this computer.' : ` Applied ${ago(project.appliedAt, Date.now()) ?? 'a while ago'}.`}
      </p>
    </div>
  );
}

/** Apply or Save as project, on the person's own project only; the organization's is changed in Memnox Cloud. */
function EditControls({ parts, project, busy, said }: { parts: SettingsParts; project: ProjectView; busy: boolean; said: (note: string) => void }) {
  const { projects, words } = parts;
  return (
    <>
      <div className="flex flex-wrap gap-2">
        {project.declared ? (
          <KitButton kind="primary" icon={Play} disabled={busy} onClick={() => void projects.apply(project.id).then((outcome) => said(projectNote(outcome, words.keyTitle)))}>
            {busy ? 'Applying' : 'Apply'}
          </KitButton>
        ) : (
          <KitButton kind="primary" icon={Save} disabled={busy} onClick={() => void projects.put(project.path, draftOf(project)).then((outcome) => said(projectNote(outcome, words.keyTitle)))}>
            {busy ? 'Saving' : 'Save as project'}
          </KitButton>
        )}
      </div>
      <p className="text-footnote text-muted">
        {project.declared
          ? 'Apply hands its instructions to its agents at once. Servers, skills and rules that widen an agent wait for your signature.'
          : 'Found from the sessions here. Save as project writes .memnox/project.toml with what it shows now, applying nothing until you ask.'}
      </p>
    </>
  );
}

/** The badge a project the organization shares carries in place of its standing. */
export function OrganizationBadge() {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-panel-edge px-2 py-0.5 text-footnote font-medium text-muted">
      <Building2 size={12} aria-hidden />
      {FROM_ORGANIZATION}
    </span>
  );
}

/** What the organization hands this project, read only: servers, skills, its rule pack, memory, and what was left out. */
function OrganizationPanel({ organization }: { organization: ProjectOrganizationView }) {
  const names = (list: readonly string[]) => (list.length === 0 ? 'None' : list.join(', '));
  return (
    <Section title="From your organization">
      {organization.description !== undefined && <p className="text-footnote text-muted">{organization.description}</p>}
      <Panel>
        <Row title="Repository" caption={<span className="font-mono">{organization.repository}</span>} />
        <Row title="MCP servers" caption={names(organization.servers)} />
        <Row title="Skills" caption={names(organization.skills)} />
        <Row title="Rule pack" caption={organizationRulesLine(organization)} />
        <Row title="Memory" caption={organizationMemoryLine(organization.memory)} />
      </Panel>
      {organization.skipped.length > 0 && (
        <ul className="flex flex-col gap-1 text-footnote text-muted">
          {organization.skipped.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      )}
    </Section>
  );
}

/** The agents the project names, then any seen working in it that it does not name. */
function AgentsHere({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  const { agents } = parts;
  useObserved(agents);
  useEffect(() => void agents.refresh(), []);
  const seenOnly = project.agentsSeen.filter((kind) => !project.agents.includes(kind));
  const nameOf = (kind: string) => agents.agents?.find((each) => each.kind === kind)?.name ?? agentLabel(kind);
  if (project.agents.length === 0 && seenOnly.length === 0) return <p className="text-footnote text-muted">No agent has worked here yet, and the project names none.</p>;
  return (
    <div className="flex flex-col gap-4">
      {project.agents.length > 0 && (
        <Section title="Given this project">
          <Panel>
            {project.agents.map((kind) => (
              <Row
                key={kind}
                leading={<BrandLogo agent={kind} name={nameOf(kind)} size={24} />}
                title={nameOf(kind)}
                caption={`${project.skills.filter((each) => each.agents.includes(kind)).length} skills, ${project.servers.filter((each) => each.agents.includes(kind)).length} servers`}
                trailing={project.agentsSeen.includes(kind) ? <StatusWord tone="good">Worked here</StatusWord> : <StatusWord tone="quiet">Not seen here</StatusWord>}
              />
            ))}
          </Panel>
        </Section>
      )}
      {seenOnly.length > 0 && (
        <Section title="Seen here, not named">
          <Panel>
            {seenOnly.map((kind) => (
              <Row key={kind} leading={<BrandLogo agent={kind} name={nameOf(kind)} size={24} />} title={nameOf(kind)} caption="Ran a session here, and the project gives it nothing" />
            ))}
          </Panel>
        </Section>
      )}
    </div>
  );
}

/** A skill or a server the project names, with who has it now. */
function Grants({ project, grants, empty }: { project: ProjectView; grants: readonly ProjectGrantView[]; empty: string }) {
  if (grants.length === 0) return <p className="text-footnote text-muted">{empty}</p>;
  return (
    <Panel>
      {grants.map((grant) => (
        <Row
          key={grant.name}
          title={grant.name}
          caption={grantLine(grant, project.agents.length)}
          trailing={
            grant.inHub ? (
              <span className="flex -space-x-1.5">
                {grant.agents.map((kind) => (
                  <BrandLogo key={kind} agent={kind} name={agentLabel(kind)} size={20} className="ring-2 ring-card" />
                ))}
              </span>
            ) : (
              <StatusWord tone="attention">Not in the hub</StatusWord>
            )
          }
        />
      ))}
    </Panel>
  );
}

/** The rules that reach into this project; those holding everywhere are counted, since they are on Policies. */
function PoliciesHere({ parts, project }: { parts: SettingsParts; project: ProjectView }) {
  const { studio } = parts;
  useObserved(studio);
  useEffect(() => void studio.refresh(), []);
  const view = studio.rules;
  if (view === undefined) return studio.unreadable ? <ReadFailed what="the rules" retry={() => void studio.refresh()} /> : null;
  const { here, everywhere } = projectRules(view.rules, project);
  return (
    <div className="flex flex-col gap-3">
      {here.length === 0 ? (
        <EmptyState icon={FileText} title="No rule of its own" body="No rule names this folder or comes from its rule file, so the rules of this computer decide here." />
      ) : (
        <Panel>
          {here.map((rule) => (
            <Row key={rule.name} title={rule.sentence} caption={rule.reason ?? rule.file ?? rule.name} trailing={<StatusWord tone={effectTone(rule.effect)}>{isEffect(rule.effect) ? EFFECT_WORDS[rule.effect].title : rule.effect}</StatusWord>} />
          ))}
        </Panel>
      )}
      <p className="text-footnote text-muted">{everywhere === 1 ? '1 rule of this computer holds here too.' : `${everywhere} rules of this computer hold here too.`}</p>
    </div>
  );
}
