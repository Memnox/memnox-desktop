import type { ProfileView } from '@memnox/core/wire';
import { Briefcase, Copy, Link2, Pencil, Play, Plus, Trash2 } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import type { ProfileOutcome } from '../../../core/application/profiles';
import type { ProfileTemplate } from '../../../core/domain/agent-wire';
import { connectionAgent, NO_AGENT, orderedProfiles, purposeLine, responsibleLine, shownConnections } from '../../../core/domain/agent-work-lines';
import { connectionStatusLine } from '../../../core/domain/capability-level-lines';
import {
  applyWhereLine,
  choiceNames,
  JobsLines,
  jobFormFor,
  packChangeLine,
  profileContents,
  profileDraftFrom,
  profileFormOf,
  ProfilesLines,
  type ProfileForm,
} from '../../../core/domain/profile-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CapabilityStrip, ConnectionPill } from '../capability-strip';
import { BrandLogo, Button, Card, CardGrid, Checkbox, Dialog, EmptyState, Field, Input, Note, ReadFailed, Section, Select, StatusWord, Textarea } from '../../kit';
import { AgentProfileCard } from './AgentProfileCards';

/** As the Mac's profile grid sets it. */
const CARD_WIDTH = 280;
const CARD_LOGO = 30;

/** Which sheet is open: a new job, an edit, a job given to an agent's default, or a template being copied. */
type Sheet = { kind: 'new' } | { kind: 'edit'; profile: ProfileView } | { kind: 'job-for'; profile: ProfileView } | { kind: 'template'; template: ProfileTemplate };

/**
 * The job editor under AI agents, as the Mac's `ProfilesDestination`: each job with who answers for it and the agents
 * it works through, an agent's default offered a job, and the templates, which are jobs with no agent behind them.
 * Keeping or binding one grants nothing; applying one raises a proposal for each piece, each signed on the island.
 */
export function JobsTab({ parts }: { parts: SettingsParts }) {
  const { profiles, skills, hub, studio, agents, words } = parts;
  useObserved(profiles, agents);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [sheet, setSheet] = useState<Sheet | undefined>(undefined);
  useEffect(() => {
    void profiles.refresh();
    void profiles.readTemplates();
    // The hubs and packs are what a job is made from, and the agents what it is bound and applied to.
    void skills.refresh();
    void hub.refresh();
    void studio.readPacks();
    void agents.refresh();
  }, []);
  const said = (outcome: ProfileOutcome) => setNote(outcome.kind === 'done' ? outcome.note : outcome.why);
  const list = profiles.profiles;
  if (list === undefined) return profiles.unreadable ? <ReadFailed what={JobsLines.readWhat} retry={() => void profiles.refresh()} /> : null;
  const kept = orderedProfiles(list.filter((each) => each.isDefault !== true));
  const defaults = list.filter((each) => each.isDefault === true);
  const templates = profiles.templates ?? [];
  return (
    <div className="flex flex-col gap-6">
      {note !== undefined && <Note>{note}</Note>}
      <div className="flex items-start gap-3">
        <p className="min-w-0 flex-1 text-footnote text-muted">{JobsLines.intro(words.keyTitle)}</p>
        <Button kind="primary" icon={Plus} onClick={() => setSheet({ kind: 'new' })}>
          {JobsLines.create}
        </Button>
      </div>
      {kept.length === 0 && defaults.length === 0 && <EmptyState icon={Briefcase} title={JobsLines.emptyTitle} body={JobsLines.emptyBody} />}
      {kept.length > 0 && (
        <Section title={JobsLines.jobs}>
          <CardGrid min={CARD_WIDTH}>
            {kept.map((profile) => (
              <JobCard key={profile.id} parts={parts} profile={profile} said={said} edit={() => setSheet({ kind: 'edit', profile })} />
            ))}
          </CardGrid>
        </Section>
      )}
      {defaults.length > 0 && (
        <Section title={JobsLines.defaults}>
          <CardGrid min={CARD_WIDTH}>
            {defaults.map((profile) => (
              <AgentProfileCard key={profile.id} profile={profile} giveJob={() => setSheet({ kind: 'job-for', profile })} />
            ))}
          </CardGrid>
        </Section>
      )}
      {templates.length > 0 && (
        <Section title={JobsLines.templates}>
          <CardGrid min={CARD_WIDTH}>
            {templates.map((template) => (
              <TemplateCard key={template.id} template={template} use={() => setSheet({ kind: 'template', template })} />
            ))}
          </CardGrid>
        </Section>
      )}
      {sheet !== undefined && sheet.kind === 'template' && <TemplateSheet parts={parts} template={sheet.template} close={() => setSheet(undefined)} said={said} />}
      {sheet !== undefined && sheet.kind !== 'template' && (
        <JobSheet
          parts={parts}
          {...(sheet.kind === 'edit' ? { editing: sheet.profile } : {})}
          {...(sheet.kind === 'job-for' ? { jobFor: sheet.profile } : {})}
          close={() => setSheet(undefined)}
          said={said}
        />
      )}
    </div>
  );
}

