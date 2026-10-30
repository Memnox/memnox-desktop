import type { ProfileView } from '@memnox/core/wire';
import { Layers, Pencil, Play, Plus, Trash2 } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { ProfileOutcome } from '../../../core/application/profiles';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { applyWhereLine, choiceNames, packChangeLine, profileContents, profileDraftFrom, profileFormOf, type ProfileForm } from '../../../core/domain/profile-lines';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CardGrid, EmptyState, ReadFailed, ScopeChip, StatusWord } from '../widgets';
import { PROFILE_SCOPE } from '../../../core/domain/scope-lines';
import { Dialog, Labelled } from './SkillDialogs';

/**
 * Profiles under Workspaces: a named bundle of skills, servers and a rule pack. Keeping one gives nothing;
 * applying it to an agent raises a proposal for each piece, and each waits for a signature on the island.
 */
export function ProfilesPage({ parts }: { parts: SettingsParts }) {
  const { profiles, skills, hub, studio } = parts;
  useObserved(profiles, skills, hub, studio);
  useEffect(() => {
    void profiles.refresh();
    // The hubs and packs are what a profile is made from, and the agents what it is applied to.
    void skills.refresh();
    void hub.refresh();
    void studio.readPacks();
    void parts.projects.refresh();
  }, []);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [creating, setCreating] = useState(false);
  const said = (outcome: ProfileOutcome) => setNote(outcome.kind === 'failed' ? outcome.why : outcome.note);

  const list = profiles.profiles;
  if (list === undefined) return profiles.unreadable ? <ReadFailed what="the profiles" retry={() => void profiles.refresh()} /> : null;
  const create = (
    <KitButton kind="primary" icon={Plus} onClick={() => setCreating(true)}>
      New profile
    </KitButton>
  );
  return (
    <div className="flex flex-col gap-5">
      {note !== undefined && (
        <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {note}
        </p>
      )}
      <div className="flex items-center justify-between gap-3">
        <p className="text-footnote text-muted">{`A profile gives nothing until you apply it. Applying it waits for your signature with ${parts.words.keyTitle} on the island, once for each piece.`}</p>
        {create}
      </div>
      {list.length === 0 ? (
        <EmptyState icon={Layers} title="No profiles yet" body="Bundle the skills, servers and rule pack one kind of work needs, such as Backend Engineering, and apply it to any agent in one go." action={create} />
      ) : (
        <CardGrid>
          {list.map((profile) => (
            <ProfileCard key={profile.id} parts={parts} profile={profile} said={said} />
          ))}
        </CardGrid>
      )}
      {creating && <ProfileDialog parts={parts} close={() => setCreating(false)} said={said} />}
    </div>
  );
}

function ProfileCard({ parts, profile, said }: { parts: SettingsParts; profile: ProfileView; said: (outcome: ProfileOutcome) => void }) {
  const { profiles } = parts;
  const [applying, setApplying] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [editing, setEditing] = useState(false);
  const busy = profiles.busy === profile.id || profiles.busy === profile.name;
  return (
    <article className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
      <div className="flex items-start gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="truncate text-headline font-semibold text-foreground">{profile.name}</span>
          <span className="truncate text-footnote text-muted">{profileContents(profile)}</span>
        </div>
        <ScopeChip scope={PROFILE_SCOPE} />
      </div>
      {profile.description !== undefined && <p className="line-clamp-2 text-footnote text-foreground">{profile.description}</p>}
      {profile.skills.length > 0 && <p className="truncate text-footnote text-muted">{`Skills: ${profile.skills.join(', ')}`}</p>}
      {profile.mcpServers.length > 0 && <p className="truncate text-footnote text-muted">{`Servers: ${profile.mcpServers.join(', ')}`}</p>}
      {profile.missing.map((missing) => (
        <StatusWord key={missing} tone="attention">
          {missing}
        </StatusWord>
      ))}
      <div className="flex flex-wrap gap-2 border-t border-panel-edge pt-3">
        {!applying && (
          <KitButton icon={Play} onClick={() => setApplying(true)}>
            Apply
          </KitButton>
        )}
        <KitButton icon={Pencil} onClick={() => setEditing(true)}>
          Edit
        </KitButton>
        {removing ? (
          <>
            <KitButton kind="primary" icon={Trash2} disabled={busy} onClick={() => void profiles.remove(profile.id).then(said)}>
              {`Remove ${profile.name}`}
            </KitButton>
            <KitButton onClick={() => setRemoving(false)}>Cancel</KitButton>
          </>
        ) : (
          <KitButton icon={Trash2} onClick={() => setRemoving(true)}>
            Remove
          </KitButton>
        )}
      </div>
      {removing && <p className="text-footnote text-muted">What it already gave stays where it was given.</p>}
      {applying && (
        <ApplyForm
          parts={parts}
          busy={busy}
          cancel={() => setApplying(false)}
          apply={(agent, project) =>
            void profiles.apply(profile.id, agent, project).then((outcome) => {
              said(outcome);
              if (outcome.kind !== 'failed') setApplying(false);
            })
          }
        />
      )}
      {editing && <ProfileDialog parts={parts} editing={profile} close={() => setEditing(false)} said={said} />}
    </article>
  );
}

