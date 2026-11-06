import type { FoundSkillView, SkillView, SkillsHubView } from '@memnox/core/wire';
import { ArrowLeft, Check, Download, Plus, RefreshCw, Search, Sparkles, Trash2 } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { SkillOutcome } from '../../../core/application/skills';
import type { WidthClass } from '../../../core/domain/destinations';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { acceptedLine, assignedLine, categoryVersion, compatibilityLine, heldLine, permissionLines, removeLines, updatedLine } from '../../../core/domain/skills-lines';
import { BrandLogo } from '../../kit/logos';
import { MiddleCut } from '../../kit/MiddleCut';
import { KitButton, SearchField, Switch } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { AssignSkillDialog, ConfirmDialog, FoundSkillDialog, NewSkillDialog } from './SkillDialogs';
import { CardGrid, EmptyState, Panel, ReadFailed, Row, ScopeChip, Section, StatusWord } from '../widgets';
import { skillScope } from '../../../core/domain/scope-lines';
import { useShellChoices } from '../shell-choices';
import { inScope, NO_ORGANIZATION_ITEMS, ORGANIZATION_READ_ONLY, skillsShown } from '../../../core/domain/shell-lines';
import { MarkdownText } from '../../cards/MarkdownText';
import { SkillCareSection } from './SkillCareSection';
import { COLLAPSED_ROWS, countedLine, foundMatching, foundReach, groupedFound, homeOf, hubMatching, importAllTitle, importedLine, importingLine, noMatchDetail, noMatchTitle, queryWords, searchCountLine, shortPath } from '../../../core/domain/skill-search';

/** The narrowest a skill's card reads well at, as the Mac's grid sets it. */
const SKILL_CARD_WIDTH = 260;

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
  const [importing, setImporting] = useState<{ done: number; total: number } | undefined>(undefined);
  const [previewing, setPreviewing] = useState<FoundSkillView | undefined>(undefined);
  const { project, scope, connected } = useShellChoices();
  const picked = view.skills.find((skill) => skill.name === opened);
  if (picked !== undefined) return <SkillDetail parts={parts} view={view} skill={picked} width={width} back={() => open(undefined)} said={said} manage={() => manage(picked.name)} />;
  const scoped = inScope(skillsShown(view.skills, project), scope, (skill) => skill.scope === 'organization');
  const label = (agent: string) => labelOf(view, agent);
  const shown = hubMatching(scoped, query, label);
  const searching = queryWords(query) !== undefined;
  const found = foundMatching(view.found, query, label);
  const foundTotal = view.found.filter((each) => !each.imported).length;
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2.5">
        <div className="w-full max-w-[320px] min-w-[180px] flex-1">
          <SearchField value={query} placeholder="Search skills and what agents have" onChange={setQuery} />
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
      {searching && <p className="text-footnote text-muted">{searchCountLine({ shown: shown.length, total: scoped.length }, { shown: found.length, total: foundTotal })}</p>}
      {/* In the Mac's order: a search that leaves nothing, then an empty hub, then the cards. */}
      {shown.length === 0 && searching ? (
        <EmptyState icon={Search} title={noMatchTitle(query)} body={noMatchDetail(found.length)} />
      ) : view.skills.length === 0 ? (
        <EmptyState
          icon={Sparkles}
          title="No skills in the hub yet"
          body="Write one with New skill and give it to any agent, or import one an agent already has from Found on this computer below."
        />
      ) : (
        shown.length > 0 && (
          <CardGrid min={SKILL_CARD_WIDTH}>
            {shown.map((skill) => (
              <SkillCard key={`${skill.scope}/${skill.project ?? ''}/${skill.name}`} parts={parts} skill={skill} said={said} view={() => open(skill.name)} manage={() => manage(skill.name)} />
            ))}
          </CardGrid>
        )
      )}
      <Found parts={parts} view={view} found={found} total={foundTotal} searching={searching} importing={importing} setImporting={setImporting} said={said} preview={setPreviewing} />
      {creating && <NewSkillDialog parts={parts} close={() => setCreating(false)} said={said} />}
      {previewing !== undefined && <FoundSkillDialog parts={parts} found={previewing} label={label(previewing.agent)} importing={importing !== undefined} close={() => setPreviewing(undefined)} said={said} />}
    </div>
  );
}