/** One kept job: its purpose, who answers for it, the agents it works through, what it bundles, and its presses. */
function JobCard({ parts, profile, said, edit }: { parts: SettingsParts; profile: ProfileView; said: (outcome: ProfileOutcome) => void; edit: () => void }) {
  const { profiles } = parts;
  const [open, setOpen] = useState<'apply' | 'bind' | 'remove' | undefined>(undefined);
  const busy = profiles.busy !== undefined;
  const bound = profile.connections.length > 0;
  const responsible = responsibleLine(profile);
  const done = (outcome: ProfileOutcome) => {
    said(outcome);
    if (outcome.kind === 'done') setOpen(undefined);
  };
  return (
    <Card label={profile.name} className={`flex flex-col gap-3 ${bound ? '' : 'opacity-70'}`}>
      <div className="flex items-center gap-2.5">
        <BrandLogo agent={profile.connections[0]?.agentKind} name={profile.name} size={CARD_LOGO} />
        <div className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-headline font-semibold text-foreground">{profile.name}</span>
          <span className="line-clamp-2 text-meta text-muted">{purposeLine(profile)}</span>
        </div>
      </div>
      {responsible !== undefined && <span className="text-meta text-muted">{responsible}</span>}
      {profile.responsibilities.length > 0 && <span className="text-meta text-muted">{profile.responsibilities.join(', ')}</span>}
      {bound ? (
        <div className="flex flex-col gap-1.5">
          {shownConnections(profile).map((connection) => {
            const agent = connectionAgent(connection);
            return (
              <span key={connection.id} className="flex items-center gap-2">
                <ConnectionPill connection={connection} />
                <span className="min-w-0 flex-1 truncate text-meta text-muted">{connectionStatusLine(connection)}</span>
                {agent !== undefined && (
                  <Button size="small" disabled={busy} title={JobsLines.unbindHint} onClick={() => void profiles.unbind(agent, profile.id).then(said)}>
                    {JobsLines.unbind}
                  </Button>
                )}
              </span>
            );
          })}
          <details>
            <summary className="mx-focus cursor-pointer text-footnote font-medium text-muted select-none">{JobsLines.howSure}</summary>
            <div className="pt-2">
              <CapabilityStrip levels={profile.levels} />
            </div>
          </details>
        </div>
      ) : (
        <StatusWord tone="quiet">{NO_AGENT}</StatusWord>
      )}
      <span className="text-meta text-muted">{profileContents(profile)}</span>
      {profile.missing.length > 0 && <span className="text-meta text-warm">{profile.missing.join(' ')}</span>}
      <div className="flex flex-wrap items-center gap-2">
        <Button icon={Play} disabled={busy} onClick={() => setOpen(open === 'apply' ? undefined : 'apply')}>
          {ProfilesLines.apply}
        </Button>
        <Button icon={Pencil} disabled={busy} onClick={edit}>
          {ProfilesLines.edit}
        </Button>
        <Button icon={Link2} disabled={busy} onClick={() => setOpen(open === 'bind' ? undefined : 'bind')}>
          {JobsLines.bind}
        </Button>
        <span className="flex-1" />
        <Button icon={Trash2} kind="quiet" disabled={busy} onClick={() => setOpen(open === 'remove' ? undefined : 'remove')}>
          {ProfilesLines.remove}
        </Button>
      </div>
      {open === 'remove' && (
        <div className="flex flex-col gap-2">
          <span className="text-footnote text-muted">{ProfilesLines.removeStays}</span>
          <div className="flex gap-2">
            <Button kind="danger" busy={busy} onClick={() => void profiles.remove(profile.id).then(done)}>
              {ProfilesLines.removeNamed(profile.name)}
            </Button>
            <Button onClick={() => setOpen(undefined)}>{ProfilesLines.cancel}</Button>
          </div>
        </div>
      )}
      {open === 'bind' && <BindForm parts={parts} busy={busy} cancel={() => setOpen(undefined)} bind={(agent) => void profiles.bind(profile.id, agent).then(done)} />}
      {open === 'apply' && <ApplyForm parts={parts} busy={busy} cancel={() => setOpen(undefined)} apply={(agent, project) => void profiles.apply(profile.id, agent, project).then(done)} />}
    </Card>
  );
}