/** The agent a profile goes to and the repository its skills are written into, or the agent's home folder. */
function ApplyForm({ parts, busy, cancel, apply }: { parts: SettingsParts; busy: boolean; cancel: () => void; apply: (agent: string, project: string) => void }) {
  const { skills, projects } = parts;
  const agents = (skills.hub?.agents ?? []).filter((each) => each.installed);
  const [agent, setAgent] = useState(agents[0]?.agent ?? '');
  const [project, setProject] = useState('');
  const folders = projects.projects ?? [];
  const field = 'h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-footnote text-foreground outline-none placeholder:text-faint focus:border-primary';
  return (
    <div className="flex flex-col gap-2.5 border-t border-panel-edge pt-3">
      <Labelled label="Agent">
        <select className={field} value={agent} onChange={(event) => setAgent(event.target.value)}>
          {agents.map((each) => (
            <option key={each.agent} value={each.agent}>
              {each.label}
            </option>
          ))}
        </select>
      </Labelled>
      <Labelled label="Repository, optional">
        <input className={`${field} font-mono`} value={project} placeholder="/home/you/code/project" onChange={(event) => setProject(event.target.value)} />
      </Labelled>
      {folders.length > 0 && (
        <div className="flex flex-wrap gap-1.5" aria-label="Your projects">
          {folders.map((each) => (
            <button
              key={each.id}
              type="button"
              title={each.path}
              aria-pressed={project === each.path}
              onClick={() => setProject(project === each.path ? '' : each.path)}
              className={`mx-focus cursor-pointer rounded-full border px-2.5 py-1 text-footnote ${project === each.path ? 'border-primary text-foreground' : 'border-panel-edge text-muted hover:bg-hover'}`}
            >
              {each.name}
            </button>
          ))}
        </div>
      )}
      <p className="text-footnote text-muted">{applyWhereLine(project)}</p>
      <div className="flex gap-2">
        <KitButton kind="primary" icon={Play} disabled={busy || agent === ''} onClick={() => apply(agent, project)}>
          {busy ? 'Applying' : `Apply to ${agent === '' ? 'the agent' : agentLabel(agent)}`}
        </KitButton>
        <KitButton onClick={cancel}>Cancel</KitButton>
      </div>
    </div>
  );
}

const EMPTY_FORM: ProfileForm = { name: '', description: '', skills: new Set(), servers: new Set(), pack: '' };

/**
 * A profile chosen from what the Skills Hub, the MCP Hub and the rule packs hold now, new or as kept when `editing`;
 * saving grants nothing. An edit keeps the name, since the runtime finds a profile by it and a new name is a new profile.
 */
