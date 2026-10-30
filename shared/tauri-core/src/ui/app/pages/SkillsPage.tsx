import type { SkillView, SkillsHubView } from '@memnox/core/wire';
import { ArrowLeft, Check, Plus, RefreshCw, Sparkles, Trash2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { SkillOutcome } from '../../../core/application/skills';
import type { WidthClass } from '../../../core/domain/destinations';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { assignedLine, categoryVersion, compatibilityLine, heldLine, permissionLines, updatedLine } from '../../../core/domain/skills-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton, SearchField, Switch } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { AssignSkillDialog, NewSkillDialog } from './SkillDialogs';
import { CardGrid, EmptyState, Panel, ReadFailed, Row, ScopeChip, Section, StatusWord } from '../widgets';
import { skillScope } from '../../../core/domain/scope-lines';
import { useShellChoices } from '../shell-choices';
import { inScope, NO_ORGANIZATION_ITEMS, ORGANIZATION_READ_ONLY, skillsShown } from '../../../core/domain/shell-lines';

/**
 * The Skills Hub: skills kept once and written into each agent's own format. Giving a skill to an agent
 * and accepting a folder that reaches further wait for a signature on the island; taking away is at once.
 */
export function SkillsPage({ parts, tab, width }: { parts: SettingsParts; tab: 'skills' | 'assigned'; width: WidthClass }) {
  const { skills } = parts;
  useObserved(skills);
  useEffect(() => {
    void skills.refresh();
  }, []);
  // A signature on the island changes what the hub holds, so it is read again.
  useEffect(() => parts.host.onHomeStale?.(() => void skills.refresh()), []);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [assigning, setAssigning] = useState<string | undefined>(undefined);
  const said = (outcome: SkillOutcome) => setNote(noteOf(outcome, parts.words.keyTitle));

  const view = skills.hub;
  if (view === undefined) return skills.unreadable ? <ReadFailed what="the Skills Hub" retry={() => void skills.refresh()} /> : null;
  const assigned = view.skills.find((skill) => skill.name === assigning);
  return (
    <>
      {note !== undefined && (
        <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {note}
        </p>
      )}
      {tab === 'assigned' ? <AssignedGrid view={view} manage={setAssigning} /> : <MySkills parts={parts} view={view} width={width} said={said} manage={setAssigning} />}
      {assigned !== undefined && <AssignSkillDialog parts={parts} view={view} skill={assigned} close={() => setAssigning(undefined)} said={setNote} />}
    </>
  );
}

function noteOf(outcome: SkillOutcome, keyTitle: string): string {
  if (outcome.kind === 'proposed') return `Waiting for you on the island: confirm it with ${keyTitle} and the runtime writes it.`;
  if (outcome.kind === 'failed') return outcome.why;
  return outcome.note;
}

function MySkills({ parts, view, width, said, manage }: { parts: SettingsParts; view: SkillsHubView; width: WidthClass; said: (outcome: SkillOutcome) => void; manage: (name: string) => void }) {
  const { skills } = parts;
  const [query, setQuery] = useState('');
  const [opened, open] = useState<string | undefined>(undefined);
  const [creating, setCreating] = useState(false);
  const { project, scope, connected } = useShellChoices();
  const picked = view.skills.find((skill) => skill.name === opened);
  if (picked !== undefined) return <SkillDetail parts={parts} view={view} skill={picked} width={width} back={() => open(undefined)} said={said} manage={() => manage(picked.name)} />;
  const words = query.trim().toLowerCase();
  const scoped = inScope(skillsShown(view.skills, project), scope, (skill) => skill.scope === 'organization');
  const shown = scoped.filter((skill) => words === '' || `${skill.name} ${skill.description} ${skill.category ?? ''}`.toLowerCase().includes(words));
  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center gap-2.5">
        <div className="w-full max-w-[320px] min-w-[180px] flex-1">
          <SearchField value={query} placeholder="Search skills" onChange={setQuery} />
        </div>
        <span className="flex-1" />
        <KitButton icon={RefreshCw} disabled={skills.busy === 'sync'} onClick={() => void skills.sync().then(said)} title="Write what the hub gives each agent into its folder again">
          Sync
        </KitButton>
        <KitButton kind="primary" icon={Plus} onClick={() => setCreating(true)}>
          New skill
        </KitButton>
      </div>
      {connected && scope === 'organization' && <p className="text-footnote text-muted">{scoped.length === 0 ? NO_ORGANIZATION_ITEMS : ORGANIZATION_READ_ONLY}</p>}
      {scope === 'personal' && view.skills.length === 0 ? (
        <EmptyState
          icon={Sparkles}
          title="No skills in the hub yet"
          body="Write a skill once and give it to any agent, or bring in one an agent already has from Found on this computer below."
          action={<KitButton kind="primary" icon={Plus} onClick={() => setCreating(true)}>New skill</KitButton>}
        />
      ) : (
        <CardGrid>
          {shown.map((skill) => (
            <SkillCard key={`${skill.scope}/${skill.project ?? ''}/${skill.name}`} parts={parts} skill={skill} said={said} view={() => open(skill.name)} manage={() => manage(skill.name)} />
          ))}
        </CardGrid>
      )}
      <Found parts={parts} view={view} said={said} />
      {creating && <NewSkillDialog parts={parts} close={() => setCreating(false)} said={said} />}
    </div>
  );
}