/** An agent found here to put under the job; its record keeps its own key, so nothing it did is renamed. */
function BindForm({ parts, busy, cancel, bind }: { parts: SettingsParts; busy: boolean; cancel: () => void; bind: (agent: string) => void }) {
  const found = parts.agents.agents ?? [];
  const [agent, setAgent] = useState(found[0]?.kind ?? '');
  return (
    <div className="flex flex-col gap-2 border-t border-panel-edge pt-3">
      {found.length === 0 ? (
        <span className="text-footnote text-muted">{JobsLines.noAgentFound}</span>
      ) : (
        <Field label={ProfilesLines.agent}>
          <Select value={agent} label={ProfilesLines.agent} wide options={found.map((each) => ({ value: each.kind, label: each.name }))} onChange={setAgent} />
        </Field>
      )}
      <div className="flex gap-2">
        <Button kind="primary" icon={Link2} busy={busy} disabled={agent === ''} onClick={() => bind(agent)}>
          {busy ? JobsLines.binding : JobsLines.bindPress}
        </Button>
        <Button onClick={cancel}>{ProfilesLines.cancel}</Button>
      </div>
    </div>
  );
}

/** The agent a job goes to and the repository its skills are written into, or the agent's home folder. */
function ApplyForm({ parts, busy, cancel, apply }: { parts: SettingsParts; busy: boolean; cancel: () => void; apply: (agent: string, project: string) => void }) {
  const found = parts.agents.agents ?? [];
  const [agent, setAgent] = useState(found[0]?.kind ?? '');
  const [project, setProject] = useState('');
  return (
    <div className="flex flex-col gap-2 border-t border-panel-edge pt-3">
      {found.length === 0 ? (
        <span className="text-footnote text-muted">{JobsLines.noAgentFound}</span>
      ) : (
        <Field label={ProfilesLines.agent}>
          <Select value={agent} label={ProfilesLines.agent} wide options={found.map((each) => ({ value: each.kind, label: each.name }))} onChange={setAgent} />
        </Field>
      )}
      <Field label={ProfilesLines.repository} help={applyWhereLine(project)}>
        <Input value={project} placeholder={ProfilesLines.repositoryPlaceholder} onValue={setProject} />
      </Field>
      <div className="flex gap-2">
        <Button kind="primary" icon={Play} busy={busy} disabled={agent === ''} onClick={() => apply(agent, project)}>
          {busy ? ProfilesLines.applying : ProfilesLines.applyTo(found.find((each) => each.kind === agent)?.name)}
        </Button>
        <Button onClick={cancel}>{ProfilesLines.cancel}</Button>
      </div>
    </div>
  );
}

/** A job description with no agent behind it, drawn grey with no activity and no numbers. */
function TemplateCard({ template, use }: { template: ProfileTemplate; use: () => void }) {
  return (
    <Card label={`${template.name}, ${NO_AGENT}`} className="flex flex-col gap-3 opacity-75">
      <div className="flex items-center gap-2">
        <span className="min-w-0 flex-1 truncate text-headline font-semibold text-foreground">{template.name}</span>
        <StatusWord tone="quiet">{NO_AGENT}</StatusWord>
      </div>
      <p className="flex-1 text-footnote text-muted">{template.purpose}</p>
      <div>
        <Button icon={Copy} onClick={use}>
          {JobsLines.useTemplate}
        </Button>
      </div>
    </Card>
  );
}

