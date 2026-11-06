import type { ProfileView } from '@memnox/core/wire';
import { Layers, Pencil, Play, Plus, Trash2 } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { ProfileOutcome } from '../../../core/application/profiles';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { applyWhereLine, choiceNames, ProfilesLines, packChangeLine, profileContents, profileDraftFrom, profileFormOf, type ProfileForm } from '../../../core/domain/profile-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { ScopeChip } from '../widgets';
import { PROFILE_SCOPE } from '../../../core/domain/scope-lines';
import { Button, Card, CardGrid, Checkbox, Dialog, EmptyState, ErrorLine, Field, Input, Note, ReadFailed, Select, StatusWord } from '../../kit';

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
  if (list === undefined) return profiles.unreadable ? <ReadFailed what={ProfilesLines.readWhat} retry={() => void profiles.refresh()} /> : null;
  const create = (
    <Button kind="primary" icon={Plus} onClick={() => setCreating(true)}>
      {ProfilesLines.create}
    </Button>
  );
  return (
    <div className="flex flex-col gap-5">
      {note !== undefined && <Note>{note}</Note>}
      <div className="flex items-center justify-between gap-3">
        <p className="text-footnote text-muted">{ProfilesLines.intro(parts.words.keyTitle)}</p>
        {create}
      </div>
      {list.length === 0 ? (
        <EmptyState icon={Layers} title={ProfilesLines.emptyTitle} body={ProfilesLines.emptyBody} action={create} />
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
    <Card as="article" className="flex flex-col gap-3">
      <div className="flex items-start gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="truncate text-headline font-semibold text-foreground">{profile.name}</span>
          <span className="truncate text-footnote text-muted">{profileContents(profile)}</span>
        </div>
        <ScopeChip scope={PROFILE_SCOPE} />
      </div>
      {profile.description !== undefined && <p className="line-clamp-2 text-footnote text-foreground">{profile.description}</p>}
      {profile.skills.length > 0 && <p className="truncate text-footnote text-muted">{ProfilesLines.skills(profile.skills)}</p>}
      {profile.mcpServers.length > 0 && <p className="truncate text-footnote text-muted">{ProfilesLines.servers(profile.mcpServers)}</p>}
      {profile.missing.map((missing) => (
        <StatusWord key={missing} tone="attention">
          {missing}
        </StatusWord>
      ))}
      <div className="flex flex-wrap gap-2 border-t border-panel-edge pt-3">
        {!applying && (
          <Button icon={Play} onClick={() => setApplying(true)}>
            {ProfilesLines.apply}
          </Button>
        )}
        <Button icon={Pencil} onClick={() => setEditing(true)}>
          {ProfilesLines.edit}
        </Button>
        {removing ? (
          <>
            <Button kind="primary" icon={Trash2} disabled={busy} onClick={() => void profiles.remove(profile.id).then(said)}>
              {ProfilesLines.removeNamed(profile.name)}
            </Button>
            <Button onClick={() => setRemoving(false)}>{ProfilesLines.cancel}</Button>
          </>
        ) : (
          <Button icon={Trash2} onClick={() => setRemoving(true)}>
            {ProfilesLines.remove}
          </Button>
        )}
      </div>
      {removing && <p className="text-footnote text-muted">{ProfilesLines.removeStays}</p>}
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
    </Card>
  );
}

/** The agent a profile goes to and the repository its skills are written into, or the agent's home folder. */
function ApplyForm({ parts, busy, cancel, apply }: { parts: SettingsParts; busy: boolean; cancel: () => void; apply: (agent: string, project: string) => void }) {
  const { skills, projects } = parts;
  const agents = (skills.hub?.agents ?? []).filter((each) => each.installed);
  const [agent, setAgent] = useState(agents[0]?.agent ?? '');
  const [project, setProject] = useState('');
  const folders = projects.projects ?? [];
  return (
    <div className="flex flex-col gap-2.5 border-t border-panel-edge pt-3">
      <Field label={ProfilesLines.agent}>
        <Select look="field" wide value={agent} options={agents.map((each) => ({ value: each.agent, label: each.label }))} onChange={setAgent} label={ProfilesLines.agent} />
      </Field>
      <Field label={ProfilesLines.repository}>
        <Input wide mono value={project} placeholder={ProfilesLines.repositoryPlaceholder} onValue={setProject} />
      </Field>
      {folders.length > 0 && (
        <div className="flex gap-1.5 overflow-x-auto [scrollbar-width:none]" role="group" aria-label={ProfilesLines.yourProjects}>
          {folders.map((each) => (
            // The Mac marks the chosen project as its primary button, the rest secondary.
            <Button key={each.id} kind={project === each.path ? 'primary' : 'secondary'} title={each.path} aria-pressed={project === each.path} onClick={() => setProject(project === each.path ? '' : each.path)}>
              {each.name}
            </Button>
          ))}
        </div>
      )}
      <p className="text-footnote text-muted">{applyWhereLine(project)}</p>
      <div className="flex gap-2">
        <Button kind="primary" icon={Play} disabled={busy || agent === ''} onClick={() => apply(agent, project)}>
          {busy ? ProfilesLines.applying : ProfilesLines.applyTo(agent === '' ? undefined : agentLabel(agent))}
        </Button>
        <Button onClick={cancel}>{ProfilesLines.cancel}</Button>
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
  const skillNames = choiceNames((skills.hub?.skills ?? []).map((skill) => skill.name), editing === undefined ? new Set() : new Set(editing.skills));
  const serverNames = choiceNames((hub.hub?.servers ?? []).map((server) => server.name), editing === undefined ? new Set() : new Set(editing.mcpServers));
  const packChange = editing === undefined ? undefined : packChangeLine(editing.rulePack, form, packs);
  return (
    <Dialog
      title={editing === undefined ? ProfilesLines.create : ProfilesLines.editNamed(editing.name)}
      close={close}
      actions={
        <>
          <span className="flex-1" />
          <Button kind="primary" disabled={profiles.busy !== undefined} onClick={() => void save()}>
            {editing === undefined ? ProfilesLines.keep : ProfilesLines.saveChanges}
          </Button>
        </>
      }
    >
      <Field label={ProfilesLines.name} help={editing === undefined ? undefined : ProfilesLines.nameStays}>
        <Input ref={editing === undefined ? first : undefined} wide value={form.name} readOnly={editing !== undefined} onValue={(name) => setForm({ ...form, name })} placeholder={ProfilesLines.namePlaceholder} />
      </Field>
      <Field label={ProfilesLines.description}>
        <Input ref={editing === undefined ? undefined : first} wide value={form.description} onValue={(description) => setForm({ ...form, description })} placeholder={ProfilesLines.descriptionPlaceholder} />
      </Field>
      <Choices title={ProfilesLines.hubSkills} empty={ProfilesLines.noSkills} names={skillNames} chosen={form.skills} toggle={(name) => toggle('skills', name)} />
      <Choices title={ProfilesLines.hubServers} empty={ProfilesLines.noServers} names={serverNames} chosen={form.servers} toggle={(name) => toggle('servers', name)} />
      <Field label={ProfilesLines.rulePack} help={packChange}>
        <Select
          look="field"
          wide
          value={form.pack}
          none={ProfilesLines.noRulePack}
          options={packs.map((pack) => ({ value: pack.id, label: ProfilesLines.packOption(pack.name, pack.ruleCount) }))}
          label={ProfilesLines.rulePack}
          onChange={(pack) => {
            chosePack.current = true;
            setForm({ ...form, pack });
          }}
        />
      </Field>
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
    </Dialog>
  );
}

/** The names a hub holds, each ticked into the profile or not. */
function Choices({ title, empty, names, chosen, toggle }: { title: string; empty: string; names: readonly string[]; chosen: ReadonlySet<string>; toggle: (name: string) => void }) {
  return (
    <fieldset className="flex flex-col gap-1.5">
      <legend className="pb-1.5 text-footnote font-medium text-muted">{title}</legend>
      {names.length === 0 ? (
        <p className="text-footnote text-muted">{empty}</p>
      ) : (
        <div className="flex flex-wrap gap-x-4 gap-y-1.5">
          {names.map((name) => (
            <Checkbox key={name} checked={chosen.has(name)} onToggle={() => toggle(name)}>
              {name}
            </Checkbox>
          ))}
        </div>
      )}
    </fieldset>
  );
}