function SkillCard({ parts, skill, said, view, manage }: { parts: SettingsParts; skill: SkillView; said: (outcome: SkillOutcome) => void; view: () => void; manage: () => void }) {
  const { skills } = parts;
  return (
    <article className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
      <div className="flex items-start gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="truncate text-headline font-semibold text-foreground">{skill.name}</span>
          <span className="truncate text-footnote text-muted">{categoryVersion(skill)}</span>
        </div>
        <ScopeChip scope={skillScope(skill)} />
        <Switch
          on={skill.enabled}
          label={skill.enabled ? `Turn ${skill.name} off for every agent` : `Hand ${skill.name} back to its agents`}
          disabled={skills.busy === skill.name}
          onChange={(on) => void (on ? skills.enable(skill.name) : skills.disable(skill.name)).then(said)}
        />
      </div>
      <p className="truncate text-footnote text-foreground">{skill.description}</p>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        {skill.held !== undefined && <StatusWord tone="attention">Held</StatusWord>}
        {!skill.enabled && <StatusWord tone="quiet">Off</StatusWord>}
        <span className="text-footnote text-muted">{assignedLine(skill.agents.length)}</span>
        <span className="text-footnote text-muted">{updatedLine(skill.updatedAt, Date.now())}</span>
      </div>
      <div className="flex flex-wrap gap-2 border-t border-panel-edge pt-3">
        <KitButton onClick={view}>View skill</KitButton>
        <KitButton onClick={manage}>Manage agents</KitButton>
      </div>
    </article>
  );
}