/**
 * Copying a template: name the copy and tick the suggested skills to take. The suggested rules are shown in plain
 * words as proposals for the person to write as rules later; none is applied by the copy.
 */
export function TemplateSheet({ parts, template, close, said }: { parts: SettingsParts; template: ProfileTemplate; close: () => void; said: (outcome: ProfileOutcome) => void }) {
  const { profiles } = parts;
  useObserved(profiles);
  const [name, setName] = useState('');
  const [taken, setTaken] = useState<ReadonlySet<string>>(new Set());
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const keep = async () => {
    const outcome = await profiles.fromTemplate(template.id, name.trim() === '' ? template.name : name, template.suggestedSkills.filter((skill) => taken.has(skill)));
    if (outcome.kind === 'failed') return setProblem(outcome.why);
    said(outcome);
    close();
  };
  return (
    <Dialog
      title={JobsLines.useNamed(template.name)}
      close={close}
      actions={
        <Button kind="primary" busy={profiles.busy !== undefined} onClick={() => void keep()}>
          {JobsLines.keepTemplate}
        </Button>
      }
    >
      <Field label={ProfilesLines.name}>
        <Input value={name} placeholder={template.name} onValue={setName} />
      </Field>
      <Labelled label={JobsLines.purpose}>
        <p className="text-footnote text-muted">{template.purpose}</p>
      </Labelled>
      {template.responsibilities.length > 0 && (
        <Labelled label={JobsLines.responsibilities}>
          <ul className="flex flex-col gap-0.5 text-footnote text-muted">
            {template.responsibilities.map((each) => (
              <li key={each}>{each}</li>
            ))}
          </ul>
        </Labelled>
      )}
      {template.suggestedSkills.length > 0 && (
        <Labelled label={JobsLines.suggestedSkills}>
          {template.suggestedSkills.map((skill) => (
            <Checkbox key={skill} checked={taken.has(skill)} onToggle={() => setTaken(toggled(taken, skill))}>
              {skill}
            </Checkbox>
          ))}
        </Labelled>
      )}
      {template.suggestedRules.length > 0 && (
        <Labelled label={JobsLines.suggestedRules}>
          <ul className="flex flex-col gap-1">
            {template.suggestedRules.map((rule) => (
              <li key={rule} className="flex items-center gap-2 text-footnote text-foreground">
                <StatusWord tone="quiet">Off</StatusWord>
                {rule}
              </li>
            ))}
          </ul>
          <span className="text-footnote text-muted">{JobsLines.suggestedRulesNote}</span>
        </Labelled>
      )}
      <p className="text-footnote text-muted">{JobsLines.templateNoAgent}</p>
      {problem !== undefined && (
        <span role="alert" className="text-footnote text-destructive">
          {problem}
        </span>
      )}
    </Dialog>
  );
}

/**
 * A job kept new, edited, or given to an agent's default, which keeps the job and binds the agent in one press. The
 * skills, servers and pack ride along so an edit never drops them, since the runtime replaces a job whole.
 */