function ProfileDialog({ parts, editing, close, said }: { parts: SettingsParts; editing?: ProfileView; close: () => void; said: (outcome: ProfileOutcome) => void }) {
  const { profiles, skills, hub, studio } = parts;
  const packs = studio.packs ?? [];
  const [form, setForm] = useState<ProfileForm>(() => (editing === undefined ? EMPTY_FORM : profileFormOf(editing, packs)));
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);
  // Packs read after the dialog opened still match the kept pack, unless the person already chose one.
  const chosePack = useRef(false);
  useEffect(() => {
    if (editing === undefined || chosePack.current || form.pack !== '') return;
    const matched = profileFormOf(editing, packs).pack;
    if (matched !== '') setForm((now) => ({ ...now, pack: matched }));
  }, [studio.packs]);
  const toggle = (which: 'skills' | 'servers', name: string) => {
    const next = new Set(form[which]);
    if (next.has(name)) next.delete(name);
    else next.add(name);
    setForm({ ...form, [which]: next });
  };
  const save = async () => {
    const draft = profileDraftFrom(form, packs);
    if (typeof draft === 'string') return setProblem(draft);
    const outcome = await profiles.put(draft, editing !== undefined);
    if (outcome.kind === 'failed') return setProblem(outcome.why);
    said(outcome);
    close();
  };
  const field = 'h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-body text-foreground outline-none placeholder:text-faint focus:border-primary';
  const skillNames = choiceNames((skills.hub?.skills ?? []).map((skill) => skill.name), editing === undefined ? new Set() : new Set(editing.skills));
  const serverNames = choiceNames((hub.hub?.servers ?? []).map((server) => server.name), editing === undefined ? new Set() : new Set(editing.mcpServers));
  const packChange = editing === undefined ? undefined : packChangeLine(editing.rulePack, form, packs);
  return (
    <Dialog
      title={editing === undefined ? 'New profile' : `Edit ${editing.name}`}
      close={close}
      footer={
        <>
          <span className="flex-1" />
          <KitButton kind="primary" disabled={profiles.busy !== undefined} onClick={() => void save()}>
            {editing === undefined ? 'Keep profile' : 'Save changes'}
          </KitButton>
        </>
      }
    >
      <Labelled label="Name">
        <input ref={editing === undefined ? first : undefined} className={field} value={form.name} readOnly={editing !== undefined} onChange={(event) => setForm({ ...form, name: event.target.value })} placeholder="Backend Engineering" />
      </Labelled>
      {editing !== undefined && <p className="text-footnote text-muted">The name stays, since a new name would keep a second profile beside this one.</p>}
      <Labelled label="What it is for, optional">
        <input ref={editing === undefined ? undefined : first} className={field} value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} placeholder="Reviews, release notes and the local database" />
      </Labelled>
      <Choices title="Skills from the Skills Hub" empty="The Skills Hub holds no skill yet." names={skillNames} chosen={form.skills} toggle={(name) => toggle('skills', name)} />
      <Choices title="Servers from the MCP Hub" empty="The MCP Hub holds no server yet." names={serverNames} chosen={form.servers} toggle={(name) => toggle('servers', name)} />
      <Labelled label="Rule pack">
        <select className={field} value={form.pack} onChange={(event) => {
            chosePack.current = true;
            setForm({ ...form, pack: event.target.value });
          }}>
          <option value="">No rule pack</option>
          {packs.map((pack) => (
            <option key={pack.id} value={pack.id}>
              {`${pack.name}, ${pack.ruleCount === 1 ? '1 rule' : `${pack.ruleCount} rules`}`}
            </option>
          ))}
        </select>
      </Labelled>
      {packChange !== undefined && <p className="text-footnote text-muted">{packChange}</p>}
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
    </Dialog>
  );
}

function Choices({ title, empty, names, chosen, toggle }: { title: string; empty: string; names: readonly string[]; chosen: ReadonlySet<string>; toggle: (name: string) => void }) {
  return (
    <fieldset className="flex flex-col gap-1.5">
      <legend className="pb-1.5 text-footnote font-medium text-muted">{title}</legend>
      {names.length === 0 ? (
        <p className="text-footnote text-muted">{empty}</p>
      ) : (
        <div className="flex flex-wrap gap-x-4 gap-y-1.5">
          {names.map((name) => (
            <label key={name} className="flex cursor-pointer items-center gap-2 text-body text-foreground">
              <input type="checkbox" checked={chosen.has(name)} onChange={() => toggle(name)} />
              {name}
            </label>
          ))}
        </div>
      )}
    </fieldset>
  );
}