/** One skill on the whole page: what it is on the left, where it goes and what it reaches on the right. */
function SkillDetail({
  parts,
  view,
  skill,
  width,
  back,
  said,
  manage,
}: {
  parts: SettingsParts;
  view: SkillsHubView;
  skill: SkillView;
  width: WidthClass;
  back: () => void;
  said: (outcome: SkillOutcome) => void;
  manage: () => void;
}) {
  const { skills } = parts;
  const twoColumns = width === 'wide' || width === 'medium';
  const reach = permissionLines(skill);
  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center gap-2.5">
        <KitButton icon={ArrowLeft} onClick={back}>
          All skills
        </KitButton>
        <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{skill.name}</span>
        <span className="text-footnote text-muted">{categoryVersion(skill)}</span>
      </div>
      <div className={twoColumns ? 'grid grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] gap-6' : 'flex flex-col gap-6'}>
        <div className="flex min-w-0 flex-col gap-6">
          <p className="text-body text-foreground">{skill.description}</p>
          <Section title="Instructions">
            <pre className="max-h-[420px] overflow-auto rounded-xl border border-panel-edge bg-card p-3.5 font-mono text-footnote whitespace-pre-wrap text-foreground">{skill.instructions}</pre>
          </Section>
          <Facts
            facts={[
              ['Version', skill.version],
              ['Publisher', skill.publisher ?? 'You'],
              ['Kept', skill.scope === 'project' ? `With ${skill.project ?? 'its repository'}` : 'In your Memnox folder'],
            ]}
          />
          {skill.files.length > 0 && <ListSection title="Files" items={skill.files} mono />}
          {skill.dependencies.length > 0 && <ListSection title="Builds on" items={skill.dependencies} />}
          <Section title="Versions">
            <Panel>
              {[...skill.versions].reverse().map((version) => (
                <Row
                  key={version.version}
                  title={`v${version.version}`}
                  caption={version.acceptedAt === undefined ? 'Never accepted' : `Accepted ${version.acceptedAt.slice(0, 10)}`}
                  trailing={
                    version.current ? (
                      <StatusWord tone="good">In use</StatusWord>
                    ) : skill.scope === 'personal' && version.acceptedAt !== undefined ? (
                      <KitButton disabled={skills.busy === skill.name} onClick={() => void skills.rollback(skill.name, version.version).then(said)}>
                        Roll back
                      </KitButton>
                    ) : undefined
                  }
                />
              ))}
            </Panel>
            <p className="text-footnote text-muted">{`Rolling back to a version that reaches further waits for your signature with ${parts.words.keyTitle}.`}</p>
          </Section>
        </div>
        <div className="flex min-w-0 flex-col gap-6">
          {skill.held !== undefined && (
            <div role="alert" className="flex flex-col gap-2.5 rounded-xl border border-warm/40 bg-card p-3.5">
              <StatusWord tone="attention">Held</StatusWord>
              <p className="text-footnote text-foreground">{heldLine(skill.held)}</p>
              <div>
                <KitButton kind="primary" icon={Check} disabled={skills.busy === skill.name} onClick={() => void skills.accept(skill.name).then(said)}>
                  Accept
                </KitButton>
              </div>
            </div>
          )}
          {skill.problems !== undefined && skill.problems.length > 0 && <ListSection title="Why its folder would not read" items={skill.problems} />}
          <Section title="Assigned agents" trailing={<KitButton onClick={manage}>Manage agents</KitButton>}>
            {skill.assignments.length === 0 ? (
              <p className="text-footnote text-muted">Given to no agent yet.</p>
            ) : (
              <Panel>
                {skill.assignments.map((assignment) => (
                  <Row
                    key={`${assignment.agent}/${assignment.project ?? ''}`}
                    leading={<BrandLogo agent={assignment.agent} name={labelOf(view, assignment.agent)} size={22} />}
                    title={labelOf(view, assignment.agent)}
                    caption={assignment.project === undefined ? 'In its home folder' : `In ${assignment.project}`}
                  />
                ))}
              </Panel>
            )}
          </Section>
          <Facts facts={[['Available', skill.scope === 'project' ? `Only in ${skill.project ?? 'its repository'}` : 'In every workspace on this computer']]} />
          <Section title="Tools and permissions">
            {reach.length === 0 ? (
              <p className="text-footnote text-muted">It asks for nothing beyond reading its own folder.</p>
            ) : (
              <Facts facts={reach.map((each) => [each.title, each.items.join(', ')])} />
            )}
          </Section>
          <Section title="Compatibility">
            <Panel>
              {skill.compatibility.map((each) => (
                <div key={each.agent} className="flex flex-col gap-1 px-3.5 py-2.5">
                  <div className="flex items-center gap-2.5">
                    <BrandLogo agent={each.agent} name={each.label} size={20} />
                    <span className="flex-1 text-body text-foreground">{each.label}</span>
                    <StatusWord tone={!each.supported ? 'bad' : each.loses.length === 0 ? 'good' : 'attention'}>{compatibilityLine(each)}</StatusWord>
                  </div>
                  {each.loses.map((loss) => (
                    <span key={loss} className="pl-[30px] text-footnote text-muted">
                      {loss}
                    </span>
                  ))}
                </div>
              ))}
            </Panel>
          </Section>
          <Facts facts={[['Digest', skill.digest]]} mono />
          {skill.scope === 'personal' && <RemoveSkill parts={parts} skill={skill} back={back} said={said} />}
        </div>
      </div>
    </div>
  );
}

/** Removing only narrows, so it is done at once; a second press confirms, since its kept versions go with it. */
function RemoveSkill({ parts, skill, back, said }: { parts: SettingsParts; skill: SkillView; back: () => void; said: (outcome: SkillOutcome) => void }) {
  const { skills } = parts;
  const [confirming, setConfirming] = useState(false);
  const remove = () =>
    void skills.remove(skill.name).then((outcome) => {
      said(outcome);
      if (outcome.kind !== 'failed') back();
    });
  return (
    <Section title="Remove">
      <p className="text-footnote text-muted">{`Takes ${skill.name} out of the hub and out of every agent it was given to, with every version kept of it.`}</p>
      <div className="flex gap-2">
        {confirming ? (
          <>
            <KitButton kind="primary" icon={Trash2} disabled={skills.busy === skill.name} onClick={remove}>
              {`Remove ${skill.name}`}
            </KitButton>
            <KitButton onClick={() => setConfirming(false)}>Cancel</KitButton>
          </>
        ) : (
          <KitButton icon={Trash2} onClick={() => setConfirming(true)}>
            Remove skill
          </KitButton>
        )}
      </div>
    </Section>
  );
}