function SkillCard({ parts, skill, said, view, manage }: { parts: SettingsParts; skill: SkillView; said: (outcome: SkillOutcome) => void; view: () => void; manage: () => void }) {
  const { skills } = parts;
  return (
    <article aria-label={skill.name} className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
      <div className="flex items-start gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="truncate text-headline font-semibold text-foreground">{skill.name}</span>
          <span className="truncate text-footnote text-muted">{categoryVersion(skill)}</span>
        </div>
        <Switch
          on={skill.enabled}
          label={skill.enabled ? `Turn ${skill.name} off for every agent` : `Hand ${skill.name} back to its agents`}
          disabled={skills.busy === skill.name}
          onChange={(on) => void (on ? skills.enable(skill.name) : skills.disable(skill.name)).then(said)}
        />
      </div>
      <p className="truncate text-footnote text-foreground">{skill.description}</p>
      {/* Whose it is, then how it stands, on one line as the Mac sets it. */}
      <div className="flex min-w-0 items-center gap-3 overflow-hidden text-footnote whitespace-nowrap text-muted">
        <ScopeChip scope={skillScope(skill)} />
        {skill.held !== undefined && <StatusWord tone="attention">Held</StatusWord>}
        {!skill.enabled && <StatusWord tone="quiet">Off</StatusWord>}
        <span className="truncate">{assignedLine(skill.agents.length)}</span>
        <span className="truncate">{updatedLine(skill.updatedAt, Date.now())}</span>
      </div>
      <div className="flex gap-2 border-t border-panel-edge pt-3">
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
    <div className="flex flex-col gap-6">
      <div className="flex items-center gap-2.5">
        <KitButton icon={ArrowLeft} onClick={back}>
          All skills
        </KitButton>
        <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{skill.name}</span>
        <span className="text-footnote text-muted">{categoryVersion(skill)}</span>
      </div>
      <div className={twoColumns ? 'grid grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] items-start gap-6' : 'flex flex-col gap-6'}>
        <div className="flex min-w-0 flex-col gap-6">
          <p className="text-body text-foreground">{skill.description}</p>
          <Section title="Instructions">
            {/* Drawn the way its agent reads it, headings, lists and code, as the Mac's SkillMarkdown draws a SKILL.md. */}
            <div className="rounded-xl border border-panel-edge bg-card p-5">
              <MarkdownText source={skill.instructions} tone="window" onLink={(href) => parts.host.openPage(href)} />
            </div>
          </Section>
          <SkillCareSection parts={parts} skill={skill} said={said} />
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
                  caption={acceptedLine(version.acceptedAt)}
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

/** Removing only narrows, so it is done at once once the console's confirm is answered, since its kept versions go with it. */
function RemoveSkill({ parts, skill, back, said }: { parts: SettingsParts; skill: SkillView; back: () => void; said: (outcome: SkillOutcome) => void }) {
  const { skills } = parts;
  const [confirming, setConfirming] = useState(false);
  const lines = removeLines(skill.name);
  const remove = () => {
    setConfirming(false);
    void skills.remove(skill.name).then((outcome) => {
      said(outcome);
      if (outcome.kind !== 'failed') back();
    });
  };
  return (
    <Section title="Remove">
      <p className="text-footnote text-muted">{lines.lead}</p>
      <div>
        <KitButton icon={Trash2} disabled={skills.busy === skill.name} onClick={() => setConfirming(true)}>
          Remove skill
        </KitButton>
      </div>
      {confirming && <ConfirmDialog icon={Trash2} title={lines.title} message={lines.message} confirm={lines.confirm} cancel={() => setConfirming(false)} act={remove} />}
    </Section>
  );
}

function labelOf(view: SkillsHubView, agent: string): string {
  return view.agents.find((each) => each.agent === agent)?.label ?? agentLabel(agent);
}

export function Facts({ facts, mono = false }: { facts: readonly (readonly [string, ReactNode])[]; mono?: boolean }) {
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

/**
 * Skills an agent already had in its own folder, as the Mac's `SkillsFound`: grouped by agent and narrowed by the same
 * search as the hub, offered to bring in one at a time or all at once, and never touched until then. A row, or its
 * View, opens the agent's own SKILL.md drawn in the window.
 */
function Found({
  parts,
  view,
  found,
  total,
  searching,
  importing,
  setImporting,
  said,
  preview,
}: {
  parts: SettingsParts;
  view: SkillsHubView;
  found: readonly FoundSkillView[];
  total: number;
  searching: boolean;
  importing: { done: number; total: number } | undefined;
  setImporting: (progress: { done: number; total: number } | undefined) => void;
  said: (outcome: SkillOutcome) => void;
  preview: (found: FoundSkillView) => void;
}) {
  const { skills } = parts;
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const label = (agent: string) => labelOf(view, agent);
  if (total === 0) return null;
  const importAll = async () => {
    if (importing !== undefined || found.length === 0) return;
    setImporting({ done: 0, total: found.length });
    const results = await skills.importAll(found, (done) => setImporting({ done, total: found.length }));
    setImporting(undefined);
    said({ kind: 'done', note: importedLine(results) });
  };
  const toggle = (agent: string, open: boolean) =>
    setExpanded((now) => {
      const next = new Set(now);
      if (open) next.add(agent);
      else next.delete(agent);
      return next;
    });
  return (
    <Section
      title={`Found on this computer · ${countedLine(found.length, total, searching)}`}
      trailing={
        importing !== undefined ? (
          <span className="flex items-center gap-2 text-footnote text-muted tabular-nums">
            <progress className="w-[120px] accent-primary" value={importing.done} max={Math.max(importing.total, 1)} />
            {importingLine(importing.done, importing.total)}
          </span>
        ) : found.length > 0 ? (
          <KitButton kind="primary" icon={Download} disabled={skills.busy !== undefined} onClick={() => void importAll()} title="Imports each one in turn; any that reaches further than reading its folder waits for your signature on the island">
            {importAllTitle(found.length, searching)}
          </KitButton>
        ) : undefined
      }
    >
      {found.length === 0 ? (
        <p className="text-footnote text-muted">Nothing an agent already has matches that search.</p>
      ) : (
        groupedFound(found, label).map((group) => {
          const open = searching || expanded.has(group.agent);
          const rows = open ? group.skills : group.skills.slice(0, COLLAPSED_ROWS);
          const hidden = group.skills.length - rows.length;
          return (
            <div key={group.agent} className="flex flex-col gap-2">
              <div className="flex items-center gap-2.5">
                <BrandLogo agent={group.agent} name={group.label} size={20} />
                <span className="text-body-sm font-semibold text-foreground">{group.label}</span>
                <span className="text-footnote text-muted tabular-nums">{group.skills.length}</span>
              </div>
              <Panel>
                {rows.map((each, index) => (
                  <FoundRow key={each.id} found={each} divided={index > 0} busy={skills.busy !== undefined || importing !== undefined} open={() => preview(each)} bring={() => void skills.importFound(each.id, each.name).then(said)} />
                ))}
                {(hidden > 0 || (expanded.has(group.agent) && !searching && group.skills.length > COLLAPSED_ROWS)) && (
                  <button type="button" className="mx-focus w-full cursor-pointer border-t border-panel-edge px-4 py-3 text-left text-body-sm font-medium text-muted hover:bg-hover hover:text-foreground" onClick={() => toggle(group.agent, hidden > 0)}>
                    {hidden > 0 ? `Show all ${group.skills.length}` : 'Show fewer'}
                  </button>
                )}
              </Panel>
            </div>
          );
        })
      )}
      <p className="text-footnote text-muted">Importing a skill keeps it once in the hub, with its files, so it can be given to any agent in that agent’s own format.</p>
    </Section>
  );
}

/** One skill an agent has: its name, its folder from ~ cut in the middle so both ends read, what it uses, View and Import. */
function FoundRow({ found, divided, busy, open, bring }: { found: FoundSkillView; divided: boolean; busy: boolean; open: () => void; bring: () => void }) {
  const where = shortPath(found.path, homeOf(found.path));
  const reach = foundReach(found);
  return (
    <div className={`flex items-center gap-3 px-4 py-3 ${divided ? 'border-t border-panel-edge' : ''}`}>
      <button type="button" className="mx-focus flex min-w-0 flex-1 cursor-pointer flex-col gap-0.5 text-left" title={found.path} aria-label={`Read ${found.name}`} onClick={open}>
        <span className="truncate text-body-sm font-medium text-foreground">{found.name}</span>
        <span className="flex min-w-0 gap-1.5 text-meta text-muted">
          <span className="block min-w-0 flex-1 overflow-hidden">
            <MiddleCut text={where} className="font-mono text-label" />
          </span>
          {reach !== undefined && <span className="shrink-0 truncate">{`· ${reach}`}</span>}
        </span>
      </button>
      <KitButton onClick={open}>View</KitButton>
      <KitButton disabled={busy} onClick={bring}>
        Import
      </KitButton>
    </div>
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