export function JobSheet({ parts, editing, jobFor, close, said }: { parts: SettingsParts; editing?: ProfileView; jobFor?: ProfileView; close: () => void; said: (outcome: ProfileOutcome) => void }) {
  const { profiles, skills, hub, studio } = parts;
  useObserved(profiles, skills, hub, studio);
  const packs = studio.packs ?? [];
  const [form, setForm] = useState<ProfileForm>(() => (editing !== undefined ? profileFormOf(editing, packs) : jobFor !== undefined ? jobFormFor(jobFor) : { name: '', description: '', skills: new Set(), servers: new Set(), pack: '' }));
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const set = (change: Partial<ProfileForm>) => setForm((before) => ({ ...before, ...change }));
  const skillNames = choiceNames((skills.hub?.skills ?? []).map((each) => each.name), new Set(editing?.skills ?? []));
  const serverNames = choiceNames((hub.hub?.servers ?? []).map((each) => each.name), new Set(editing?.mcpServers ?? []));
  const packLine = editing === undefined ? undefined : packChangeLine(editing.rulePack, form, packs);
  const agent = jobFor === undefined ? undefined : jobFor.connections.map(connectionAgent).find((each) => each !== undefined);
  const save = async () => {
    const draft = profileDraftFrom(form, packs);
    if (typeof draft === 'string') return setProblem(draft);
    const outcome = editing !== undefined ? await profiles.put(draft, true) : agent !== undefined ? await profiles.putAndBind(draft, agent) : await profiles.put(draft);
    if (outcome.kind === 'failed') return setProblem(outcome.why);
    said(outcome);
    close();
  };
  const title = editing !== undefined ? ProfilesLines.editNamed(editing.name) : jobFor !== undefined ? JobsLines.giveNamed(jobFor.name) : JobsLines.create;
  const press = editing !== undefined ? ProfilesLines.saveChanges : jobFor !== undefined ? JobsLines.giveThisJob : JobsLines.keepJob;
  return (
    <Dialog
      title={title}
      close={close}
      actions={
        <Button kind="primary" busy={profiles.busy !== undefined} onClick={() => void save()}>
          {press}
        </Button>
      }
    >
      {editing !== undefined ? (
        <Field label={ProfilesLines.name} help={ProfilesLines.nameStays}>
          <span className="text-body text-foreground">{editing.name}</span>
        </Field>
      ) : (
        <Field label={ProfilesLines.name}>
          <Input value={form.name} placeholder={ProfilesLines.namePlaceholder} onValue={(name) => set({ name })} />
        </Field>
      )}
      <Field label={JobsLines.purpose}>
        <Input value={form.purpose ?? ''} placeholder={JobsLines.purposePlaceholder} onValue={(purpose) => set({ purpose })} />
      </Field>
      <Field label={JobsLines.role}>
        <Input value={form.role ?? ''} placeholder={JobsLines.rolePlaceholder} onValue={(role) => set({ role })} />
      </Field>
      <Field label={JobsLines.responsibilities}>
        <Textarea grow value={form.responsibilities ?? ''} placeholder={JobsLines.responsibilitiesPlaceholder} onValue={(responsibilities) => set({ responsibilities })} />
      </Field>
      <Field label={JobsLines.instructions}>
        <Textarea grow value={form.instructions ?? ''} placeholder={JobsLines.instructionsPlaceholder} onValue={(instructions) => set({ instructions })} />
      </Field>
      <Field label={JobsLines.responsible} help={JobsLines.responsibleNote}>
        <Input value={form.responsiblePerson ?? ''} placeholder={JobsLines.responsiblePlaceholder} onValue={(responsiblePerson) => set({ responsiblePerson })} />
      </Field>
      <Choices label={ProfilesLines.hubSkills} empty={ProfilesLines.noSkills} names={skillNames} chosen={form.skills} toggle={(name) => set({ skills: toggled(form.skills, name) })} />
      <Choices label={ProfilesLines.hubServers} empty={ProfilesLines.noServers} names={serverNames} chosen={form.servers} toggle={(name) => set({ servers: toggled(form.servers, name) })} />
      <Field label={ProfilesLines.rulePack} {...(packLine === undefined ? {} : { help: packLine })}>
        <Select
          value={form.pack}
          label={ProfilesLines.rulePack}
          wide
          options={[{ value: '', label: ProfilesLines.noRulePack }, ...packs.map((pack) => ({ value: pack.id, label: ProfilesLines.packOption(pack.name, pack.ruleCount) }))]}
          onChange={(pack) => set({ pack })}
        />
      </Field>
      {problem !== undefined && (
        <span role="alert" className="text-footnote text-destructive">
          {problem}
        </span>
      )}
    </Dialog>
  );
}

function Choices({ label, empty, names, chosen, toggle }: { label: string; empty: string; names: readonly string[]; chosen: ReadonlySet<string>; toggle: (name: string) => void }) {
  return (
    <Labelled label={label}>
      {names.length === 0 ? (
        <span className="text-footnote text-muted">{empty}</span>
      ) : (
        names.map((name) => (
          <Checkbox key={name} checked={chosen.has(name)} onToggle={() => toggle(name)}>
            {name}
          </Checkbox>
        ))
      )}
    </Labelled>
  );
}

/** A group of choices under its label, which a `Field` cannot hold since its label would press the first. */
function Labelled({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      {children}
    </div>
  );
}

function toggled(set: ReadonlySet<string>, name: string): ReadonlySet<string> {
  const next = new Set(set);
  if (next.has(name)) next.delete(name);
  else next.add(name);
  return next;
}