function labelOf(view: SkillsHubView, agent: string): string {
  return view.agents.find((each) => each.agent === agent)?.label ?? agentLabel(agent);
}

export function Facts({ facts, mono = false }: { facts: readonly (readonly [string, string])[]; mono?: boolean }) {
  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-footnote">
      {facts.map(([name, value]) => (
        <div key={name} className="contents">
          <dt className="text-muted">{name}</dt>
          <dd className={`min-w-0 break-words text-foreground ${mono ? 'font-mono text-micro break-all' : ''}`}>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function ListSection({ title, items, mono = false }: { title: string; items: readonly string[]; mono?: boolean }) {
  return (
    <Section title={title}>
      <Panel>
        {items.map((item) => (
          <Row key={item} title={mono ? <span className="font-mono">{item}</span> : item} />
        ))}
      </Panel>
    </Section>
  );
}

/** Skills an agent already had in its own folder, offered to bring in and never touched until then. */
function Found({ parts, view, said }: { parts: SettingsParts; view: SkillsHubView; said: (outcome: SkillOutcome) => void }) {
  const { skills } = parts;
  const waiting = view.found.filter((each) => !each.imported);
  if (waiting.length === 0) return null;
  return (
    <Section title={`Found on this computer · ${waiting.length}`}>
      <Panel>
        {waiting.map((found) => (
          <Row
            key={found.id}
            leading={<BrandLogo agent={found.agent} name={labelOf(view, found.agent)} size={22} />}
            title={found.name}
            caption={`${labelOf(view, found.agent)} · ${found.grant} · ${found.path}`}
            trailing={
              <KitButton disabled={skills.busy === found.name} onClick={() => void skills.importFound(found.id, found.name).then(said)}>
                Import
              </KitButton>
            }
          />
        ))}
      </Panel>
      <p className="text-footnote text-muted">Importing a skill keeps it once in the hub, with its files, so it can be given to any agent in that agent’s own format.</p>
    </Section>
  );
}

/** Skills down, agents across: who has what at a glance, changed through Manage agents. */
function AssignedGrid({ view, manage }: { view: SkillsHubView; manage: (name: string) => void }) {
  const agents = view.agents.filter((each) => each.installed);
  if (view.skills.length === 0 || agents.length === 0) {
    return <EmptyState icon={Sparkles} title="Nothing assigned yet" body="Once the hub holds a skill and an agent that takes skills is installed, who has what shows here." />;
  }
  return (
    <div className="overflow-x-auto rounded-xl border border-panel-edge">
      <table className="w-full border-collapse text-body">
        <thead>
          <tr className="bg-card">
            <th scope="col" className="px-3.5 py-2.5 text-left text-footnote font-semibold text-muted">Skill</th>
            {agents.map((agent) => (
              <th key={agent.agent} scope="col" className="px-3 py-2.5 text-footnote font-semibold whitespace-nowrap text-muted">
                <span className="inline-flex items-center gap-1.5">
                  <BrandLogo agent={agent.agent} name={agent.label} size={18} />
                  {agent.label}
                </span>
              </th>
            ))}
            <th scope="col" className="px-3 py-2.5" aria-label="Change" />
          </tr>
        </thead>
        <tbody>
          {view.skills.map((skill) => (
            <tr key={`${skill.scope}/${skill.project ?? ''}/${skill.name}`} className="border-t border-panel-edge">
              <th scope="row" className="px-3.5 py-2.5 text-left font-medium whitespace-nowrap text-foreground">
                {skill.name}
                {!skill.enabled && <span className="pl-2 text-footnote font-normal text-muted">Off</span>}
              </th>
              {agents.map((agent) => {
                const on = skill.agents.includes(agent.agent);
                return (
                  <td key={agent.agent} className="px-3 py-2.5 text-center">
                    {on ? <Check size={15} className="inline text-success" aria-label={`${skill.name} for ${agent.label}`} /> : <span className="sr-only">{`Not given to ${agent.label}`}</span>}
                  </td>
                );
              })}
              <td className="px-3 py-2.5 text-right">
                <KitButton onClick={() => manage(skill.name)}>Manage agents</KitButton>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
